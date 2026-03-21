import Foundation

enum CodexAppServerError: Error {
    case notRunning
    case launchFailed
    case responseError(code: Int?, message: String)
    case malformedResponse
}

final class CodexAppServer: @unchecked Sendable {
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

    private let processQueue = DispatchQueue(label: "cxswitch.codex-app-server.process")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var listenTask: Task<Void, Never>?
    private var nextId: Int = 1
    private var notificationHandler: ((ServerNotification) -> Void)?

    private var isInitialized = false
    private let pending = PendingRequestStore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {}

    func start() throws {
        if process?.isRunning == true {
            return
        }
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
        stderrHandle = pipeErr.fileHandleForReading

        listenTask = Task { [weak self] in
            await self?.listen()
        }
    }

    func shutdown() {
        processQueue.sync {
            process?.terminate()
            process = nil
        }
        isInitialized = false
        listenTask?.cancel()
        listenTask = nil
    }

    func restart() throws {
        shutdown()
        try start()
    }

    func setNotificationHandler(_ handler: ((ServerNotification) -> Void)?) {
        processQueue.sync {
            notificationHandler = handler
        }
    }

    func initialize(clientName: String = "cx-switch", version: String = "0.1.0") async throws {
        if isInitialized { return }
        let params = InitializeParams(clientInfo: ClientInfo(name: clientName, version: version), protocolVersion: 2)
        _ = try await sendRequest(method: "initialize", params: params) as EmptyResult
        isInitialized = true
    }

    func sendRequest<T: Decodable>(method: String, params: Encodable? = nil) async throws -> T {
        guard process?.isRunning == true else {
            throw CodexAppServerError.notRunning
        }
        let id = nextRequestId()
        let request = JSONRPCRequest(id: id, method: method, params: params.map { EncodableValue($0) })
        let data = try encoder.encode(request)
        try writeLine(data)

        let resultData = try await pending.wait(for: id)
        return try decoder.decode(T.self, from: resultData)
    }

    func sendNotification(method: String, params: Encodable? = nil) throws {
        guard process?.isRunning == true else {
            throw CodexAppServerError.notRunning
        }
        let envelope = JSONRPCNotification(method: method, params: params.map { EncodableValue($0) })
        let data = try encoder.encode(envelope)
        try writeLine(data)
    }

    private func nextRequestId() -> Int {
        processQueue.sync {
            let id = nextId
            nextId += 1
            return id
        }
    }

    private func writeLine(_ data: Data) throws {
        guard let handle = stdinHandle else {
            throw CodexAppServerError.notRunning
        }
        var line = data
        line.append(0x0A)
        try handle.write(contentsOf: line)
    }

    private func listen() async {
        guard let handle = stdoutHandle else {
            return
        }
        do {
            for try await line in handle.bytes.lines {
                guard let data = line.data(using: String.Encoding.utf8) else {
                    continue
                }
                handleResponse(data)
            }
        } catch {
            return
        }
    }

    private func handleResponse(_ data: Data) {
        guard let envelope = try? decoder.decode(JSONRPCEnvelope.self, from: data) else {
            NSLog("[CodexAppServer] failed to decode: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            return
        }

        if let method = envelope.method, envelope.id == nil {
            processQueue.sync {
                notificationHandler?(ServerNotification(method: method, paramsData: envelope.params?.rawData))
            }
            return
        }

        if let id = envelope.id, id != 0 {
            if let error = envelope.error {
                let message = error.message ?? "Unknown error"
                pending.fail(id: id, error: CodexAppServerError.responseError(code: error.code, message: message))
                return
            }
            if let result = envelope.result {
                if let resultData = result.rawData {
                    pending.fulfill(id: id, data: resultData)
                } else {
                    pending.fail(id: id, error: CodexAppServerError.malformedResponse)
                }
                return
            }
        }

        if let id = envelope.id, id == 0 {
            return
        }
    }
}

struct ServerNotification {
    let method: String
    let paramsData: Data?
}

private final class PendingRequestStore {
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
}

private struct EmptyResult: Decodable {}

private struct EncodableValue: Encodable {
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
        if let data = try? container.decode(Data.self) {
            rawData = data
            return
        }
        if let dict = try? container.decode([String: AnyDecodable].self) {
            rawData = try? JSONSerialization.data(withJSONObject: dict.mapValues { $0.anyValue }, options: [.fragmentsAllowed])
            return
        }
        if let array = try? container.decode([AnyDecodable].self) {
            rawData = try? JSONSerialization.data(withJSONObject: array.map { $0.anyValue }, options: [.fragmentsAllowed])
            return
        }
        if let string = try? container.decode(String.self) {
            rawData = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
            return
        }
        if let number = try? container.decode(Double.self) {
            rawData = try? JSONSerialization.data(withJSONObject: number, options: [.fragmentsAllowed])
            return
        }
        if let bool = try? container.decode(Bool.self) {
            rawData = try? JSONSerialization.data(withJSONObject: bool, options: [.fragmentsAllowed])
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
