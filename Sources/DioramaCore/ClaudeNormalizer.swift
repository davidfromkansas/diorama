import Foundation

public struct ClaudeOutput: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var location: String? = nil
    public var mediaType: String? = nil
    public var encoded: String? = nil
    public var note: String? = nil
    public init(id: String, name: String, kind: String, location: String? = nil, mediaType: String? = nil, encoded: String? = nil, note: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.location = location
        self.mediaType = mediaType; self.encoded = encoded; self.note = note
    }
}

public struct ClaudeChecklistItem: Codable, Equatable, Sendable {
    public var title: String
    public var status: String
}

public struct ClaudePresentation: Codable, Equatable, Sendable {
    public var title: String
    public var status: String
    public var callID: String? = nil
    public var agentID: String? = nil
    public var input: String = ""
    public var outputs: [ClaudeOutput] = []
    public var detail: String = ""
    public var checklist: [ClaudeChecklistItem]? = nil
    public var category: String? = nil
    public var evidence: WireValue? = nil
    public var toolName: String? = nil
    public var resultEvidence: WireValue? = nil
}

/// Normalizes saved Claude evidence. It never executes tools or interprets prose as instructions.
public enum ClaudeNormalizer {
    private static let ignored = Set(["thinking", "redacted_thinking", "signature", "queue-operation", "last-prompt", "summary", "custom-title", "agent-name", "file-history-snapshot", "atis-latch"])
    private static let internalAttachments = Set(["hook_success", "environment", "model", "deferred_tools_delta", "agent_listing_delta", "mcp_instructions_delta", "skill_listing", "auto_mode", "total_tokens_reminder", "session_context", "date", "remote_session_change", "prompt_snapshot"])
    private static func bounded(_ text: String, limit: Int = 64 * 1024) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n[Output truncated; inspect the original conversation for more.]"
    }
    private static func pretty(_ value: Any?) -> String {
        guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return bounded(String(decoding: data, as: UTF8.self))
    }
    public static func parse(_ data: Data, scope: String, start: UInt64 = 0, limit: Int = 300, sourcePath: String? = nil) -> Transcript {
        var result = Transcript(), entries: [Entry] = []
        var calls: [String: Int] = [:], seen = Set<String>()
        var messageUsage: [String: Int] = [:]
        var offset = start
        func unknown(_ type: String) { result.unrecognizedTypes[String(type.prefix(100)), default: 0] += 1 }
        for line in SessionLibrary.completeLines(data) {
            offset = start + UInt64(data.distance(from: data.startIndex, to: line.startIndex))
            if Task.isCancelled { break }
            guard let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { result.malformed += 1; continue }
            let uuid = r["uuid"] as? String ?? "byte-\(offset)"
            guard seen.insert(uuid).inserted else { continue }
            let base = scope + ":" + uuid, type = r["type"] as? String ?? "unknown"
            let stamp = r["timestamp"] as? String, agent = r["agentId"] as? String ?? r["agent_id"] as? String
            let owner = agent ?? "main"
            let folder = r["cwd"] as? String
            func entry(_ id: String, _ kind: String, _ text: String, _ presentation: ClaudePresentation? = nil) -> Entry {
                var e = Entry(id: id, kind: kind, text: bounded(text), timestamp: stamp)
                e.providerItemID = uuid; e.claude = presentation
                if kind == "Assistant", agent == nil {
                    e.completionMessageID = (r["message"] as? [String: Any])?["id"] as? String ?? uuid
                }
                if kind != "System context", let reference = TranscriptSource(path: sourcePath ?? scope, offset: offset, record: Data(line)) { e.sourceRecords = [reference] }
                return e
            }
            if type == "attachment" {
                let attachment = r["attachment"] as? [String: Any] ?? [:]
                let subtype = attachment["type"] as? String ?? "unknown"
                if !internalAttachments.contains(subtype) {
                    unknown("attachment/" + subtype)
                    entries.append(entry(base, "Event", "", .init(title: "Attachment · " + subtype, status: "Unrecognized", agentID: agent, category: "unknown", evidence: safe(attachment))))
                }
                continue
            }
            if type == "progress" {
                let progress = r["data"] as? [String: Any] ?? [:]
                let subtype = progress["type"] as? String ?? "unknown"
                let known = ["agent_progress", "bash_progress", "mcp_progress", "hook_progress"].contains(subtype)
                if !known { unknown("progress/" + subtype) }
                entries.append(entry(base, "Event", "", .init(title: known ? "Reported " + subtype.replacingOccurrences(of: "_", with: " ") : "Unrecognized progress · " + subtype,
                    status: progress["status"] as? String ?? "Reported", agentID: agent, category: known ? "progress" : "unknown", evidence: safe(progress))))
                continue
            }
            if type != "assistant" && type != "user" {
                if type == "cost-state" {
                    entries.append(entry(base, "Event", "", .init(title: "Claude session usage", status: "Reported", agentID: agent, category: "sessionUsage", evidence: safe(r))))
                    continue
                }
                if type == "mode", let mode = r["mode"] as? String {
                    entries.append(entry(base, "Event", "Reported mode: " + mode, .init(title: "Claude mode", status: "Reported", agentID: agent, category: "event", evidence: safe(r))))
                    continue
                }
                let subtype = r["subtype"] as? String ?? type
                if ["compact_boundary", "status", "task_started", "task_progress", "task_notification", "result", "rate_limit_event"].contains(subtype) || type == "result" || type == "rate_limit_event" {
                    let title = subtype == "compact_boundary" ? "Context compacted" : type == "result" ? "Turn result" : type == "rate_limit_event" ? "Rate limits" : "Session · " + subtype
                    var fields: [String: Any] = [:]
                    for key in ["status", "duration_ms", "duration_api_ms", "usage", "modelUsage", "total_cost_usd", "rate_limit_info", "description", "summary", "is_error", "task_id", "tool_use_id", "output_file", "error", "errors"] { fields[key] = r[key] }
                    entries.append(entry(base, "Event", pretty(fields), .init(title: title, status: r["is_error"] as? Bool == true ? "Failed" : r["status"] as? String ?? "Reported", agentID: agent, category: type == "result" ? "usage" : subtype.hasPrefix("task_") ? "task" : "event", evidence: safe(fields))))
                } else if !ignored.contains(type) && subtype != "stop_hook_summary" {
                    unknown(type + "/" + subtype)
                    entries.append(entry(base, "Event", "", .init(title: "Unrecognized event · " + type + "/" + subtype, status: "Unrecognized", agentID: agent, category: "unknown", evidence: safe(r))))
                }
                continue
            }
            guard let message = r["message"] as? [String: Any] else { unknown(type + "/missing-message"); continue }
            let blocks = (message["content"] as? [[String: Any]]) ?? (message["content"] as? String).map { [["type": "text", "text": $0]] } ?? []
            for (index, block) in blocks.enumerated() {
                let blockType = block["type"] as? String ?? "unknown", id = base + ":\(index)"
                switch blockType {
                case "text":
                    let text = block["text"] as? String ?? ""
                    if ["[Request interrupted by user]", "[Request interrupted by user for tool use]"].contains(text), type == "user" {
                        for i in calls.values where entries[i].claude?.status == "Running" { entries[i].claude?.status = "Interrupted" }
                        entries.append(entry(id, "Event", "Interrupted", .init(title: "Interrupted", status: "Interrupted", agentID: agent)))
                    } else {
                        let kind = r["isMeta"] as? Bool == true ? "System context" : type == "user" ? "You" : "Assistant"
                        let cleaned = kind == "Assistant" ? text.replacingOccurrences(of: #"(?m)^DIORAMA_GOAL_[A-Fa-f0-9-]{36}:(?:COMPLETE|CONTINUE|BLOCKED)[ \t]*$"#, with: "", options: .regularExpression) : text
                        for (partIndex, part) in MessageContent.split(cleaned, provider: .claude).enumerated() where !part.text.isEmpty {
                            entries.append(entry(id + ":\(partIndex)", part.context ? "System context" : kind, part.text))
                        }
                    }
                case "tool_use":
                    let name = block["name"] as? String ?? "Tool", call = block["id"] as? String ?? id
                    let args = block["input"] as? [String: Any] ?? [:]
                    let action = args["action"] as? String
                    let title = name + (action.map { " · " + $0.prefix(1).uppercased() + $0.dropFirst() } ?? "")
                    var presentation = ClaudePresentation(title: title, status: name == "AskUserQuestion" ? "Waiting for input" : "Running", callID: call, agentID: agent, input: pretty(args), category: name == "WebSearch" ? "search" : name == "WebFetch" ? "fetch" : name == "Task" || name == "Agent" ? "delegation" : name == "Artifact" ? "artifact" : "tool", evidence: safe(args), toolName: name)
                    // File references are only promoted to outputs once this call succeeds.
                    if ["Write", "Edit", "MultiEdit", "NotebookEdit"].contains(name), let path = args["file_path"] as? String ?? args["notebook_path"] as? String {
                        presentation.outputs = [fileOutput(path, folder: folder, id: id + ":file", note: "Requested file change")]
                    } else if name == "Artifact", (action == nil || ["publish", "create", "update"].contains(action ?? "")), let path = args["file_path"] as? String ?? args["path"] as? String {
                        presentation.outputs = [fileOutput(path, folder: folder, id: id + ":artifact", note: "Requested artifact")]
                    }
                    if name == "ExitPlanMode" { presentation.detail = args["plan"] as? String ?? pretty(args) }
                    else if ["TodoWrite", "TaskCreate", "TaskUpdate", "AskUserQuestion"].contains(name) { presentation.detail = pretty(args) }
                    if name == "TodoWrite", let todos = args["todos"] as? [[String: Any]] {
                        presentation.checklist = todos.prefix(100).map {
                            .init(title: bounded($0["content"] as? String ?? $0["activeForm"] as? String ?? "Task"), status: $0["status"] as? String ?? "Reported")
                        }
                    } else if name == "TaskCreate" || name == "TaskUpdate" {
                        presentation.checklist = [.init(title: args["subject"] as? String ?? "Task " + (args["taskId"] as? String ?? ""), status: args["status"] as? String ?? "Requested")]
                    }
                    calls[owner + ":" + call] = entries.count
                    entries.append(entry(id, name == "ExitPlanMode" ? "Proposed plan" : "Tool call", args["plan"] as? String ?? "", presentation))
                case "tool_result":
                    let call = block["tool_use_id"] as? String ?? id
                    let parsed = content(block["content"], id: id)
                    let failed = block["is_error"] as? Bool == true
                    if let i = calls[owner + ":" + call] {
                        entries[i].text = parsed.text
                        if let reference = TranscriptSource(path: sourcePath ?? scope, offset: offset, record: Data(line)) { entries[i].sourceRecords = (entries[i].sourceRecords ?? []) + [reference] }
                        if var presentation = entries[i].claude {
                            presentation.status = failed ? "Failed" : presentation.toolName == "AskUserQuestion" ? "Resolved" : "Completed"
                            presentation.outputs = failed ? [] : presentation.outputs.map {
                                var output = $0
                                output.note = presentation.title.hasPrefix("Artifact") ? "Artifact · preview shows current file" : "Reported file change · preview shows current file"
                                return output
                            }
                            presentation.outputs += parsed.outputs
                            if let structured = r["tool_use_result"] ?? r["toolUseResult"] {
                                presentation.detail = pretty(structured)
                                presentation.resultEvidence = safe(structured)
                            }
                            entries[i].claude = presentation
                        }
                    } else {
                        entries.append(entry(id, "Tool result", parsed.text, .init(title: "Tool result", status: failed ? "Failed" : "Completed", callID: call, agentID: agent, outputs: parsed.outputs, detail: "Originating call is outside the loaded history.")))
                    }
                default:
                    if ignored.contains(blockType) { continue }
                    let parsed = content([block], id: id)
                    if parsed.outputs.contains(where: { $0.kind == "unsupported" }) { unknown("content/" + blockType) }
                    entries.append(entry(id, type == "user" ? "You" : "Assistant", parsed.text, .init(title: type == "user" ? "Attachment" : "Output", status: "Reported", agentID: agent, outputs: parsed.outputs)))
                }
            }
            if let usage = message["usage"] as? [String: Any] {
                let presentation = ClaudePresentation(title: "Claude message usage", status: "Reported", agentID: agent, category: "usage", evidence: safe(["usage": usage, "scope": "message"]))
                let row = entry(base + ":usage", "Event", "", presentation)
                // Desktop persists each content block separately, repeating message-level
                // usage. Update the existing card without deduplicating the actual blocks.
                let key = (message["id"] as? String).flatMap { id in
                    id.isEmpty ? nil : [r["sessionId"] as? String ?? scope, owner, id].joined(separator: "\u{1f}")
                }
                if let key, let index = messageUsage[key] {
                    entries[index].claude = presentation
                    entries[index].sourceRecords = (entries[index].sourceRecords ?? []) + (row.sourceRecords ?? [])
                } else {
                    if let key { messageUsage[key] = entries.count }
                    entries.append(row)
                }
            }
        }
        result.earlierContentOmitted = start > 0 || entries.count > limit
        result.entries = Array(entries.suffix(max(1, limit)))
        return result
    }

    private static func safe(_ value: Any) -> WireValue {
        CodexOutputEvidence.safeDetails(TranscriptSource.inspectable(CodexOutputEvidence.wire(value)))
    }
    private static func fileOutput(_ path: String, folder: String?, id: String, note: String) -> ClaudeOutput {
        let location = path.hasPrefix("/") ? path : folder.map { URL(fileURLWithPath: $0).appendingPathComponent(path).path }
        return .init(id: id, name: URL(fileURLWithPath: path).lastPathComponent, kind: "file", location: location, note: location == nil ? "Relative path has no recorded working folder" : note)
    }
    private static func content(_ value: Any?, id: String) -> (text: String, outputs: [ClaudeOutput]) {
        if let string = value as? String { return (bounded(string), []) }
        guard let blocks = value as? [[String: Any]] else { return (pretty(value), []) }
        var texts: [String] = [], outputs: [ClaudeOutput] = []
        for (i, block) in blocks.enumerated() {
            let type = block["type"] as? String ?? "unknown", key = id + ":content:\(i)"
            switch type {
            case "text": texts.append(block["text"] as? String ?? "")
            case "image", "document":
                let source = block["source"] as? [String: Any] ?? block
                let encoded = source["type"] as? String == "text" ? (source["data"] as? String).map { Data($0.utf8).base64EncodedString() } : source["data"] as? String
                let allowed = (encoded?.utf8.count ?? 0) <= 8 * 1024 * 1024
                outputs.append(.init(id: key, name: block["title"] as? String ?? (type == "image" ? "Image" : "Document"), kind: type, location: source["url"] as? String, mediaType: source["media_type"] as? String ?? block["mimeType"] as? String, encoded: allowed ? encoded : nil, note: allowed ? nil : "Content exceeds the 8 MiB inline preview limit"))
            case "resource":
                let resource = block["resource"] as? [String: Any] ?? [:]
                let uri = resource["uri"] as? String
                let inline = (resource["text"] as? String).map { Data($0.utf8).base64EncodedString() } ?? resource["blob"] as? String
                let allowed = (inline?.utf8.count ?? 0) <= 8 * 1024 * 1024
                outputs.append(.init(id: key, name: block["name"] as? String ?? uri.flatMap { URL(string: $0)?.lastPathComponent } ?? "Resource", kind: "resource", location: uri, mediaType: resource["mimeType"] as? String, encoded: allowed ? inline : nil, note: allowed ? nil : "Content exceeds the inline preview limit"))
            case "resource_link", "resourceLink":
                outputs.append(.init(id: key, name: block["name"] as? String ?? "Resource", kind: "resource", location: block["uri"] as? String, mediaType: block["mimeType"] as? String))
            default:
                if !ignored.contains(type) { outputs.append(.init(id: key, name: "Unsupported content · " + type, kind: "unsupported", note: "This content type has no preview yet.")) }
            }
        }
        return (bounded(texts.joined(separator: "\n")), outputs)
    }
}
