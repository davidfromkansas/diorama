import Foundation
import Darwin

public enum WireValue: Codable, Sendable, Equatable {
    case object([String: WireValue]), array([WireValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: WireValue].self) { self = .object(v) }
        else { self = .array(try c.decode([WireValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> WireValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var array: [WireValue] { if case .array(let v) = self { return v }; return [] }
    public var object: [String: WireValue] { if case .object(let v) = self { return v }; return [:] }
    public var bool: Bool { if case .bool(let v) = self { return v }; return false }
    public var pretty: String { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "null" }
    public var key: String { switch self { case .string(let s): return "s:" + s; default: return pretty } }
}

public struct ExecutionRPCRejection: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public protocol ExecutionTransport: Sendable {
    var events: AsyncStream<WireValue> { get }
    func connect() async throws
    func request(_ method: String, _ params: WireValue) async throws -> WireValue
    func respond(id: WireValue, result: WireValue) async throws
    func reject(id: WireValue, message: String) async throws
    func shutdown() async
}

/// Separate from the history reader: this connection owns only explicitly created/resumed tasks.
public actor CodexExecutionTransport: ExecutionTransport {
    // Scoped to Diorama's child process: do not modify the user's global Codex settings.
    // update_plan is opt-in; V1 delegation otherwise stops after one child level.
    public static let launchArguments = ["app-server", "--stdio", "--config", "tools.update_plan.enabled=true", "--config", "agents.max_depth=2"]

    public nonisolated let events: AsyncStream<WireValue>
    private let eventSink: AsyncStream<WireValue>.Continuation
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var scannedBytes = 0
    private var reader: Task<Void, Never>?
    private var serial = 0
    private var ready = false
    private var pending: [String: CheckedContinuation<WireValue, any Error>] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private let executable: URL?
    private let timeout: Duration
    public init(executable: URL? = nil, timeout: Duration = .seconds(30)) {
        self.executable = executable; self.timeout = timeout
        (events, eventSink) = AsyncStream.makeStream(of: WireValue.self)
    }
    deinit {
        reader?.cancel(); try? input?.close(); try? output?.close()
        if let process, process.isRunning { process.terminate() }
        eventSink.finish()
    }
    public func connect() async throws {
        if ready, process?.isRunning == true { return }
        guard process == nil else { throw AppServerFailure("Execution connection is initializing or unavailable") }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent(".local/bin/codex"), URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex")]
        guard let binary = executable ?? candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw AppServerFailure("Install Codex CLI before running tasks") }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = binary
        child.arguments = Self.launchArguments
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        child.currentDirectoryURL = home
        try child.run()
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        _ = fcntl(stdout.fileHandleForReading.fileDescriptor, F_SETFL, fcntl(stdout.fileHandleForReading.fileDescriptor, F_GETFL) | O_NONBLOCK)
        // Avoid SIGPIPE on a disconnected child; never let it terminate the GUI.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        reader = Task { [weak self] in
            while !Task.isCancelled {
                guard await self?.pump() == true else { return }
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
        }
        do {
            _ = try await request("initialize", .object(["clientInfo": .object(["name": .string("diorama_execution"), "version": .string("0.3.0")]), "capabilities": .object(["experimentalApi": .bool(true)])]))
            try write(.object(["method": .string("initialized"), "params": .object([:])]))
            ready = true
        } catch { fail("Initialization failed: \(error.localizedDescription)"); throw error }
    }
    public func request(_ method: String, _ params: WireValue) async throws -> WireValue {
        let allowed = ["account/read", "initialize", "model/list", "thread/start", "thread/resume", "thread/read", "thread/list", "thread/turns/list", "thread/goal/get", "turn/start", "turn/steer", "turn/interrupt", "thread/goal/set", "thread/goal/clear", "thread/compact/start", "account/rateLimits/read", "collaborationMode/list", "thread/name/set", "thread/archive", "thread/unarchive", "thread/fork", "review/start", "thread/queue/add", "thread/queue/list", "thread/queue/delete", "thread/queue/start", "skills/list", "skills/config/write", "app/list", "app/installed", "mcpServerStatus/list", "mcpServer/oauth/login", "config/mcpServer/reload", "thread/search", "thread/searchOccurrences", "thread/items/list", "thread/backgroundTerminals/list", "thread/backgroundTerminals/terminate"]
        guard allowed.contains(method) else { throw AppServerFailure("Execution method is not supported: \(method)") }
        guard process?.isRunning == true, ready || method == "initialize" else { throw AppServerFailure("Execution connection unavailable; no request was sent") }
        serial += 1; let id = WireValue.string("diorama-\(serial)"); let key = id.key
        return try await withCheckedThrowingContinuation { continuation in
            pending[key] = continuation
            do { try write(.object(["id": id, "method": .string(method), "params": params])) }
            catch { pending.removeValue(forKey: key)?.resume(throwing: error); return }
            timers[key] = Task { [weak self, timeout] in
                do { try await Task.sleep(for: timeout) } catch { return }
                await self?.expire(key, method: method)
            }
        }
    }
    private func expire(_ key: String, method: String) {
        timers.removeValue(forKey: key)
        let readOnly = ["thread/read", "thread/list", "thread/turns/list", "thread/goal/get", "collaborationMode/list", "model/list", "account/read"].contains(method)
        let detail = readOnly ? "Loading conversation or settings timed out. This request did not send a message." : "Submission outcome may be unknown; it was not retried."
        pending.removeValue(forKey: key)?.resume(throwing: AppServerFailure("\(method) response timed out. " + detail))
    }
    public func respond(id: WireValue, result: WireValue) throws {
        guard ready else { throw AppServerFailure("Disconnected; response was not sent") }
        try write(.object(["id": id, "result": result]))
    }
    public func reject(id: WireValue, message: String) throws {
        try write(.object(["id": id, "error": .object(["code": .number(-32601), "message": .string(message)])]))
    }
    private func write(_ message: WireValue) throws {
        guard let input else { throw AppServerFailure("Execution pipe unavailable") }
        var bytes = try JSONEncoder().encode(message); bytes.append(10)
        try input.write(contentsOf: bytes)
    }
    private func pump() -> Bool {
        guard let output else { return false }
        // Drain ready chunks in bounded batches instead of throttling every 64 KiB.
        for _ in 0..<32 {
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 0) > 0 else { return true }
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count == 0 { fail("Execution server disconnected. Task outcome must be reconciled."); return false }
            if count < 0 { if errno != EAGAIN && errno != EINTR { fail("Execution pipe read failed"); return false }; return true }
            buffer.append(contentsOf: bytes.prefix(count))
            while let end = buffer[buffer.index(buffer.startIndex, offsetBy: scannedBytes)...].firstIndex(of: 10) {
                guard buffer.distance(from: buffer.startIndex, to: end) <= 64 * 1024 * 1024 else { fail("Execution event exceeded 64 MiB"); return false }
                scannedBytes = 0
                let line = Data(buffer.prefix(upTo: end)); buffer.removeSubrange(...end)
                do {
                    let message = try JSONDecoder().decode(WireValue.self, from: line)
                    if message["method"].string != nil { eventSink.yield(message) }
                    else {
                        let key = message["id"].key
                        timers.removeValue(forKey: key)?.cancel()
                        if let continuation = pending.removeValue(forKey: key) {
                            if message["error"] != .null { continuation.resume(throwing: ExecutionRPCRejection(message["error"]["message"].string ?? "Provider request failed")) }
                            else { continuation.resume(returning: message["result"]) }
                        }
                    }
                } catch { fail("Invalid execution protocol message"); return false }
            }
            scannedBytes = buffer.count
            guard buffer.count <= 64 * 1024 * 1024 else { fail("Execution event exceeded 64 MiB"); return false }
        }
        return true
    }
    private func fail(_ reason: String) {
        ready = false; reader?.cancel(); reader = nil
        try? input?.close(); try? output?.close(); input = nil; output = nil
        if let process, process.isRunning { process.terminate() }; process = nil; buffer.removeAll(); scannedBytes = 0
        for timer in timers.values { timer.cancel() }; timers.removeAll()
        let waiting = pending; pending.removeAll()
        for c in waiting.values { c.resume(throwing: AppServerFailure(reason)) }
        eventSink.yield(.object(["method": .string("diorama/disconnected"), "params": .object(["reason": .string(reason)])]))
    }
    public func shutdown() { fail("Execution connection closed") }
}
