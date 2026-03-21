type JsonPrimitive = null | boolean | number | string;
type JsonValue =
  | JsonPrimitive
  | JsonValue[]
  | {
      [key: string]: JsonValue;
    };

type PendingRequest = {
  resolve: (value: JsonValue) => void;
  reject: (reason?: unknown) => void;
  timeout: ReturnType<typeof setTimeout>;
};

type JsonRpcMessage = {
  id?: number;
  result?: JsonValue;
  error?: {
    code?: number;
    message?: string;
  };
  method?: string;
  params?: JsonValue;
};

export type AppServerNotification = {
  method: string;
  params: JsonValue;
};

export class CodexAppServerClient {
  private process: Bun.Subprocess<"pipe", "pipe", "pipe"> | null = null;
  private isInitialized = false;
  private startPromise: Promise<void> | null = null;
  private nextRequestId = 1;
  private pending = new Map<number, PendingRequest>();
  private listeners = new Set<(notification: AppServerNotification) => void>();

  async request<T extends JsonValue>(
    method: string,
    params: JsonValue,
    timeoutMs = 20_000,
  ): Promise<T> {
    await this.ensureStarted();
    return this.sendRequestDirect<T>(method, params, timeoutMs);
  }

  onNotification(
    listener: (notification: AppServerNotification) => void,
  ): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  waitForNotification<T extends JsonValue>(
    method: string,
    predicate: (params: JsonValue) => boolean,
    timeoutMs: number,
  ): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const timeout = setTimeout(() => {
        unsubscribe();
        reject(new Error(`Timed out waiting for ${method}.`));
      }, timeoutMs);

      const unsubscribe = this.onNotification((notification) => {
        if (notification.method !== method || !predicate(notification.params)) {
          return;
        }

        clearTimeout(timeout);
        unsubscribe();
        resolve(notification.params as T);
      });
    });
  }

  async restart(): Promise<void> {
    await this.shutdown();
    await this.ensureStarted();
  }

  async shutdown(): Promise<void> {
    if (!this.process) {
      return;
    }

    const activeProcess = this.process;
    this.process = null;
    this.isInitialized = false;
    this.startPromise = null;

    try {
      activeProcess.kill();
      await activeProcess.exited;
    } catch {
      // Best effort.
    } finally {
      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timeout);
        pending.reject(new Error("Codex app-server stopped."));
        this.pending.delete(id);
      }
    }
  }

  private async ensureStarted(): Promise<void> {
    if (this.isInitialized && this.process) {
      return;
    }

    if (!this.startPromise) {
      this.startPromise = this.start();
    }

    await this.startPromise;
  }

  private async start(): Promise<void> {
    const started = await this.spawnWithRetry();

    this.process = started;
    this.attachStream(started.stdout, (line) => {
      this.handleStdout(line);
    });
    this.attachStream(started.stderr, (line) => {
      if (line.trim()) {
        console.warn(`[codex app-server] ${line}`);
      }
    });

    void started.exited.then(() => {
      if (this.process !== started) {
        return;
      }

      this.process = null;
      this.isInitialized = false;
      this.startPromise = null;

      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timeout);
        pending.reject(new Error("Codex app-server exited unexpectedly."));
        this.pending.delete(id);
      }
    });

    try {
      await this.sendRequestDirect("initialize", {
        clientInfo: {
          name: "cx-switch",
          version: "0.1.0",
        },
        protocolVersion: 2,
      }, 15_000);
      this.isInitialized = true;
    } catch (error) {
      await this.shutdown();
      throw error;
    } finally {
      this.startPromise = null;
    }
  }

  private async spawnWithRetry(
    attempts = 3,
    delayMs = 250,
  ): Promise<Bun.Subprocess<"pipe", "pipe", "pipe">> {
    let lastError: unknown = null;

    for (let attempt = 0; attempt < attempts; attempt += 1) {
      try {
        return Bun.spawn({
          cmd: ["codex", "app-server", "--listen", "stdio://"],
          stdin: "pipe",
          stdout: "pipe",
          stderr: "pipe",
        });
      } catch (error) {
        lastError = error;
        const message = error instanceof Error ? error.message : String(error);
        const errno = error && typeof error === "object" && "errno" in error
          ? (error as { errno?: unknown }).errno
          : null;
        if (errno !== -35 && !message.includes("EAGAIN")) {
          break;
        }

        if (attempt < attempts - 1) {
          await new Promise((resolve) => {
            setTimeout(resolve, delayMs * (attempt + 1));
          });
          continue;
        }
      }
    }

    throw new Error(
      lastError instanceof Error
        ? lastError.message
        : "Failed to start codex app-server.",
    );
  }

  private async sendRequestDirect<T extends JsonValue>(
    method: string,
    params: JsonValue,
    timeoutMs: number,
  ): Promise<T> {
    if (!this.process?.stdin) {
      throw new Error("Codex app-server stdin is unavailable.");
    }

    const id = this.nextRequestId++;
    const payload = JSON.stringify({ id, method, params });
    const response = new Promise<T>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timed out waiting for ${method}.`));
      }, timeoutMs);

      this.pending.set(id, {
        resolve: (value) => resolve(value as T),
        reject,
        timeout,
      });
    });

    this.process.stdin.write(`${payload}\n`);
    return response;
  }

  private attachStream(
    stream: ReadableStream<Uint8Array>,
    onLine: (line: string) => void,
  ): void {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    const pump = async () => {
      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          const finalLine = buffer.trim();
          if (finalLine) {
            onLine(finalLine);
          }
          break;
        }

        buffer += decoder.decode(value, { stream: true });
        while (true) {
          const newlineIndex = buffer.indexOf("\n");
          if (newlineIndex === -1) {
            break;
          }

          const line = buffer.slice(0, newlineIndex).trim();
          buffer = buffer.slice(newlineIndex + 1);
          if (line) {
            onLine(line);
          }
        }
      }
    };

    void pump().catch((error) => {
      console.warn("Failed to read codex app-server stream:", error);
    });
  }

  private handleStdout(line: string): void {
    let message: JsonRpcMessage;
    try {
      message = JSON.parse(line) as JsonRpcMessage;
    } catch {
      console.warn("Failed to parse codex app-server message:", line);
      return;
    }

    if (typeof message.id === "number") {
      const pending = this.pending.get(message.id);
      if (!pending) {
        return;
      }

      clearTimeout(pending.timeout);
      this.pending.delete(message.id);

      if (message.error) {
        pending.reject(
          new Error(message.error.message || "Codex app-server request failed."),
        );
        return;
      }

      pending.resolve((message.result ?? null) as JsonValue);
      return;
    }

    if (typeof message.method === "string") {
      const notification: AppServerNotification = {
        method: message.method,
        params: (message.params ?? null) as JsonValue,
      };

      for (const listener of this.listeners) {
        listener(notification);
      }
    }
  }
}
