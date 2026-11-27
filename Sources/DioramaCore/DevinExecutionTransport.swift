import Foundation
import Darwin

/// Runs the published Devin CLI (`devin acp`), which speaks the Agent Client Protocol (JSON-RPC
/// over stdin/stdout), and translates it into the same events Diorama reads from Codex and
/// Claude. Credentials stay with the Devin CLI: Diorama never reads or stores them.
///
/// One transport is one Devin session. Its Diorama thread id is Devin's own session id, so a
/// conversation can be continued later with `session/load`.
public actor DevinExecutionTransport: ExecutionTransport {
    public nonisolated let events: AsyncStream<WireValue>
    private let sink: AsyncStream<WireValue>.Continuation
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var reader: Task<Void, Never>?
    private var buffer = Data()
    private var serial = 0
    private var pending: [String: CheckedContinuation<WireValue, any Error>] = [:]
    /// Devin's own permission requests, by the id Diorama shows them under.
    private var approvals: [String: WireValue] = [:]
    private let folder: String
    private let executable: URL?
    private var sessionID: String
    /// Sent once, ahead of the first message: ACP has no separate system prompt.
    private var context: String?
    private var model: String
    private var permissionMode: String?
    private var agentCapabilities: WireValue = .null
    private var modes: [String] = []
    private var turn: String?
    private var interrupted = false
    private var steering = false
    private var steeringCancelled = false
    private var textID = UUID().uuidString
    private var text = ""
    private var tools: [String: WireValue] = [:]
    private var queue: [WireValue] = []
    private var queueSending: WireValue = .null

    /// `sessionID` is nil for a new conversation; Devin picks the id.
    public init(folder: String, sessionID: String? = nil, context: String? = nil, model: String? = nil, permissionMode: String? = nil, executable: URL? = nil) {
        self.folder = folder; self.sessionID = sessionID ?? ""
        self.context = context; self.executable = executable; self.permissionMode = permissionMode
        self.model = model.flatMap { $0.hasPrefix("devin/") ? $0 : nil } ?? "devin/default"
        (events, sink) = AsyncStream.makeStream(of: WireValue.self)
    }
    deinit { reader?.cancel(); try? input?.close(); try? output?.close(); if let process, process.isRunning { process.terminate() }; sink.finish() }

    public static func binary() -> URL? { AgentExecutable.resolve("devin") }
    public var id: String { sessionID }

    /// The Devin model slug for a Diorama model id; nil for Devin's own default.
    static func slug(_ model: String) -> String? {
        guard model.hasPrefix("devin/") else { return nil }
        let slug = String(model.dropFirst(6))
        return slug.isEmpty || slug == "default" ? nil : slug
    }
    static func childEnvironment(_ source: [String: String], folder: String, model: String, permissionMode: String?) -> [String: String] {
        var environment = source
        environment["PWD"] = URL(fileURLWithPath: folder).standardizedFileURL.path
        environment.removeValue(forKey: "OLDPWD")
        environment["NO_COLOR"] = "1"
        // Documented Devin CLI settings; anything unset keeps the person's own Devin defaults.
        environment.removeValue(forKey: "DEVIN_MODEL"); environment.removeValue(forKey: "DEVIN_PERMISSION_MODE")
        if let slug = slug(model) { environment["DEVIN_MODEL"] = slug }
        if let permissionMode { environment["DEVIN_PERMISSION_MODE"] = permissionMode }
        return environment
    }

    public func connect() async throws {
        if process?.isRunning == true { return }
        guard let binary = executable ?? Self.binary() else { throw ExecutionRPCRejection("Install the Devin CLI, then sign in to Devin in Settings.") }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &directory), directory.boolValue else { throw ExecutionRPCRejection("Choose an existing working folder") }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = binary
        child.arguments = ["acp"]
        child.environment = Self.childEnvironment(ProcessInfo.processInfo.environment, folder: folder, model: model, permissionMode: permissionMode)
        child.currentDirectoryURL = URL(fileURLWithPath: folder)
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        try child.run(); process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        _ = fcntl(stdout.fileHandleForReading.fileDescriptor, F_SETFL, fcntl(stdout.fileHandleForReading.fileDescriptor, F_GETFL) | O_NONBLOCK)
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        reader = Task { [weak self] in
            while !Task.isCancelled {
                guard await self?.pump() == true else { return }
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
        }
        do {
            let reply = try await call("initialize", [
                "protocolVersion": .number(1),
                // Diorama doesn't serve files or terminals: Devin uses its own tools for those.
                "clientCapabilities": .object(["fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]), "terminal": .bool(false)]),
                "clientInfo": .object(["name": .string("diorama"), "version": .string("1.0")])
            ], timeout: .seconds(30))
            agentCapabilities = reply["agentCapabilities"]
            let session: WireValue
            // A known id continues that conversation (a resume, or a restart with new settings).
            if !sessionID.isEmpty {
                guard agentCapabilities["loadSession"].bool else { throw ExecutionRPCRejection("This Devin version can't continue earlier conversations. Update the Devin CLI.") }
                // Devin replays the earlier conversation; it's already in Diorama, so it's skipped.
                replaying = true; defer { replaying = false }
                session = try await call("session/load", ["sessionId": .string(sessionID), "cwd": .string(folder), "mcpServers": .array([])], timeout: .seconds(60))
            } else {
                session = try await call("session/new", ["cwd": .string(folder), "mcpServers": .array([])], timeout: .seconds(60))
                guard let id = session["sessionId"].string, !id.isEmpty else { throw AppServerFailure("Devin didn't start a session. No message was sent.") }
                sessionID = id
            }
            modes = session["modes"]["availableModes"].array.compactMap { $0["id"].string }
        } catch { shutdown(); throw Self.friendly(error) }
        if let data = try? Data(contentsOf: queueFile), let saved = try? JSONDecoder().decode(WireValue.self, from: data) { queue = saved["rows"].array; queueSending = saved["sending"] }
    }
    private var replaying = false

    /// Sign-in problems read as sign-in problems, so Settings and Home offer "Sign in".
    static func friendly(_ error: any Error) -> any Error {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("auth") || lower.contains("login") || lower.contains("log in") || lower.contains("unauthorized") {
            return ExecutionRPCRejection("Not logged in to Devin. Sign in to Devin, then try again. (\(message))")
        }
        return error
    }

    // MARK: JSON-RPC

    private func call(_ method: String, _ params: [String: WireValue], timeout: Duration? = nil) async throws -> WireValue {
        serial += 1; let id = WireValue.number(Double(serial)); let key = id.key
        return try await withCheckedThrowingContinuation { continuation in
            pending[key] = continuation
            do { try write(.object(["jsonrpc": .string("2.0"), "id": id, "method": .string(method), "params": .object(params)])) }
            catch { pending.removeValue(forKey: key)?.resume(throwing: error); return }
            if let timeout {
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    await self?.expire(key, method: method)
                }
            }
        }
    }
    private func notify(_ method: String, _ params: [String: WireValue]) throws {
        try write(.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": .object(params)]))
    }
    private func expire(_ key: String, method: String) {
        pending.removeValue(forKey: key)?.resume(throwing: AppServerFailure("Devin didn't answer \(method) in time. No message was sent. Check Devin in Settings."))
    }
    private func write(_ value: WireValue) throws {
        guard let input, process?.isRunning == true else { throw AppServerFailure("Devin disconnected") }
        var data = try JSONEncoder().encode(value)
        data.append(10); try input.write(contentsOf: data)
    }
    private func emit(_ method: String, _ values: [String: WireValue] = [:], requestID: WireValue? = nil) {
        var p = values; p["threadId"] = .string(sessionID)
        if let turn { p["turnId"] = .string(turn) }
        var e: [String: WireValue] = ["method": .string(method), "params": .object(p)]
        if let requestID { e["id"] = requestID }
        sink.yield(.object(e))
    }

    // MARK: Diorama requests

    private var queueFile: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/DevinQueue/" + (sessionID.isEmpty ? "new" : sessionID) + ".json") }
    private func saveQueue() throws {
        try FileManager.default.createDirectory(at: queueFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(WireValue.object(["rows": .array(queue), "sending": queueSending])).write(to: queueFile, options: .atomic)
    }
    private var settings: WireValue {
        .object(["thread": .object(["id": .string(sessionID)]), "cwd": .string(folder), "model": .string(model), "approvalPolicy": permissionMode.map(WireValue.string) ?? .null])
    }

    public func request(_ method: String, _ p: WireValue) async throws -> WireValue {
        switch method {
        case "collaborationMode/list": return .object(["data": .array([.object(["mode": .string("default")])])])
        case "diorama/capabilities": return .object([:])
        case "model/list": return .object(["data": .array([])])
        case "thread/start", "thread/resume":
            if let desired = p["permissionMode"].string, desired != permissionMode {
                _ = try await request("diorama/permissions/set", .object(["permissionMode": .string(desired)]))
            }
            return settings
        case "thread/read": return .object(["thread": .object(["id": .string(sessionID), "cwd": .string(folder), "turns": .array([])])])
        case "thread/goal/get": return .object(["goal": .null])
        case "thread/goal/set", "thread/goal/clear": throw ExecutionRPCRejection("Goals aren't available for Devin conversations yet.")
        case "thread/backgroundTerminals/list": return .object(["data": .array([])])
        case "diorama/permissions/set":
            guard turn == nil, approvals.isEmpty else { throw ExecutionRPCRejection("Finish the current turn and approvals first") }
            if let selected = p["model"].string, selected.hasPrefix("devin/"), selected != model { try await setModel(selected) }
            if let target = p["permissionMode"].string, target != permissionMode {
                // Devin reads its permission mode when a session starts, so start this one
                // again with the new mode. The conversation itself carries on.
                if modes.contains(target) {
                    _ = try await call("session/set_mode", ["sessionId": .string(sessionID), "modeId": .string(target)], timeout: .seconds(20))
                    permissionMode = target
                } else { try await restart(permissionMode: target) }
            }
            emit("diorama/permissions/changed", ["model": .string(model), "permissionMode": permissionMode.map(WireValue.string) ?? .null])
            return .object(["model": .string(model), "permissionMode": permissionMode.map(WireValue.string) ?? .null])
        case "turn/start":
            guard turn == nil else { throw ExecutionRPCRejection("Wait for Devin to finish or stop it first.") }
            if let selected = p["model"].string, selected.hasPrefix("devin/"), selected != model { try await setModel(selected) }
            if let effort = p["effort"].string, !effort.isEmpty { throw ExecutionRPCRejection("Changing Devin's reasoning effort isn't supported.") }
            var prompt = try Self.prompt(p["input"].array, images: agentCapabilities["promptCapabilities"]["image"].bool)
            if let context { prompt.insert(.object(["type": .string("text"), "text": .string("<diorama_context>\n" + context + "\n</diorama_context>")]), at: 0) }
            let id = UUID().uuidString; turn = id; interrupted = false; text = ""; textID = UUID().uuidString
            emit("turn/started", ["turn": .object(["id": .string(id)])])
            emit("item/completed", ["item": .object(["id": .string(UUID().uuidString), "type": .string("userMessage"), "content": p["input"]])])
            context = nil
            let sent = prompt
            Task { [weak self] in await self?.run(sent, turn: id) }
            return .object(["turn": .object(["id": .string(id)])])
        case "turn/interrupt":
            steeringCancelled = true
            guard turn != nil else { throw ExecutionRPCRejection("No active Devin turn") }
            interrupted = true
            try notify("session/cancel", ["sessionId": .string(sessionID)])
            cancelApprovals()
            return .object([:])
        case "turn/steer":
            guard !steering, let expected = turn, p["expectedTurnId"].string == expected, approvals.isEmpty else { throw ExecutionRPCRejection("The active Devin turn changed or needs approval. Correction not sent.") }
            _ = try Self.prompt(p["input"].array, images: agentCapabilities["promptCapabilities"]["image"].bool)
            steering = true; steeringCancelled = false
            defer { steering = false }
            interrupted = true
            try notify("session/cancel", ["sessionId": .string(sessionID)])
            let deadline = Date().addingTimeInterval(20)
            while turn == expected {
                guard Date() < deadline else { throw AppServerFailure("Devin didn't confirm it stopped; correction not sent") }
                try await Task.sleep(for: .milliseconds(25))
            }
            guard !steeringCancelled, process?.isRunning == true else { throw AppServerFailure("Devin disconnected or changed turns while stopping") }
            let reply = try await request("turn/start", .object(["input": p["input"]]))
            return .object(["turnId": .string(expected), "replacementTurnId": reply["turn"]["id"]])
        case "thread/queue/list":
            return .object(["data": .array(queue), "deliveryUncertain": .bool(queueSending != .null)])
        case "thread/queue/add":
            let row: WireValue = .object(["id": .string(UUID().uuidString), "clientUserMessageId": p["clientUserMessageId"], "input": p["input"], "model": .string(model)])
            queue.append(row); do { try saveQueue() } catch { queue.removeLast(); throw ExecutionRPCRejection("Could not save the queued message.") }; return .object(["queuedSubmission": row])
        case "thread/queue/delete":
            let oldSending = queueSending; if queueSending["id"] == p["queuedSubmissionId"] { queueSending = .null }
            let old = queue; queue.removeAll { $0["id"] == p["queuedSubmissionId"] }
            do { try saveQueue() } catch { queue = old; queueSending = oldSending; throw error }
            return .object(["deleted": .bool(old.count != queue.count)])
        case "thread/queue/start":
            guard let row = queue.first, row["id"] == p["queuedSubmissionId"] else { throw ExecutionRPCRejection("Queued message unavailable") }
            guard queueSending == .null else { throw ExecutionRPCRejection("A previous queue delivery needs review") }
            queueSending = row; try saveQueue()
            do {
                let reply = try await request("turn/start", .object(["input": row["input"], "model": row["model"]]))
                queue.removeFirst(); queueSending = .null; try saveQueue(); return reply
            } catch let error as ExecutionRPCRejection { queueSending = .null; try saveQueue(); throw error }
        default: throw ExecutionRPCRejection("This action isn't available for Devin conversations yet: " + method)
        }
    }

    private func setModel(_ selected: String) async throws {
        guard let slug = Self.slug(selected) else { throw ExecutionRPCRejection("Choose a Devin model.") }
        do { _ = try await call("session/set_model", ["sessionId": .string(sessionID), "modelId": .string(slug)], timeout: .seconds(20)) }
        catch { try await restart(model: selected) }
        model = selected
    }
    /// Starts Devin again on the same session with new settings.
    private func restart(model newModel: String? = nil, permissionMode newMode: String? = nil) async throws {
        guard agentCapabilities["loadSession"].bool else { throw ExecutionRPCRejection("This Devin version can't change settings mid-conversation. Start a new chat.") }
        let previous = (model, permissionMode)
        stop()
        if let newModel { model = newModel }
        if let newMode { permissionMode = newMode }
        do { try await connect() }
        catch { (model, permissionMode) = previous; try? await connect(); throw error }
    }

    private func run(_ prompt: [WireValue], turn id: String) async {
        let status: String
        do {
            let reply = try await call("session/prompt", ["sessionId": .string(sessionID), "prompt": .array(prompt)])
            let reason = reply["stopReason"].string ?? "end_turn"
            status = interrupted || reason == "cancelled" ? "interrupted" : reason == "refusal" ? "failed" : "completed"
            if reason == "refusal" { emit("error", ["error": .object(["message": .string("Devin declined this request.")])]) }
            if reason == "max_tokens" || reason == "max_turn_requests" { emit("error", ["error": .object(["message": .string("Devin stopped early: it reached its limit for one turn.")])]) }
        } catch {
            status = interrupted ? "interrupted" : "failed"
            if !interrupted { emit("error", ["error": .object(["message": .string(Self.friendly(error).localizedDescription)])]) }
        }
        guard turn == id else { return }
        finishText()
        for (toolID, var item) in tools.map({ ($0.key, $0.value.object) }) {
            item["status"] = .string(status == "completed" ? "completed" : "failed"); emit("item/completed", ["item": .object(item)]); tools.removeValue(forKey: toolID)
        }
        emit("turn/completed", ["turn": .object(["id": .string(id), "status": .string(status)])])
        turn = nil; cancelApprovals()
    }

    static func prompt(_ parts: [WireValue], images: Bool) throws -> [WireValue] {
        try parts.map { part in
            if part["type"].string == "localImage", let path = part["path"].string {
                guard images else { throw ExecutionRPCRejection("Devin can't read images here. Attach the file instead.") }
                let file = try ConversationAttachment(url: URL(fileURLWithPath: path))
                let data = try Data(contentsOf: file.url)
                guard data.count <= 5 * 1024 * 1024 else { throw ExecutionRPCRejection("Devin images must be 5 MiB or smaller.") }
                let ext = file.url.pathExtension.lowercased(), mime = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp"]
                return .object(["type": .string("image"), "mimeType": .string(mime[ext] ?? "image/png"), "data": .string(data.base64EncodedString())])
            }
            guard part["type"].string == "text" else { throw ExecutionRPCRejection("This attachment type isn't supported by Devin.") }
            return .object(["type": .string("text"), "text": part["text"]])
        }
    }

    // MARK: Approvals

    public func respond(id: WireValue, result: WireValue) throws {
        guard let request = approvals.removeValue(forKey: id.key) else { throw ExecutionRPCRejection("This Devin request is no longer pending") }
        let options = request["options"].array
        let accept = result["decision"].string == "accept" || result["decision"].string == "acceptForSession"
        let wanted = accept ? (result["decision"].string == "acceptForSession" ? ["allow_always", "allow_once"] : ["allow_once", "allow_always"]) : ["reject_once", "reject_always"]
        let option = wanted.lazy.compactMap { kind in options.first { $0["kind"].string == kind } }.first
        let outcome: WireValue = option.map { .object(["outcome": .string("selected"), "optionId": $0["optionId"]]) } ?? .object(["outcome": .string("cancelled")])
        try write(.object(["jsonrpc": .string("2.0"), "id": request["rpcID"], "result": .object(["outcome": outcome])]))
        emit("serverRequest/resolved", ["requestId": id])
    }
    public func reject(id: WireValue, message: String) throws {
        guard let request = approvals.removeValue(forKey: id.key) else { return }
        try write(.object(["jsonrpc": .string("2.0"), "id": request["rpcID"], "result": .object(["outcome": .object(["outcome": .string("cancelled")])])]))
        emit("serverRequest/resolved", ["requestId": id])
    }
    /// A stopped turn's open questions are answered "cancelled", as ACP asks.
    private func cancelApprovals() {
        for (key, request) in approvals {
            try? write(.object(["jsonrpc": .string("2.0"), "id": request["rpcID"], "result": .object(["outcome": .object(["outcome": .string("cancelled")])])]))
            emit("serverRequest/resolved", ["requestId": request["dioramaID"]])
            approvals.removeValue(forKey: key)
        }
    }

    // MARK: Devin's messages

    private func receive(_ message: WireValue) {
        guard let method = message["method"].string else {
            let key = message["id"].key
            if message["error"] != .null { pending.removeValue(forKey: key)?.resume(throwing: ExecutionRPCRejection(message["error"]["message"].string ?? "Devin rejected the request")) }
            else { pending.removeValue(forKey: key)?.resume(returning: message["result"]) }
            return
        }
        let params = message["params"]
        if message["id"] != .null {
            switch method {
            case "session/request_permission": askPermission(params, rpcID: message["id"])
            default:
                try? write(.object(["jsonrpc": .string("2.0"), "id": message["id"], "error": .object(["code": .number(-32601), "message": .string("Diorama doesn't support \(method)")])]))
            }
            return
        }
        guard method == "session/update", !replaying else { return }
        update(params["update"])
    }
    private func askPermission(_ params: WireValue, rpcID: WireValue) {
        let call = params["toolCall"]
        let id = WireValue.string("devin-permission-" + UUID().uuidString)
        var request = params.object; request["rpcID"] = rpcID; request["dioramaID"] = id
        approvals[id.key] = .object(request)
        let input = call["rawInput"]
        let command = input["command"].string ?? call["title"].string
        let decisions: [WireValue] = params["options"].array.contains { $0["kind"].string == "allow_always" }
            ? [.string("accept"), .string("acceptForSession"), .string("decline")] : [.string("accept"), .string("decline")]
        emit("item/commandExecution/requestApproval", ["itemId": call["toolCallId"], "toolName": call["kind"], "toolInput": input,
             "command": command.map(WireValue.string) ?? .null, "reason": call["title"], "availableDecisions": .array(decisions)], requestID: id)
    }
    private func update(_ u: WireValue) {
        switch u["sessionUpdate"].string {
        case "agent_message_chunk":
            guard turn != nil, u["content"]["type"].string == "text", let value = u["content"]["text"].string else { return }
            text += value
            emit("item/agentMessage/delta", ["itemId": .string(textID), "delta": .string(value)])
        case "tool_call":
            guard turn != nil, let id = u["toolCallId"].string else { return }
            finishText()
            let item: WireValue = .object(["id": .string(id), "type": .string("mcpToolCall"), "tool": u["kind"].string.map(WireValue.string) ?? .string("tool"),
                                           "server": .string("devin"), "command": u["title"], "arguments": u["rawInput"], "status": .string("inProgress")])
            tools[id] = item; emit("item/started", ["item": item])
            if let status = u["status"].string, ["completed", "failed"].contains(status) { finishTool(id, u) }
        case "tool_call_update":
            guard let id = u["toolCallId"].string, var item = tools[id]?.object else { return }
            if let title = u["title"].string { item["command"] = .string(title) }
            if u["rawInput"] != .null { item["arguments"] = u["rawInput"] }
            tools[id] = .object(item)
            if let status = u["status"].string, ["completed", "failed"].contains(status) { finishTool(id, u) }
        case "plan":
            guard turn != nil else { return }
            let plan = u["entries"].array.map { entry -> WireValue in
                let status = entry["status"].string == "in_progress" ? "inProgress" : entry["status"].string ?? "pending"
                return .object(["step": entry["content"], "status": .string(status)])
            }
            emit("turn/plan/updated", ["plan": .array(plan)])
        case "current_mode_update":
            if let mode = u["currentModeId"].string {
                permissionMode = mode
                emit("diorama/permissions/changed", ["permissionMode": .string(mode), "model": .string(model)])
            }
        default: break // Thoughts, command lists and replays aren't shown.
        }
    }
    private func finishTool(_ id: String, _ u: WireValue) {
        guard var item = tools.removeValue(forKey: id)?.object else { return }
        item["status"] = .string(u["status"].string == "failed" ? "failed" : "completed")
        let shown = u["content"].array.compactMap { $0["content"]["text"].string ?? $0["text"].string }.joined(separator: "\n")
        item["result"] = shown.isEmpty ? u["rawOutput"] : .string(shown)
        emit("item/completed", ["item": .object(item)])
    }
    /// Each message before a tool call is its own bubble, like Codex and Claude.
    private func finishText() {
        guard !text.isEmpty else { return }
        emit("item/completed", ["item": .object(["id": .string(textID), "type": .string("agentMessage"), "text": .string(text)])])
        text = ""; textID = UUID().uuidString
    }

    // MARK: Process

    private func pump() -> Bool {
        guard let output else { return false }
        var poller = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&poller, 1, 0) > 0 else { return true }
        var bytes = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
        if count == 0 { disconnected(); return false }
        if count < 0 { if errno != EAGAIN && errno != EINTR { disconnected(); return false }; return true }
        buffer.append(contentsOf: bytes.prefix(count))
        if buffer.count > 64 * 1024 * 1024 { disconnected(); return false }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: end)); buffer.removeSubrange(...end)
            // Anything that isn't a protocol message (a log line) is skipped, not fatal.
            guard !line.isEmpty, let message = try? JSONDecoder().decode(WireValue.self, from: line) else { continue }
            receive(message)
        }
        return true
    }
    /// Ends the process without telling Diorama the conversation is gone (for a restart).
    private func stop() {
        reader?.cancel(); reader = nil; try? input?.close(); try? output?.close(); input = nil; output = nil
        if let process, process.isRunning { process.terminate() }; process = nil; buffer.removeAll()
        let waiting = pending; pending.removeAll()
        for c in waiting.values { c.resume(throwing: AppServerFailure("Devin restarted")) }
    }
    private func disconnected() {
        let waiting = pending; pending.removeAll()
        for c in waiting.values { c.resume(throwing: AppServerFailure("Devin disconnected; check the conversation before retrying.")) }
        approvals.removeAll()
        if !sessionID.isEmpty { emit("diorama/sessionDisconnected", ["reason": .string("Devin disconnected. Send again to reconnect.")]) }
    }
    public func shutdown() {
        reader?.cancel(); reader = nil; try? input?.close(); try? output?.close(); input = nil; output = nil
        if let process, process.isRunning { process.terminate() }; process = nil; disconnected()
    }
}

/// Checks the Devin CLI without starting a conversation: is it signed in, and which models
/// does this account offer. Rows use Diorama's `devin/<slug>` model ids.
public enum DevinCatalog {
    public static func probe(executable: URL? = nil) async throws -> [WireValue] {
        guard let binary = executable ?? DevinExecutionTransport.binary() else { throw ExecutionRPCRejection("Install the Devin CLI to connect your Devin account.") }
        do { _ = try await ProjectCommand.data(binary.path, ["auth", "status"], timeout: 15) }
        catch { throw ExecutionRPCRejection("Not logged in to Devin. " + error.localizedDescription) }
        let data = (try? await ProjectCommand.data(binary.path, ["models", "list", "--format", "json"], timeout: 20)) ?? Data()
        return rows((try? JSONDecoder().decode(WireValue.self, from: data)) ?? .null)
    }
    /// Devin's own default first, then the models `devin models list` reports.
    public static func rows(_ list: WireValue) -> [WireValue] {
        let items: [WireValue] = {
            if case .array(let a) = list { return a }
            for key in ["models", "data", "items"] { if case .array(let a) = list[key] { return a } }
            return []
        }()
        var seen = Set<String>()
        let reported = items.compactMap { item -> WireValue? in
            let slug = item.string ?? ["slug", "id", "model", "modelId", "model_id", "name"].lazy.compactMap { item[$0].string }.first
            guard let slug, !slug.isEmpty, seen.insert(slug).inserted else { return nil }
            let name = ["displayName", "display_name", "label", "title", "name"].lazy.compactMap { item[$0].string }.first ?? slug
            return .object(["model": .string("devin/" + slug), "displayName": .string("Devin · " + name), "isDefault": .bool(false), "supportedReasoningEfforts": .array([])])
        }
        return [.object(["model": .string("devin/default"), "displayName": .string("Devin · Default"), "isDefault": .bool(false), "supportedReasoningEfforts": .array([])])] + reported
    }
}
