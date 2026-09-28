import Foundation

/// Read-only rollout normalization. Native UI items take precedence over duplicate
/// model-facing records, while unpaired tool results remain inspectable.
public enum CodexTranscriptNormalizer {
    public static func parse(_ data: Data, scope: String, start: UInt64, limit: Int, sourcePath: String? = nil) -> Transcript {
        var transcript = Transcript(), entries: [Entry] = []
        let lines = SessionLibrary.completeLines(data)
        var structuredMessages: [String: Set<String>] = [:]
        var structuredTools = Set<String>(), scanTurn = ""
        for line in lines {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let p = row["payload"] as? [String: Any] else { continue }
            scanTurn = p["turn_id"] as? String ?? scanTurn
            guard row["type"] as? String == "event_msg", ["item_started", "item_completed"].contains(p["type"] as? String ?? ""),
                  let item = p["item"] as? [String: Any] else { continue }
            let type = item["type"] as? String ?? ""
            let canonical = type.prefix(1).lowercased() + type.dropFirst()
            if ["userMessage", "agentMessage", "plan"].contains(canonical) {
                let native = CodexOutputEvidence.canonical(CodexOutputEvidence.wire(item))
                let text = canonical == "userMessage" ? CodexOutputEvidence.text(native["content"]) : native["text"].string ?? ""
                if !text.isEmpty { structuredMessages[scanTurn, default: []].insert(canonical + ":" + text) }
            }
            else if let id = item["id"] as? String { structuredTools.insert(scanTurn + ":" + id) }
        }
        var turn = "", cwd: String?, offset = start
        var indexes: [String: Int] = [:]
        func put(_ entry: Entry) {
            if let i = indexes[entry.id] {
                var updated = entry
                let previous = entries[i].sourceRecords ?? []
                updated.sourceRecords = previous + (entry.sourceRecords ?? []).filter { !previous.contains($0) }
                entries[i] = updated
            }
            else { indexes[entry.id] = entries.count; entries.append(entry) }
        }
        for line in lines {
            offset = start + UInt64(data.distance(from: data.startIndex, to: line.startIndex))
            if Task.isCancelled { break }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { transcript.malformed += 1; continue }
            let row = CodexOutputEvidence.wire(object)
            let p = row["payload"], recordType = row["type"].string ?? "unknown", type = p["type"].string ?? ""
            turn = p["turn_id"].string ?? turn
            cwd = p["cwd"].string ?? cwd
            let stamp = row["timestamp"].string
            func entry(_ id: String, kind: String, text: String, native: String? = nil, tool: ToolResult? = nil) -> Entry {
                var value = Entry(id: scope + ":" + turn + ":" + id, kind: kind, text: CodexOutputEvidence.bounded(text), timestamp: stamp, tool: tool, turnID: turn.isEmpty ? nil : turn, providerItemID: native)
                if let tool { value.codex = .tool(tool) }
                if kind != "System context", let reference = TranscriptSource(path: sourcePath ?? scope, offset: offset, record: Data(line)) { value.sourceRecords = [reference] }
                return value
            }
            func tools(_ item: WireValue, id: String) {
                if let tool = ToolResult(item: item) { put(entry(id, kind: "Tool activity", text: tool.title + (tool.output.isEmpty ? "" : "\n" + tool.output), native: item["id"].string, tool: tool)) }
                else {
                    let type = item["type"].string ?? "unknown"
                    if !["reasoning", "hookPrompt"].contains(type) {
                        transcript.unrecognizedTypes["item/" + String(type.prefix(100)), default: 0] += 1
                        var unknown = entry(id, kind: "Event", text: "Unrecognized Codex item · " + String(type.prefix(100)), native: item["id"].string)
                        unknown.codex = .init(category: "unknown", title: "Unrecognized event · " + String(type.prefix(100)), evidence: CodexOutputEvidence.safeDetails(item))
                        put(unknown)
                    }
                }
            }
            func event(_ title: String, category: String, key: String? = nil) {
                var value = entry(key ?? "event-\(offset)", kind: "Event", text: title)
                value.codex = .init(category: category, title: title, status: p["status"].string ?? "Reported", evidence: CodexOutputEvidence.safeDetails(p))
                put(value)
            }
            if recordType == "token_usage_record" {
                // Retained as a separately scoped record: never sum it with token_count.
                event("Reported usage record", category: "usageRecord")
            } else if recordType == "event_msg" {
                if ["item_started", "item_completed"].contains(type) {
                    let item = CodexOutputEvidence.canonical(p["item"], cwd: cwd)
                    let native = item["id"].string, key = native ?? "byte-\(offset)"
                    switch item["type"].string {
                    case "userMessage":
                        for (index, part) in MessageContent.split(CodexOutputEvidence.text(item["content"]), provider: .codex).enumerated() {
                            put(entry(key + ":\(index)", kind: part.context ? "System context" : "You", text: part.text, native: native))
                        }
                        let media = item["content"].array.filter { !["text", "input_text"].contains(($0["type"].string ?? "").lowercased()) }
                        if !media.isEmpty { tools(.object(["id": .string(key + ":attachments"), "type": .string("functionCallOutput"), "name": .string("User attachments"), "output": .array(media)]), id: key + ":attachments") }
                    case "agentMessage": put(entry(key, kind: "Assistant", text: item["text"].string ?? "", native: native))
                    case "plan": put(entry(key, kind: "Proposed plan", text: item["text"].string ?? "", native: native))
                    case "contextCompaction": put(entry(key, kind: "Event", text: "Conversation compacted", native: native))
                    case "enteredReviewMode", "exitedReviewMode":
                        if item["type"].string == "exitedReviewMode" { tools(item, id: key) }
                        else { put(entry(key, kind: "Event", text: "Code review started", native: native)) }
                    default: tools(item, id: key)
                    }
                } else if let state = ["task_started": "Working", "task_complete": "Last turn finished", "turn_aborted": "Interrupted"][type] {
                    transcript.state = state
                    put(entry("event-\(offset)", kind: "Event", text: state))
                } else if type == "token_count" {
                    event("Token usage", category: "usage", key: "usage")
                } else if ["warning", "error", "stream_error", "request_user_input", "request_resolved", "exec_approval_request", "apply_patch_approval_request"].contains(type) {
                    event(type.replacingOccurrences(of: "_", with: " ").capitalized, category: "notice")
                } else if !["agent_message", "user_message", "agent_reasoning", "agent_reasoning_raw_content"].contains(type) {
                    transcript.unrecognizedTypes["event/" + String(type.prefix(100)), default: 0] += 1
                    event("Unrecognized event · " + String(type.prefix(100)), category: "unknown")
                }
            } else if recordType == "response_item" {
                let native = p["call_id"].string ?? p["id"].string, key = native ?? "byte-\(offset)"
                switch type {
                case "message":
                    let role = p["role"].string ?? "", text = CodexOutputEvidence.text(p["content"])
                    let parts = MessageContent.split(text, provider: .codex)
                    if role == "assistant", structuredMessages[turn]?.contains("agentMessage:" + text) == true { continue }
                    if role == "user", structuredMessages[turn]?.contains("userMessage:" + text) == true, parts.contains(where: { !$0.context }) { continue }
                    for (index, part) in parts.enumerated() where !part.text.isEmpty {
                        let kind = part.context || ["system", "developer"].contains(role) ? "System context" : role == "user" ? "You" : "Assistant"
                        put(entry(key + ":\(index)", kind: kind, text: part.text, native: native))
                    }
                    let media = p["content"].array.filter { !["input_text", "output_text", "text"].contains($0["type"].string ?? "") }
                    if !media.isEmpty { tools(.object(["type": .string("functionCallOutput"), "id": .string(key + ":attachments"), "name": .string(role == "user" ? "User attachments" : "Message outputs"), "output": .array(media)]), id: key + ":attachments") }
                case "function_call", "custom_tool_call":
                    if structuredTools.contains(turn + ":" + key) { continue }
                    let arguments = p["arguments"] == .null ? p["input"] : p["arguments"]
                    tools(.object(["type": .string("functionCall"), "id": .string(key), "name": p["name"], "arguments": arguments, "status": .string("Called")]), id: key)
                case "function_call_output", "custom_tool_call_output":
                    if structuredTools.contains(turn + ":" + key) { continue }
                    let rowID = scope + ":" + turn + ":" + key
                    var item = indexes[rowID].flatMap { entries[$0].tool?.item.object } ?? ["type": .string("functionCallOutput"), "id": .string(key), "name": .string("Tool result · call outside loaded history")]
                    item["output"] = p["output"]; item["status"] = .string("Returned")
                    tools(.object(item), id: key)
                case "image_generation_call":
                    var item = p.object; item["type"] = .string("imageGeneration"); item["id"] = .string(key)
                    tools(.object(item), id: key)
                case "reasoning": break
                default:
                    transcript.unrecognizedTypes["response/" + String(type.prefix(100)), default: 0] += 1
                    event("Unrecognized response · " + String(type.prefix(100)), category: "unknown")
                }
            } else if recordType == "compacted" {
                put(entry("event-\(offset)", kind: "Event", text: "Conversation compacted"))
            } else if !["session_meta", "turn_context", "token_usage_record", "world_state"].contains(recordType) {
                transcript.unrecognizedTypes[String(recordType.prefix(100)), default: 0] += 1
            }
        }
        transcript.earlierContentOmitted = start > 0 || entries.count > limit
        transcript.entries = Array(entries.suffix(max(1, limit)))
        return transcript
    }
}
