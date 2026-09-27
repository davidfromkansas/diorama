import Foundation
import Darwin

/// Runs the published Claude Code binary. Credentials stay with Claude Code.
public actor ClaudeExecutionTransport: ExecutionTransport {
    public nonisolated let events: AsyncStream<WireValue>
    private let sink: AsyncStream<WireValue>.Continuation
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var reader: Task<Void, Never>?
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<WireValue, any Error>] = [:]
    private var approvals: [String: WireValue] = [:]
    private var catalog: WireValue = .null
    private let folder: String
    private let sessionID: String
    private let resume: Bool
    private let context: String?
    private var turn: String?
    private var interrupted = false
    private var steering = false
    private var steeringCancelled = false
    private var goal: ClaudeGoal?
    private var goalArmed = false
    private var goalContinuation: Task<Void, Never>?
    private var goalRevision = UUID()
    private var goalFile: URL { queueFile.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ClaudeGoals/" + sessionID + ".json") }
    private func saveGoal() throws {
        try FileManager.default.createDirectory(at: goalFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(goal).write(to: goalFile, options: .atomic)
        emit("thread/goal/updated", ["goal": goal?.wire ?? .null])
    }
    private func pauseGoal(_ reason: String) {
        goalArmed = false
        goalContinuation?.cancel(); goalContinuation = nil; goalRevision = UUID()
        guard goal != nil else { return }
        if goal?.status == "active" || goal?.pendingResult == true {
            goal?.status = "paused"; goal?.reason = reason
            do { try saveGoal() } catch { emit("error", ["error": .object(["message": .string("Could not save paused goal: " + error.localizedDescription)])]) }
        }
    }
    private func scheduleGoal() {
        guard !steering, turn == nil, goal?.status == "active", goalContinuation == nil else { return }
        let revision = goalRevision
        goalContinuation = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self?.continueGoal(revision)
        }
    }
    private func continueGoal(_ revision: UUID) async {
        goalContinuation = nil
        guard revision == goalRevision, !steering, turn == nil, goal?.status == "active" else { return }
        guard let goal, goal.turnsUsed < goal.turnLimit, goal.tokensUsed < goal.tokenBudget else { pauseGoal("Continuation limit reached"); return }
        do { _ = try await request("turn/start", .object(["model": .string(goal.selectedModel ?? model), "goalRevision": .string(revision.uuidString), "input": .array([.object(["type": .string("text"), "text": .string("<diorama_goal_context>\nDiorama goal: automatic continuation. Use the previous progress and evidence; do not repeat completed work.\n</diorama_goal_context>")])])])) }
        catch { if revision == goalRevision { pauseGoal("Continuation stopped: " + error.localizedDescription) } }
    }
    private var model = "claude/default"
    private var textID = ""
    private var text = ""
    private var goalVisibleText = ""
    private var goalOutput = false
    private var queue: [WireValue] = []
    private var queueSending: WireValue = .null
    private var queueFile: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/ClaudeQueue/" + sessionID + ".json") }
    private func saveQueue() throws {
        try FileManager.default.createDirectory(at: queueFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(WireValue.object(["rows": .array(queue), "sending": queueSending])).write(to: queueFile, options: .atomic)
    }
    private var toolItems: [String: WireValue] = [:]
    private var permissionMode = "default"
    private let executable: URL?
    private let backend: ClaudeBackend
    public init(folder: String, sessionID: String = UUID().uuidString.lowercased(), resume: Bool = false, context: String? = nil, executable: URL? = nil, backend: ClaudeBackend = .automatic) {
        self.folder = folder; self.sessionID = sessionID; self.resume = resume; self.context = context; self.executable = executable; self.backend = backend
        (events, sink) = AsyncStream.makeStream(of: WireValue.self)
    }
    deinit { reader?.cancel(); try? input?.close(); try? output?.close(); if let process, process.isRunning { process.terminate() }; sink.finish() }
    /// Read-only recovery preview; does not connect or restart work.
    public static func savedGoal(sessionID: String) -> WireValue {
        guard UUID(uuidString: sessionID) != nil else { return .null }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/ClaudeGoals/" + sessionID + ".json")
        guard let data = try? Data(contentsOf: file), var goal = try? JSONDecoder().decode(ClaudeGoal.self, from: data) else { return .null }
        if goal.status == "active" || goal.pendingResult { goal.status = "paused"; goal.reason = "Review before resuming" }
        return goal.wire
    }
    public static func binary() -> URL? {
        AgentExecutable.resolve("claude")
    }
    /// A GUI launch can inherit PWD from the process that opened Diorama.
    /// Claude consults it during startup, independently of Process.currentDirectoryURL.
    /// Keep both representations of the working directory aligned for CLI and SDK.
    static func childEnvironment(_ source: [String: String], folder: String, executable: URL) -> [String: String] {
        var environment = source
        // Explicit API credentials must never silently override subscription login.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"] { environment.removeValue(forKey: key) }
        environment["PWD"] = URL(fileURLWithPath: folder).standardizedFileURL.path
        environment.removeValue(forKey: "OLDPWD")
        environment["CLAUDE_CODE_ENABLE_TODO_TOOLS"] = "1"
        environment["DIORAMA_CLAUDE_EXECUTABLE"] = executable.path
        return environment
    }
    public func connect() async throws {
        if process?.isRunning == true { return }
        guard UUID(uuidString: sessionID) != nil else { throw ExecutionRPCRejection("Invalid Claude session identity") }
        guard let binary = executable ?? Self.binary() else { throw ExecutionRPCRejection("Install Claude Code, then connect your Claude account in Settings.") }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = binary
        child.arguments = ["-p", "--allow-dangerously-skip-permissions", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-prompt-tool", "stdio", resume ? "--resume" : "--session-id", sessionID]
        if let context { child.arguments! += ["--append-system-prompt", context] }
        let requested = ProcessInfo.processInfo.environment["DIORAMA_CLAUDE_BACKEND"].flatMap(ClaudeBackend.init(rawValue:)) ?? backend
        let runtime = requested == .cli || (executable != nil && requested == .automatic) ? nil : ClaudeSDKRuntime.discover()
        if requested == .sdk && runtime == nil { throw ExecutionRPCRejection("Claude SDK helper is missing. Reinstall Diorama or select the CLI backend.") }
        if let runtime {
            child.executableURL = runtime.node
            child.arguments = [runtime.directory.appendingPathComponent("index.mjs").path] + (child.arguments ?? [])
        }
        let environment = Self.childEnvironment(ProcessInfo.processInfo.environment, folder: folder, executable: binary)
        child.environment = environment; child.currentDirectoryURL = URL(fileURLWithPath: folder)
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
        do { catalog = try await control(["subtype": .string("initialize")]) }
        catch { shutdown(); throw error }
        // Fail closed if Claude chose API billing. We do not infer subscription access from loggedIn alone.
        if !Self.usesSubscription(catalog) {
            shutdown()
            throw ExecutionRPCRejection("Claude is connected with API credentials. Use Settings → Connect Claude and choose your Claude subscription. Diorama has not sent a prompt or switched to API billing.")
        }
        if let data = try? Data(contentsOf: queueFile), let saved = try? JSONDecoder().decode(WireValue.self, from: data) { queue = saved["rows"].array; queueSending = saved["sending"] }
        if let data = try? Data(contentsOf: goalFile) {
            goal = try JSONDecoder().decode(ClaudeGoal?.self, from: data)
            if goal?.status == "active" || goal?.pendingResult == true {
                goal?.status = "paused"; goal?.pendingResult = false; goal?.reason = "App restarted; review progress before resuming"
                try saveGoal()
            }
        }
        if let mode = catalog["current_permission_mode"].string { permissionMode = mode }
    }
    private func control(_ payload: [String: WireValue]) async throws -> WireValue {
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try write(.object(["type": .string("control_request"), "request_id": .string(id), "request": .object(payload)])) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                await self?.expire(id, initializing: payload["subtype"]?.string == "initialize")
            }
        }
    }
    private func expire(_ id: String, initializing: Bool) {
        let message = initializing
            ? "Claude did not finish starting within 20 seconds. No message was sent. Try again; if this continues, check Claude in Settings."
            : "Claude response timed out. Check the conversation before retrying."
        pending.removeValue(forKey: id)?.resume(throwing: AppServerFailure(message))
    }
    private func write(_ value: WireValue) throws {
        guard let input, process?.isRunning == true else { throw AppServerFailure("Claude disconnected") }
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
    public static func usesSubscription(_ catalog: WireValue) -> Bool {
        let account = catalog["account"]
        guard account["apiKeySource"].string == "none" || account["apiKeySource"] == .null else { return false }
        if let subscription = account["subscriptionType"].string?.lowercased(),
           ["max", "pro", "team", "enterprise", "claude max", "claude pro", "claude team", "claude enterprise"].contains(subscription),
           account["apiProvider"].string == "firstParty" { return true }
        guard let source = account["tokenSource"].string, !source.isEmpty, source != "none" else { return false }
        return true
    }
    public static func modelRows(_ catalog: WireValue) -> [WireValue] {
        catalog["models"].array.compactMap { m in
            guard let value = m["value"].string else { return nil }
            return .object(["model": .string("claude/" + value), "displayName": m["displayName"], "isDefault": .bool(false), "supportedReasoningEfforts": .array([])])
        }
    }
    public func request(_ method: String, _ p: WireValue) async throws -> WireValue {
        switch method {
        case "collaborationMode/list": return .object(["data": .array([.object(["mode": .string("default")]), .object(["mode": .string("plan")])])])
        case "diorama/capabilities": return try await control(["subtype": .string("capability_discovery")])
        case "model/list": return .object(["data": .array(Self.modelRows(catalog))])
        case "thread/start", "thread/resume":
            return .object(["thread": .object(["id": .string(sessionID)]), "cwd": .string(folder), "model": .string(model), "approvalPolicy": .string(permissionMode)])
        case "thread/goal/get": return .object(["goal": goal?.wire ?? .null])
        case "thread/goal/set":
            guard let status = p["status"].string, ["active", "paused"].contains(status) else { throw ExecutionRPCRejection("Choose active or paused") }
            var next = goal
            if let objective = p["objective"].string {
                guard !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, objective.count <= 4000 else { throw ExecutionRPCRejection("Enter a goal of 1–4,000 characters") }
                if next?.objective != objective {
                    guard turn == nil else { throw ExecutionRPCRejection("Stop the current turn before replacing its goal") }
                    next = ClaudeGoal(objective: objective)
                }
            }
            guard next != nil else { throw ExecutionRPCRejection("Set a goal first") }
            if let budget = p["tokenBudget"].number {
                guard budget > 0, budget <= Double(Int.max / 2) else { throw ExecutionRPCRejection("Enter a positive token budget") }
                next?.tokenBudget = Int(budget)
            }
            if status == "active", p["activateSubmittedGoal"].bool, next?.status == "paused",
               !["Ready", "Paused", "Working toward goal"].contains(next?.reason ?? "") { return .object(["goal": next!.wire]) }
            if status == "active", next?.status == "complete" { return .object(["goal": next!.wire]) }
            if status == "active" {
                guard permissionMode != "plan" else { throw ExecutionRPCRejection("Turn off Plan Mode before activating a goal") }
                guard next!.turnsUsed < next!.turnLimit, next!.tokensUsed < next!.tokenBudget else { throw ExecutionRPCRejection("Goal limit reached. Create a new goal or increase its token budget.") }
            }
            goalContinuation?.cancel(); goalContinuation = nil; goalRevision = UUID()
            let previous = goal
            next?.status = status; next?.reason = status == "active" ? "Working toward goal" : "Paused"
            goal = next
            goalArmed = p["prepareSubmission"].bool
            do { try saveGoal() } catch { goal = previous; throw ExecutionRPCRejection("Could not save goal") }
            scheduleGoal()
            return .object(["goal": goal!.wire])
        case "thread/goal/clear":
            goalContinuation?.cancel(); goalContinuation = nil; goalRevision = UUID()
            let previous = goal; goal = nil; goalArmed = false
            do { try saveGoal() } catch { goal = previous; throw ExecutionRPCRejection("Could not clear goal") }
            return .object(["cleared": .bool(true)])
        case "turn/steer":
            guard !steering, let expected = turn, p["expectedTurnId"].string == expected, approvals.isEmpty else { throw ExecutionRPCRejection("The active Claude turn changed or needs approval. Correction not sent.") }
            _ = try Self.input(p["input"].array)
            steering = true; steeringCancelled = false
            defer { steering = false }
            pauseGoal("Paused for correction")
            interrupted = true
            _ = try await control(["subtype": .string("interrupt")])
            let deadline = Date().addingTimeInterval(20)
            while turn == expected {
                guard Date() < deadline else { throw AppServerFailure("Claude interruption was not confirmed; correction not sent") }
                try await Task.sleep(for: .milliseconds(25))
            }
            guard !steeringCancelled, turn == nil, process?.isRunning == true else { throw AppServerFailure("Claude disconnected or changed turns during interruption") }
            let reply = try await request("turn/start", .object(["input": p["input"]]))
            return .object(["turnId": .string(expected), "replacementTurnId": reply["turn"]["id"]])
        case "thread/queue/list":
            return .object(["data": .array(queue), "deliveryUncertain": .bool(queueSending != .null)])
        case "thread/queue/add":
            let row: WireValue = .object(["id": .string(UUID().uuidString), "clientUserMessageId": p["clientUserMessageId"], "input": p["input"], "model": .string(model)])
            queue.append(row); do { try saveQueue() } catch { queue.removeLast(); throw ExecutionRPCRejection("Could not save the queued message.") }; return .object(["queuedSubmission": row])
        case "thread/queue/delete":
            let oldSending = queueSending; if queueSending["id"] == p["queuedSubmissionId"] { queueSending = .null }
            let old = queue; queue.removeAll { $0["id"] == p["queuedSubmissionId"] }; do { try saveQueue() } catch { queue = old; queueSending = oldSending; throw error }; return .object(["deleted": .bool(old.count != queue.count)])
        case "thread/queue/start":
            guard let row = queue.first, row["id"] == p["queuedSubmissionId"] else { throw ExecutionRPCRejection("Queued message unavailable") }
            guard queueSending == .null else { throw ExecutionRPCRejection("A previous queue delivery needs review") }
            queueSending = row; try saveQueue()
            do {
                let reply = try await request("turn/start", .object(["input": row["input"], "model": row["model"]]))
                queue.removeFirst(); queueSending = .null; try saveQueue(); return reply
            } catch let error as ExecutionRPCRejection { queueSending = .null; try saveQueue(); throw error }
        case "turn/start":
            guard turn == nil else { throw ExecutionRPCRejection("Wait for Claude to finish or stop it first.") }
            var content = try Self.input(p["input"].array)
            if let selected = p["model"].string, selected.hasPrefix("claude/") {
                _ = try await control(["subtype": .string("set_model"), "model": .string(String(selected.dropFirst(7)))]); model = selected
            }
            if let effort = p["effort"].string, !effort.isEmpty { throw ExecutionRPCRejection("Changing Claude reasoning effort is not supported yet.") }
            let mode = p["collaborationMode"]["mode"].string
            var nextMode = permissionMode
            if p["approvalPolicy"].string == "never" { nextMode = "bypassPermissions" }
            else if p["approvalsReviewer"].string == "auto_review" { nextMode = "auto" }
            else if p["approvalsReviewer"].string == "user" { nextMode = "default" }
            if mode == "plan" { nextMode = "plan" } else if nextMode == "plan" { nextMode = "default" }
            if nextMode != permissionMode { _ = try await control(["subtype": .string("set_permission_mode"), "mode": .string(nextMode)]); permissionMode = nextMode }
            guard turn == nil else { throw ExecutionRPCRejection("Claude already started another turn") }
            if let revision = p["goalRevision"].string {
                guard revision == goalRevision.uuidString, goal?.status == "active", !Task.isCancelled else { throw ExecutionRPCRejection("Goal paused before continuation") }
            }
            if goal != nil, goal?.status != "complete", goalArmed || goal?.status == "active" {
                goalArmed = false; goal?.selectedModel = model; goal?.turnsUsed += 1; goal?.pendingResult = true
                do { try saveGoal() } catch { goal?.status = "paused"; goal?.pendingResult = false; throw ExecutionRPCRejection("Could not checkpoint goal before sending") }
                content.append(.object(["type": .string("text"), "text": .string(goal!.instruction)]))
            }
            goalOutput = goal?.pendingResult == true
            let id = UUID().uuidString; turn = id; interrupted = false; text = ""; goalVisibleText = ""; textID = UUID().uuidString
            do { try write(.object(["type": .string("user"), "message": .object(["role": .string("user"), "content": .array(content)]), "parent_tool_use_id": .null, "session_id": .string(sessionID)])) }
            catch { turn = nil; throw error }
            emit("turn/started", ["turn": .object(["id": .string(id)])])
            emit("item/completed", ["item": .object(["id": .string(UUID().uuidString), "type": .string("userMessage"), "content": p["input"]])])
            return .object(["turn": .object(["id": .string(id)])])
        case "turn/interrupt":
            steeringCancelled = true
            guard turn != nil else { throw ExecutionRPCRejection("No active Claude turn") }
            pauseGoal("Stopped by user")
            interrupted = true
            return try await control(["subtype": .string("interrupt")])
        case "thread/backgroundTerminals/list": return .object(["data": .array([])])
        default: throw ExecutionRPCRejection("This action is not available for Claude sessions yet: " + method)
        }
    }
    public static func input(_ parts: [WireValue]) throws -> [WireValue] {
        try parts.map { part in
            if part["type"].string == "localImage", let path = part["path"].string {
                let file = try ConversationAttachment(url: URL(fileURLWithPath: path))
                let data = try Data(contentsOf: file.url)
                guard data.count <= 5 * 1024 * 1024 else { throw ExecutionRPCRejection("Claude images must be 5 MiB or smaller.") }
                let ext = file.url.pathExtension.lowercased(), mime = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp"]
                return .object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string(mime[ext] ?? "image/png"), "data": .string(data.base64EncodedString())])])
            }
            guard part["type"].string == "text" else { throw ExecutionRPCRejection("This attachment type is not supported by Claude.") }
            return .object(["type": .string("text"), "text": part["text"]])
        }
    }
    public func respond(id: WireValue, result: WireValue) throws {
        guard let request = approvals[id.key] else { throw ExecutionRPCRejection("This Claude request is no longer pending") }
        var response: WireValue
        if request["tool_name"].string == "AskUserQuestion" {
            var updated = request["input"].object, answers: [String: WireValue] = [:]
            for (index, question) in request["input"]["questions"].array.enumerated() { answers[question["question"].string ?? ""] = .string(result["answers"][String(index)]["answers"].array.compactMap(\.string).joined(separator: ", ")) }
            updated["answers"] = .object(answers); response = .object(["behavior": .string("allow"), "updatedInput": .object(updated)])
        } else if result["decision"].string == "accept" { response = .object(["behavior": .string("allow"), "updatedInput": request["input"]]) }
        else { pauseGoal("Permission declined"); response = .object(["behavior": .string("deny"), "message": .string("The user declined this action.")]) }
        try write(.object(["type": .string("control_response"), "response": .object(["subtype": .string("success"), "request_id": id, "response": response])]))
        approvals.removeValue(forKey: id.key); emit("serverRequest/resolved", ["requestId": id])
    }
    public func reject(id: WireValue, message: String) throws {
        try write(.object(["type": .string("control_response"), "response": .object(["subtype": .string("error"), "request_id": id, "error": .string(message)])]))
    }
    private func receive(_ e: WireValue) {
        // Both the CLI and SDK feed the same provider-neutral reducer. Reasoning is ignored there.
        if ["assistant", "user", "system", "result", "rate_limit_event"].contains(e["type"].string ?? "") {
            emit("diorama/claudeActivity", ["event": e])
        }
        // Child content belongs in child inspection, never in the parent's conversation.
        if e["parent_tool_use_id"].string != nil { return }
        switch e["type"].string {
        case "control_response":
            let r = e["response"], id = r["request_id"].string ?? ""
            if r["subtype"].string == "error" { pending.removeValue(forKey: id)?.resume(throwing: ExecutionRPCRejection(r["error"].string ?? "Claude rejected the request")) }
            else { pending.removeValue(forKey: id)?.resume(returning: r["response"]) }
        case "control_request":
            let r = e["request"], id = e["request_id"]
            guard r["subtype"].string == "can_use_tool" else { try? reject(id: id, message: "Unsupported Claude request"); return }
            approvals[id.key] = r
            if r["tool_name"].string == "AskUserQuestion" {
                let questions = r["input"]["questions"].array.enumerated().map { index, q -> WireValue in
                    var fields = q.object; fields["id"] = .string(String(index)); return .object(fields)
                }
                emit("item/tool/requestUserInput", ["questions": .array(questions), "itemId": r["tool_use_id"]], requestID: id)
            } else {
                emit("item/commandExecution/requestApproval", ["itemId": r["tool_use_id"], "toolName": r["tool_name"], "toolInput": r["input"], "command": r["input"]["command"], "reason": r["input"]["description"], "availableDecisions": .array([.string("accept"), .string("decline")])], requestID: id)
            }
        case "system":
            if let actual = e["session_id"].string, actual != sessionID {
                disconnected(); if let process, process.isRunning { process.terminate() }
            }
        case "stream_event":
            let delta = e["event"]["delta"]
            if delta["type"].string == "text_delta", let value = delta["text"].string {
                text += value
                if goalOutput {
                    if let newline = text.lastIndex(of: "\n") { emitGoalText(String(text[...newline])) }
                } else { emit("item/agentMessage/delta", ["itemId": .string(textID), "delta": .string(value)]) }
            }
        case "assistant":
            let complete = e["message"]["content"].array.filter { $0["type"].string == "text" }.compactMap { $0["text"].string }.joined(separator: "\n")
            if !complete.isEmpty {
                text = complete
                if goalOutput { emitGoalText(text) }
                else { emit("item/completed", ["item": .object(["id": .string(textID), "type": .string("agentMessage"), "text": .string(complete)])]) }
            }
            for block in e["message"]["content"].array {
                if block["type"].string == "tool_use", let id = block["id"].string {
                    if block["name"].string == "ExitPlanMode", let plan = block["input"]["plan"].string {
                        emit("item/completed", ["item": .object(["id": .string(id + ":plan"), "type": .string("plan"), "text": .string(plan)])])
                    }
                    let item: WireValue = .object(["id": .string(id), "type": .string("mcpToolCall"), "tool": block["name"], "arguments": block["input"], "status": .string("inProgress")])
                    toolItems[id] = item; emit("item/started", ["item": item])
                }
            }
            // Each assistant message may precede another tool cycle; don't overwrite earlier text.
            if !text.isEmpty { text = ""; goalVisibleText = ""; textID = UUID().uuidString }
        case "user":
            for block in e["message"]["content"].array where block["type"].string == "tool_result" {
                guard let id = block["tool_use_id"].string, var item = toolItems.removeValue(forKey: id)?.object else { continue }
                item["status"] = .string(block["is_error"].bool ? "failed" : "completed"); item["result"] = block["content"]
                emit("item/completed", ["item": .object(item)])
            }
        case "result":
            guard let turn else { return }
            if e["is_error"].bool, !interrupted { emit("error", ["error": .object(["message": .string(e["errors"].array.compactMap(\.string).joined(separator: "\n"))])]) }
            emit("turn/completed", ["turn": .object(["id": .string(turn), "status": .string(interrupted ? "interrupted" : e["is_error"].bool ? "failed" : "completed")])])
            self.turn = nil; approvals.removeAll()
            if goal?.pendingResult == true {
                let usage = e["usage"]
                let tokens = ["input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"].reduce(0) { $0 + Int(usage[$1].number ?? 0) }
                goal?.finish(result: e["result"].string ?? "", usage: tokens, failed: e["is_error"].bool, interrupted: interrupted)
                do { try saveGoal() } catch { pauseGoal("Could not save goal progress") }
            }
            scheduleGoal()
        default: break
        }
    }
    private func emitGoalText(_ raw: String) {
        let cleaned = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("DIORAMA_GOAL_") }.joined(separator: "\n")
        guard cleaned.hasPrefix(goalVisibleText) else { return }
        let delta = String(cleaned.dropFirst(goalVisibleText.count))
        goalVisibleText = cleaned
        if !delta.isEmpty { emit("item/agentMessage/delta", ["itemId": .string(textID), "delta": .string(delta)]) }
    }
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
            guard let e = try? JSONDecoder().decode(WireValue.self, from: line) else { disconnected(); return false }
            receive(e)
        }
        return true
    }
    private func disconnected() {
        pauseGoal("Disconnected; review before resuming")
        let waiting = pending; pending.removeAll()
        for c in waiting.values { c.resume(throwing: AppServerFailure("Claude disconnected; check the conversation before retrying.")) }
        emit("diorama/sessionDisconnected", ["reason": .string("Claude disconnected. Check saved history before reconnecting.")])
    }
    public func shutdown() {
        pauseGoal("App closed; review before resuming")
        reader?.cancel(); reader = nil; try? input?.close(); try? output?.close(); input = nil; output = nil
        if let process, process.isRunning { process.terminate() }; process = nil; disconnected()
    }
}
