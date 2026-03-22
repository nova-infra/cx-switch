import Foundation

protocol CodexAppServering: Sendable {
    func start() throws
    func shutdown()
    func restart() throws
    func restartAndInitialize() async throws
    func setNotificationHandler(_ handler: ((ServerNotification) -> Void)?)
    func initialize(clientName: String, version: String) async throws
    func sendRequest<T: Decodable>(method: String, params: Encodable?) async throws -> T
    func sendNotification(method: String, params: Encodable?) throws
}

extension CodexAppServering {
    func initialize() async throws {
        try await initialize(clientName: "cx-switch", version: "0.1.0")
    }
}

enum CodexAppServerError: Error, LocalizedError {
    case notRunning
    case launchFailed
    case responseError(code: Int?, message: String)
    case malformedResponse
    case requestTimeout

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Codex app-server is not running."
        case .launchFailed: return "Failed to start codex app-server."
        case .responseError(_, let message): return message
        case .malformedResponse: return "Malformed response from codex app-server."
        case .requestTimeout: return "Request to codex app-server timed out."
        }
    }
}

final class CodexAppServer: CodexAppServering, @unchecked Sendable {
    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }

    struct InitializeParams: Encodable {
        let clientInfo: ClientInfo
        let protocolVersion: Int
    }

    private struct JSONRPCRequest: Encodable {
        let jsonrpc: String = "2.0"
        let id: Int
        let method: String
        let params: EncodableValue

        init(id: Int, method: String, params: EncodableValue?) {
            self.id = id
            self.method = method
            self.params = params ?? EncodableValue(EmptyParams())
        }
    }

    private struct EmptyParams: Encodable {}

    private struct JSONRPCNotification: Encodable {
        let jsonrpc: String = "2.0"
        let method: String
        let params: EncodableValue

        init(method: String, params: EncodableValue?) {
            self.method = method
            self.params = params ?? EncodableValue(EmptyParams())
        }
    }

    private struct JSONRPCErrorBody: Decodable {
        let code: Int?
        let message: String?
    }

    private struct JSONRPCEnvelope: Decodable {
        let id: Int?
        let result: AnyDecodable?
        let error: JSONRPCErrorBody?
        let method: String?
        let params: AnyDecodable?
    }

    /// All mutable state accessed only through this queue
    private let queue = DispatchQueue(label: "cxswitch.codex-app-server")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var listenTask: Task<Void, Never>?
    private var nextId: Int = 1
    private var isInitialized = false
    private var notificationHandler: ((ServerNotification) -> Void)?

    private let pending = PendingRequestStore()
    private static let requestTimeoutNs: UInt64 = 20_000_000_000 // 20 seconds

    init() {}

    func start() throws {
        try queue.sync {
            if process?.isRunning == true { return }
            isInitialized = false

            let pipeIn = Pipe()
            let pipeOut = Pipe()
            let pipeErr = Pipe()

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["codex", "app-server", "--listen", "stdio://"]
            proc.standardInput = pipeIn
            proc.standardOutput = pipeOut
            proc.standardError = pipeErr

            do {
                try proc.run()
                NSLog("[CodexAppServer] process started, pid=\(proc.processIdentifier)")
            } catch {
                NSLog("[CodexAppServer] launch failed: \(error)")
                throw CodexAppServerError.launchFailed
            }

            process = proc
            stdinHandle = pipeIn.fileHandleForWriting
            stdoutHandle = pipeOut.fileHandleForReading

            let handle = pipeOut.fileHandleForReading
            listenTask = Task { [weak self] in
                await self?.listen(handle: handle)
            }
        }
    }

    func shutdown() {
        queue.sync {
            process?.terminate()
            process = nil
            stdinHandle = nil
            stdoutHandle = nil
            isInitialized = false
            listenTask?.cancel()
            listenTask = nil
        }
        // Fail all pending requests so continuations are always resumed
        pending.failAll(error: CodexAppServerError.notRunning)
    }

    func restart() throws {
        shutdown()
        try start()
    }

    func restartAndInitialize() async throws {
        shutdown()
        try await Task.sleep(nanoseconds: 500_000_000)
        try start()
        try await initialize()
    }

    func setNotificationHandler(_ handler: ((ServerNotification) -> Void)?) {
        queue.sync {
            notificationHandler = handler
        }
    }

    func initialize(clientName: String = "cx-switch", version: String = "0.1.0") async throws {
        let alreadyDone = queue.sync { isInitialized }
        if alreadyDone { return }
        let params = InitializeParams(clientInfo: ClientInfo(name: clientName, version: version), protocolVersion: 2)
        _ = try await sendRequest(method: "initialize", params: params) as EmptyResult
        queue.sync { isInitialized = true }
    }

    func sendRequest<T: Decodable>(method: String, params: Encodable? = nil) async throws -> T {
        let isRunning = queue.sync { process?.isRunning == true }
        guard isRunning else { throw CodexAppServerError.notRunning }

        let id = queue.sync { () -> Int in
            let current = nextId
            nextId += 1
            return current
        }

        let request = JSONRPCRequest(id: id, method: method, params: params.map { EncodableValue($0) })
        // Create encoder per call — JSONEncoder is not thread-safe
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        try queue.sync {
            guard let handle = stdinHandle else { throw CodexAppServerError.notRunning }
            var line = data
            line.append(0x0A)
            try handle.write(contentsOf: line)
        }

        // Wait with timeout
        let resultData = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.pending.wait(for: id)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.requestTimeoutNs)
                throw CodexAppServerError.requestTimeout
            }
            guard let result = try await group.next() else {
                throw CodexAppServerError.requestTimeout
            }
            group.cancelAll()
            return result
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: resultData)
    }

    func sendNotification(method: String, params: Encodable? = nil) throws {
        try queue.sync {
            guard process?.isRunning == true else { throw CodexAppServerError.notRunning }
            let envelope = JSONRPCNotification(method: method, params: params.map { EncodableValue($0) })
            let encoder = JSONEncoder()
            let data = try encoder.encode(envelope)
            guard let handle = stdinHandle else { throw CodexAppServerError.notRunning }
            var line = data
            line.append(0x0A)
            try handle.write(contentsOf: line)
        }
    }

    private func listen(handle: FileHandle) async {
        let decoder = JSONDecoder()
        do {
            for try await line in handle.bytes.lines {
                guard let data = line.data(using: .utf8) else { continue }
                handleResponse(data, decoder: decoder)
            }
        } catch {
            // Stream ended (process terminated)
        }
        // Process exited — fail any remaining pending requests
        pending.failAll(error: CodexAppServerError.notRunning)
    }

    private func handleResponse(_ data: Data, decoder: JSONDecoder) {
        guard let envelope = try? decoder.decode(JSONRPCEnvelope.self, from: data) else {
            NSLog("[CodexAppServer] failed to decode: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            return
        }

        // Notification (no id)
        if let method = envelope.method, envelope.id == nil {
            queue.sync {
                notificationHandler?(ServerNotification(method: method, paramsData: envelope.params?.rawData))
            }
            return
        }

        // Response with id
        if let id = envelope.id, id > 0 {
            if let error = envelope.error {
                pending.fail(id: id, error: CodexAppServerError.responseError(code: error.code, message: error.message ?? "Unknown error"))
            } else if let result = envelope.result, let resultData = result.rawData {
                pending.fulfill(id: id, data: resultData)
            } else {
                pending.fail(id: id, error: CodexAppServerError.malformedResponse)
            }
        }
    }
}

struct ServerNotification {
    let method: String
    let paramsData: Data?
}

/// Thread-safe store for pending request continuations.
private final class PendingRequestStore: @unchecked Sendable {
    private var continuations: [Int: CheckedContinuation<Data, Error>] = [:]
    private let lock = NSLock()

    func wait(for id: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
        }
    }

    func fulfill(id: Int, data: Data) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(returning: data)
    }

    func fail(id: Int, error: Error) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    /// Fail all pending continuations (e.g. on shutdown or process exit).
    func failAll(error: Error) {
        lock.lock()
        let all = continuations
        continuations.removeAll()
        lock.unlock()
        for (_, continuation) in all {
            continuation.resume(throwing: error)
        }
    }
}

private struct EmptyResult: Decodable {}

private struct EncodableValue: Encodable, @unchecked Sendable {
    private let encodeBlock: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encodeBlock = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeBlock(encoder)
    }
}

private struct AnyDecodable: Decodable {
    let rawData: Data?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try structured types first (dict/array), then primitives
        if let dict = try? container.decode([String: AnyDecodable].self) {
            rawData = try? JSONSerialization.data(withJSONObject: dict.mapValues { $0.anyValue }, options: [.fragmentsAllowed])
            return
        }
        if let array = try? container.decode([AnyDecodable].self) {
            rawData = try? JSONSerialization.data(withJSONObject: array.map { $0.anyValue }, options: [.fragmentsAllowed])
            return
        }
        if let bool = try? container.decode(Bool.self) {
            rawData = try? JSONSerialization.data(withJSONObject: bool, options: [.fragmentsAllowed])
            return
        }
        if let number = try? container.decode(Double.self) {
            rawData = try? JSONSerialization.data(withJSONObject: number, options: [.fragmentsAllowed])
            return
        }
        if let string = try? container.decode(String.self) {
            rawData = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
            return
        }
        rawData = nil
    }

    var anyValue: Any {
        if let rawData,
           let json = try? JSONSerialization.jsonObject(with: rawData, options: [.fragmentsAllowed]) {
            return json
        }
        return NSNull()
    }
}
