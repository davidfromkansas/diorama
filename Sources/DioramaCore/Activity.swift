import Foundation

public enum ActivityState: String, Codable, Sendable {
    case working = "Working", approval = "Awaiting approval", input = "Waiting for input"
    case idle = "Idle", finished = "Last turn finished", interrupted = "Interrupted"
    case blocked = "Blocked", unknown = "Unknown"
    public var needsAttention: Bool { self == .approval || self == .input || self == .blocked }
}

public struct ActivityEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: String
    public var sessionID: String
    public var kind: String
    public var source: String
    public var recordedAt: Date?
    public var observedAt: Date
    public var turnID: String?
    public var callID: String?
    public var agentID: String?
    public var parentID: String?
    public var role: String?
    public var tool: String?
    public var detail: String?
    public var durationMS: Double?
    public var state: ActivityState?
    public var time: Date { recordedAt ?? observedAt }
    public var label: String {
        if kind == "toolStarted" {
            switch tool {
            case "Bash", "exec_command", "shell", "shell_command": return "Using terminal"
            case "Edit", "Write", "apply_patch": return "Editing a file"
            default: return "Calling \(tool ?? "tool")"
            }
        }
        return ["toolFinished": "Tool returned", "toolFailed": "Tool failed", "started": "Turn started",
                "finished": "Last turn finished", "stopping": "Response stopping (continuation possible)",
                "approval": "Approval requested", "input": "Input requested", "idle": "Idle reported",
                "interrupted": "Interrupted", "compact": "Compacting conversation", "compacted": "Compaction finished",
                "sessionStarted": "Session started or resumed", "sessionEnded": "Session ended",
                "agentStarted": "Subagent started", "agentStopped": "Subagent stopped", "blocked": "Blocking condition reported",
                "commentary": "Says"][kind] ?? kind
    }
    public init(id: String, provider: String, sessionID: String, kind: String, source: String,
                recordedAt: Date? = nil, observedAt: Date = Date(), turnID: String? = nil, callID: String? = nil,
                agentID: String? = nil, parentID: String? = nil, role: String? = nil, tool: String? = nil,
                detail: String? = nil, durationMS: Double? = nil, state: ActivityState? = nil) {
        self.id = id; self.provider = provider; self.sessionID = sessionID; self.kind = kind; self.source = source
        self.recordedAt = recordedAt; self.observedAt = observedAt; self.turnID = turnID; self.callID = callID
        self.agentID = agentID; self.parentID = parentID; self.role = role; self.tool = tool; self.detail = detail
        self.durationMS = durationMS; self.state = state
    }
}

public struct ActivitySummary: Sendable {
    public var events: [ActivityEvent] = []
    public var error: String?
    public init(events: [ActivityEvent] = [], error: String? = nil) { self.events = events; self.error = error }
    public var latestState: ActivityEvent? {
        var latest: ActivityEvent?
        var activeTurn: String?
        for event in events {
            if event.state == nil {
                if let request = latest, request.state?.needsAttention == true,
                   let call = request.callID, event.callID == call,
                   ["toolFinished", "toolFailed"].contains(event.kind) {
                    var resolved = event; resolved.state = .working; latest = resolved
                }
                continue
            }
            if event.kind == "started" { activeTurn = event.turnID }
            // Claude emits a generic permission notification for its question UI.
            // Keep the more specific, still-unanswered AskUserQuestion evidence.
            if event.state == .approval, event.callID == nil, event.tool == nil,
               latest?.state == .input, latest?.tool == "AskUserQuestion" { continue }
            if event.kind != "started", let activeTurn,
               let turn = event.turnID, turn != activeTurn { continue }
            latest = event
        }
        return latest
    }
    public var state: ActivityState { latestState?.state ?? .unknown }
    public var current: String? {
        guard let last = events.last, state == .working else { return nil }
        return ["toolStarted", "compact", "stopping"].contains(last.kind) ? last.label : nil
    }
    public var attention: [ActivityEvent] {
        events.filter { request in
            guard request.state?.needsAttention == true else { return false }
            return !events.contains { later in
                guard later.time >= request.time, later.id != request.id, later.agentID == request.agentID else { return false }
                // A matched tool completion or explicit same-turn ending resolves the request.
                if let call = request.callID, later.callID == call,
                   ["toolFinished", "toolFailed"].contains(later.kind) { return true }
                if let turn = request.turnID, later.turnID == turn,
                   ["finished", "interrupted"].contains(later.kind) { return true }
                if request.turnID == nil, later.turnID == nil,
                   ["finished", "interrupted", "started"].contains(later.kind) { return true }
                return false
            }
        }
    }
    public var uncertain: Bool {
        if error != nil || events.contains(where: { $0.recordedAt == nil }) { return true }
        var states: [Date: ActivityState] = [:]
        for event in events {
            guard let state = event.state else { continue }
            if let prior = states[event.time], prior != state { return true }
            states[event.time] = state
        }
        return false
    }
    public static func merged(_ events: [ActivityEvent], error: String? = nil) -> ActivitySummary {
        var seen = Set<String>()
        let unique = events.filter { seen.insert($0.id).inserted }
        return .init(events: unique.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }, error: error)
    }
}

public enum ActivityParser {
    /// The first `tools.<name>(` call in a Codex code-mode script, and its `cmd:` string literals:
    /// a script may run several commands (for example a listing, then reading a skill), joined
    /// with `&&` so all of them are seen.
    public static func codeModeCall(_ script: String) -> (tool: String, detail: String?)? {
        let range = NSRange(script.startIndex..., in: script)
        guard let match = codeModeTool.firstMatch(in: script, range: range), let name = Range(match.range(at: 1), in: script) else { return nil }
        let after = NSRange(match.range.upperBound..<range.upperBound)
        let commands = codeModeCommand.matches(in: script, range: after).compactMap { cmd -> String? in
            guard let literal = Range(cmd.range(at: 1), in: script) else { return nil }
            let quoted = String(script[literal])
            if quoted.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: Data(quoted.utf8)) { return decoded }
            return String(quoted.dropFirst().dropLast())
        }
        return (String(script[name]), commands.isEmpty ? nil : commands.joined(separator: " && "))
    }
    /// Every `tools.<name>(` call in a code-mode script with its own detail: a command, the files a
    /// patch touches, or the session a poll reads.
    public static func codeModeCalls(_ script: String) -> [(tool: String, detail: String?)] {
        let range = NSRange(script.startIndex..., in: script)
        let matches = codeModeTool.matches(in: script, range: range)
        return matches.enumerated().compactMap { index, match in
            guard let name = Range(match.range(at: 1), in: script) else { return nil }
            let end = index + 1 < matches.count ? matches[index + 1].range.location : range.upperBound
            guard let segment = Range(NSRange(location: match.range.upperBound, length: end - match.range.upperBound), in: script) else { return nil }
            let body = String(script[segment]), tool = String(script[name])
            switch tool {
            case "apply_patch":
                // A wrapped patch keeps its newlines escaped inside the script's string literal.
                return (tool, patchFiles(body.replacingOccurrences(of: "\\n", with: "\n")).joined(separator: "\n"))
            case "write_stdin": return (tool, polledSession(body).map { "session=" + $0 })
            default:
                let range = NSRange(body.startIndex..., in: body)
                let command = codeModeCommand.firstMatch(in: body, range: range).flatMap { Range($0.range(at: 1), in: body) }.map { literal -> String in
                    let quoted = String(body[literal])
                    if quoted.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: Data(quoted.utf8)) { return decoded }
                    return String(quoted.dropFirst().dropLast())
                }
                if let command { return (tool, KitchenActivity.withoutHeredocs(command)) }
                // An MCP resource read names what it fetched by URI (`skill://…` for a skill).
                let uri = codeModeURI.firstMatch(in: body, range: range).flatMap { Range($0.range(at: 1), in: body) }.map { String(body[$0]) }
                return (tool, uri)
            }
        }
    }
    /// The checklist from a code-mode `tools.update_plan({plan:[{step:"…",status:"…"}]})` call.
    public static func codeModePlan(_ script: String) -> WireValue? {
        guard let start = script.range(of: "tools.update_plan(") else { return nil }
        let body = String(script[start.upperBound...])
        let range = NSRange(body.startIndex..., in: body)
        let steps = codeModePlanStep.matches(in: body, range: range).compactMap { match -> WireValue? in
            guard let step = Range(match.range(at: 1), in: body), let status = Range(match.range(at: 2), in: body) else { return nil }
            let title = (try? JSONDecoder().decode(String.self, from: Data(("\"" + body[step] + "\"").utf8))) ?? String(body[step])
            return .object(["step": .string(title), "status": .string(String(body[status]))])
        }
        return steps.isEmpty ? nil : .array(steps)
    }
    private static let codeModePlanStep = try! NSRegularExpression(pattern: #"step\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*status\s*:\s*"(\w+)""#)
    private static let codeModeTool = try! NSRegularExpression(pattern: #"\btools\.([A-Za-z_][A-Za-z0-9_]*)\s*\("#)
    private static let codeModeURI = try! NSRegularExpression(pattern: #"\buri\s*:\s*["'`]([^"'`]+)["'`]"#)
    private static let codeModeCommand = try! NSRegularExpression(pattern: #"\bcmd\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`]*`)"#)

    public static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    /// Files named by an `apply_patch` patch (`*** Add File: path`, `*** Update File:`, `*** Delete File:`).
    public static func patchFiles(_ patch: String) -> [String] {
        var files: [String] = []
        for line in patch.split(separator: "\n") {
            for prefix in ["*** Add File: ", "*** Update File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                let path = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty && !files.contains(path) { files.append(path) }
            }
        }
        return files
    }
    /// The exit status in Codex shell output: `Process exited with code N` or `"exit_code":N`.
    public static func exitCode(_ output: String) -> Int? {
        first(exitPattern, in: output).flatMap { Int($0) }
    }
    /// The session a code-mode `write_stdin` call polls (`session_id: 17775`).
    public static func polledSession(_ script: String) -> String? { first(polledPattern, in: script) }
    private static let polledPattern = try! NSRegularExpression(pattern: #"session_id\s*:\s*(\d+)"#)
    /// The session a still-running Codex command continues in.
    public static func sessionID(_ output: String) -> String? { first(sessionPattern, in: output) }
    private static func first(_ pattern: NSRegularExpression, in text: String) -> String? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).lazy.compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }.first
    }
    private static let exitPattern = try! NSRegularExpression(pattern: #"Process exited with code (-?\d+)|"exit_code"\s*:\s*(-?\d+)"#)
    private static let sessionPattern = try! NSRegularExpression(pattern: #"Process running with session ID (\d+)|"session_id"\s*:\s*(\d+)"#)
    private static func clipped(_ value: Any?) -> String? { (value as? String).map { String($0.prefix(1000)) } }
    public static func transcript(_ r: [String: Any], session: Session, id: String, now: Date) -> [ActivityEvent] {
        let time = date(r["timestamp"])
        func event(_ kind: String, _ state: ActivityState? = nil, call: String? = nil, tool: String? = nil, detail: String? = nil, turn: String? = nil) -> ActivityEvent {
            .init(id: id + ":" + (call ?? kind), provider: session.provider.rawValue, sessionID: session.sessionID,
                  kind: kind, source: "Transcript · version-dependent", recordedAt: time, observedAt: now,
                  turnID: turn, callID: call, tool: tool, detail: detail, state: state)
        }
        if session.provider == .codex {
            guard let p = r["payload"] as? [String: Any], let type = p["type"] as? String else { return [] }
            let turn = p["turn_id"] as? String
            if r["type"] as? String == "event_msg" {
                switch type {
                case "task_started": return [event("started", .working, turn: turn)]
                case "task_complete": return [event("finished", .finished, turn: turn)]
                case "turn_aborted": return [event("interrupted", .interrupted, turn: turn)]
                default: return []
                }
            }
            guard r["type"] as? String == "response_item" else { return [] }
            // The agent's progress notes to you ("I'll check the setup first…").
            if type == "message", p["role"] as? String == "assistant" {
                let text = (p["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: " ")
                return text.isEmpty ? [] : [event("commentary", detail: clipped(text), turn: turn)]
            }
            let call = p["call_id"] as? String
            if ["function_call", "custom_tool_call"].contains(type) {
                // A patch names its files in its headers; the patch text itself is not a detail.
                if p["name"] as? String == "apply_patch", let input = p["input"] as? String {
                    return [event("toolStarted", .working, call: call, tool: "apply_patch", detail: clipped(patchFiles(input).joined(separator: "\n")), turn: turn)]
                }
                // Code-mode calls wrap real tools in JavaScript, often several per script
                // (`tools.update_plan(…); tools.apply_patch(…); tools.exec_command({cmd:"…"})`):
                // each becomes its own event. The script's output has one result per call, in
                // order; shell calls wait for theirs (exit codes, sessions), others return at once.
                if let input = p["input"] as? String {
                    let inner = codeModeCalls(input)
                    if !inner.isEmpty {
                        var events: [ActivityEvent] = []
                        for (index, item) in inner.enumerated() {
                            let last = index == inner.count - 1
                            let id = last ? call : call.map { $0 + "#\(index)" }
                            events.append(event("toolStarted", .working, call: id, tool: item.tool, detail: item.detail.map { String($0.prefix(1000)) }, turn: turn))
                            if !last, !KitchenActivity.commandTools.contains(item.tool.lowercased()) { events.append(event("toolFinished", call: id, turn: turn)) }
                        }
                        return events
                    }
                }
                let args = (p["arguments"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
                // Codex's JavaScript runner driving the Computer Use plugin (a browser preview, an app).
                if p["name"] as? String == "js", let code = args?["code"] as? String, code.contains("cua.") {
                    return [event("toolStarted", .working, call: call, tool: "computer_use", detail: clipped(args?["title"] ?? "Computer Use"), turn: turn)]
                }
                // A poll names the session it reads, so its exit settles the command running there.
                let polled = p["name"] as? String == "write_stdin" ? (args?["session_id"]).map { "session=\($0)" } : nil
                let command = polled ?? (args?["command"] as? [String])?.joined(separator: " ") ?? args?["command"] ?? args?["cmd"] ?? args?["file_path"]
                // Heredoc bodies (whole files written inline) would crowd out what the command runs.
                return [event("toolStarted", .working, call: call, tool: p["name"] as? String, detail: clipped((command as? String).map(KitchenActivity.withoutHeredocs) ?? command), turn: turn)]
            }
            if ["function_call_output", "custom_tool_call_output"].contains(type) {
                // Shell output reports its exit status, or the session a still-running command
                // continues in (a later `write_stdin` poll reports its exit); the detail carries both.
                func finish(_ output: String, call: String?) -> ActivityEvent {
                    let code = exitCode(output), session = sessionID(output)
                    let detail = [code.map { "exit=\($0)" }, session.map { "session=\($0)" }].compactMap { $0 }.joined(separator: " ")
                    return event(code.map { $0 != 0 } == true ? "toolFailed" : "toolFinished", call: call, detail: detail.isEmpty ? nil : detail, turn: turn)
                }
                let parts = (p["output"] as? [[String: Any]])?.compactMap { $0["text"] as? String }
                // A code-mode script's output: a "Script completed" header, then one result per
                // inner call. Each finishes its own call (`call#i`, the last one `call`).
                if let parts, parts.count > 2, parts[0].hasPrefix("Script ") {
                    let results = parts.dropFirst()
                    return results.enumerated().map { index, text in finish(text, call: index == results.count - 1 ? call : call.map { $0 + "#\(index)" }) }
                }
                return [finish((p["output"] as? String) ?? (parts?.joined(separator: "\n") ?? ""), call: call)]
            }
        } else if let message = r["message"] as? [String: Any] {
            let blocks = message["content"] as? [[String: Any]] ?? []
            var events: [ActivityEvent] = []
            // Claude persists cancellation as a synthetic user message. Do not
            // mistake its exact sentinel for a newly submitted prompt.
            let interruptionMarkers: Set<String> = ["[Request interrupted by user]", "[Request interrupted by user for tool use]"]
            let soleText = (message["content"] as? String) ?? (blocks.count == 1 && blocks[0]["type"] as? String == "text" ? blocks[0]["text"] as? String : nil)
            if r["type"] as? String == "user", let soleText, interruptionMarkers.contains(soleText) {
                return [event("interrupted", .interrupted)]
            }
            if r["type"] as? String == "user", r["isMeta"] as? Bool != true,
               !blocks.contains(where: { $0["type"] as? String == "tool_result" }),
               message["content"] is String || blocks.contains(where: { $0["type"] as? String == "text" }) {
                events.append(event("started", .working))
            }
            events += blocks.enumerated().compactMap { index, block in
                var result: ActivityEvent
                switch block["type"] as? String {
                case "tool_use":
                    let args = block["input"] as? [String: Any]
                    result = event("toolStarted", block["name"] as? String == "AskUserQuestion" ? .input : .working, call: block["id"] as? String, tool: block["name"] as? String, detail: clipped(args?["command"] ?? args?["file_path"] ?? args?["skill"] ?? args?["pattern"]))
                case "tool_result":
                    result = event(block["is_error"] as? Bool == true ? "toolFailed" : "toolFinished", call: block["tool_use_id"] as? String)
                case "text" where r["type"] as? String == "assistant":
                    guard let text = block["text"] as? String, !text.isEmpty else { return nil }
                    result = event("commentary", detail: clipped(text))
                default: return nil
                }
                result.id = id + ":\(index)"; return result
            }
            if r["type"] as? String == "assistant", message["stop_reason"] as? String == "end_turn" {
                events.append(event("finished", .finished))
            }
            return events
        }
        return []
    }

    /// Only explicitly allowlisted fields leave the reporter. Hook bodies are never retained.
    public static func hook(_ r: [String: Any], provider: Provider, now: Date = Date()) -> ActivityEvent? {
        guard let sid = r["session_id"] as? String, !sid.isEmpty, let name = r["hook_event_name"] as? String else { return nil }
        var kind: String
        var state: ActivityState?
        switch name {
        case "UserPromptSubmit": kind = "started"; state = .working
        case "PreToolUse":
            kind = "toolStarted"
            state = provider == .claude && r["tool_name"] as? String == "AskUserQuestion" ? .input : .working
        case "PostToolUse": kind = "toolFinished"; state = .working
        case "PostToolUseFailure" where provider == .claude: kind = "toolFailed"; state = .working
        case "PermissionRequest":
            let question = provider == .claude && r["tool_name"] as? String == "AskUserQuestion"
            kind = question ? "input" : "approval"; state = question ? .input : .approval
        case "Stop": kind = "stopping" // Other hooks can continue the turn. Not confirmed completion.
        case "Interrupt" where provider == .codex: kind = "interrupted"; state = .interrupted
        case "PreCompact": kind = "compact"; state = .working
        case "PostCompact": kind = "compacted"
        case "SessionStart": kind = "sessionStarted"
        case "SessionEnd": kind = "sessionEnded"
        case "SubagentStart": kind = "agentStarted"
        case "SubagentStop": kind = "agentStopped"
        case "Notification" where provider == .claude:
            switch r["notification_type"] as? String {
            case "permission_prompt": kind = "approval"; state = .approval
            case "idle_prompt": kind = "idle"; state = .idle
            case "elicitation_dialog", "elicitation_url_dialog": kind = "input"; state = .input
            default: return nil
            }
        default: return nil
        }
        let input = r["tool_input"] as? [String: Any]
        return .init(id: UUID().uuidString, provider: provider.rawValue, sessionID: sid, kind: kind,
                     source: "Hook · \(name)\((r["notification_type"] as? String).map { ":" + String($0.prefix(100)) } ?? "") · reported event; current activity unverified", recordedAt: date(r["timestamp"]), observedAt: now,
                     turnID: clipped(r["turn_id"]), callID: clipped(r["tool_use_id"]), agentID: clipped(r["agent_id"]),
                     parentID: clipped(r["parent_session_id"]), role: clipped(r["agent_type"]), tool: clipped(r["tool_name"]),
                     detail: clipped(r["error"] ?? input?["command"] ?? input?["file_path"] ?? input?["description"]),
                     durationMS: r["duration_ms"] as? Double, state: state)
    }
}

/// Bounded tail bootstrap, then append-only reads. No transcript bodies are cached.
public actor ActivityLibrary {
    private struct Cursor {
        var identity: UInt64
        var offset: UInt64
        var modified: Date
        var pending = Data()
        var events: [ActivityEvent] = []
        var skippingLongLine = false
        var lastState: ActivityEvent?
    }
    private var cursors: [URL: Cursor] = [:]
    public init() {}
    public func scan(_ sessions: [Session], hookDirectory: URL? = HookStore.directory, retainingOtherCursors: Bool = false) -> [String: ActivitySummary] {
        var result: [String: ActivitySummary] = [:]
        let hooks = hookDirectory.map { HookStore.read(directory: $0) } ?? []
        for session in sessions {
            let matching = hooks.filter { event in
                guard event.provider == session.provider.rawValue else { return false }
                let lifecycle = ["agentStarted", "agentStopped"].contains(event.kind)
                if session.classification != .subagent {
                    return event.sessionID == session.sessionID && (event.agentID == nil || lifecycle)
                }
                if session.provider == .codex {
                    return event.sessionID == session.sessionID || (lifecycle && event.agentID == session.sessionID)
                }
                let agent = session.url?.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "agent-", with: "")
                return event.agentID == agent && event.sessionID == session.parentID
            }
            let scoped = matching.map { event in
                var scoped = event
                if session.classification == .subagent, event.kind == "agentStarted" { scoped.state = .working }
                return scoped
            }
            guard let url = session.url else {
                result[session.id] = .merged(scoped, error: "Local activity transcript unavailable; hook evidence only")
                continue
            }
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let identity = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                let modified = attributes[.modificationDate] as? Date ?? .distantPast
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                var cursor = cursors[url]
                var bootstrapped = false
                if cursor == nil || cursor!.identity != identity || size < cursor!.offset || (size == cursor!.offset && modified != cursor!.modified) {
                    let start = size > 512 * 1024 ? size - 512 * 1024 : 0
                    cursor = Cursor(identity: identity, offset: start, modified: modified, skippingLongLine: start > 0)
                    bootstrapped = true
                }
                var c = cursor!
                try file.seek(toOffset: c.offset)
                let data = try file.read(upToCount: 2 * 1024 * 1024) ?? Data()
                c.offset += UInt64(data.count); c.modified = modified; c.pending.append(data)
                var consumed = 0
                for end in c.pending.indices where c.pending[end] == 10 {
                    let start = consumed; consumed = end + 1
                    if c.skippingLongLine { c.skippingLongLine = false; continue }
                    guard end - start <= 1024 * 1024, let record = try? JSONSerialization.jsonObject(with: c.pending[start..<end]) as? [String: Any] else { continue }
                    let byteOffset = c.offset - UInt64(c.pending.count) + UInt64(start)
                    let id = (record["uuid"] as? String).map { session.id + ":" + $0 } ?? "\(identity):\(byteOffset)"
                    c.events += ActivityParser.transcript(record, session: session, id: id, now: Date())
                }
                c.pending = Data(c.pending.dropFirst(consumed))
                if c.pending.count > 1024 * 1024 { c.pending.removeAll(); c.skippingLongLine = true }
                if let latest = ActivitySummary.merged(c.events).latestState { c.lastState = latest }
                // A long-running turn can start before the recent activity window. Search a
                // bounded larger tail for its last explicit state, without importing messages.
                if bootstrapped && c.lastState == nil && session.provider == .codex && size > 512 * 1024 {
                    let start = size > 16 * 1024 * 1024 ? size - 16 * 1024 * 1024 : 0
                    try file.seek(toOffset: start)
                    let tail = try file.read(upToCount: 16 * 1024 * 1024) ?? Data()
                    if let final = tail.lastIndex(of: 10) {
                        var offset = start
                        var historyStates: [ActivityEvent] = []
                        for (index, line) in tail.prefix(through: final).split(separator: 10, omittingEmptySubsequences: false).enumerated() {
                            defer { offset += UInt64(line.count + 1) }
                            if index == 0 && start > 0 { continue }
                            guard String(decoding: line.prefix(256), as: UTF8.self).contains("event_msg"),
                                  let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                                  let state = ActivityParser.transcript(record, session: session, id: "\(identity):\(offset)", now: Date()).last(where: { $0.state != nil }) else { continue }
                            historyStates.append(state)
                        }
                        c.lastState = ActivitySummary.merged(historyStates).latestState
                    }
                }
                c.events = Array(c.events.suffix(499))
                if let state = c.lastState, !c.events.contains(where: { $0.id == state.id }) { c.events.insert(state, at: 0) }
                cursors[url] = c
                result[session.id] = .merged(c.events + scoped)
            } catch { result[session.id] = .merged((cursors[url]?.events ?? []) + scoped, error: error.localizedDescription) }
        }
        let urls = Set(sessions.compactMap(\.url))
        if retainingOtherCursors {
            // A selected parent and its children are read separately. Preserve their
            // lifecycle baseline instead of repeatedly bootstrapping a short tail.
            for key in cursors.keys.filter({ !urls.contains($0) }).sorted(by: { $0.path < $1.path }).prefix(max(0, cursors.count - 24)) {
                cursors.removeValue(forKey: key)
            }
        } else { cursors = cursors.filter { urls.contains($0.key) } }
        return result
    }
}
