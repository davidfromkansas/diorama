import Foundation

public enum SessionActivityHistory {
    /// A bounded read-only import. Source timestamps are kept; import time is never presented as live execution time.
    @concurrent public static func read(_ session: Session) async -> SessionActivitySnapshot {
        var state = SessionActivitySnapshot()
        guard let url = session.url, let handle = try? FileHandle(forReadingFrom: url) else { return state }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 16 * 1024 * 1024 ? size - 16 * 1024 * 1024 : 0
        try? handle.seek(toOffset: start)
        var data = (try? handle.read(upToCount: 16 * 1024 * 1024)) ?? Data()
        if start > 0, let newline = data.firstIndex(of: 10) { data.removeSubrange(...newline); state.truncated = true }
        append(data, session: session, into: &state)
        return state
    }

    static func append(_ data: Data, session: Session, into state: inout SessionActivitySnapshot) {
        var codexTurn = state.codexTurn
        for line in SessionLibrary.completeLines(data) {
            if Task.isCancelled { break }
            guard let e = try? JSONDecoder().decode(WireValue.self, from: Data(line)) else { continue }
            if session.provider == .claude {
                SessionActivityReducer.ingest(.object(["method": .string("diorama/claudeActivity"), "params": .object(["event": e])]), provider: .claude, sessionID: session.sessionID, into: &state)
            } else {
                let p = e["payload"]
                let type = p["type"].string ?? ""
                codexTurn = p["turn_id"].string ?? codexTurn
                state.codexTurn = codexTurn
                if ["item_started", "item_completed"].contains(type) {
                    let item = CodexOutputEvidence.canonical(p["item"])
                    SessionActivityReducer.ingest(.object(["method": .string(type == "item_started" ? "item/started" : "item/completed"), "params": .object(["item": item, "turnId": codexTurn.map(WireValue.string) ?? .null, "timestamp": e["timestamp"]])]), provider: .codex, sessionID: session.sessionID, into: &state)
                }
                if type == "message", p["role"].string == "assistant" {
                    let text = p["content"].array.compactMap { $0["text"].string }.joined(separator: "\n")
                    // A Markdown checklist in the message is the agent's reported progress.
                    if let plan = MessageChecklist.plan(text) {
                        SessionActivityReducer.ingest(.object(["method": .string("turn/plan/updated"), "params": .object(["plan": plan, "turnId": codexTurn.map(WireValue.string) ?? .null, "timestamp": e["timestamp"]])]), provider: .codex, sessionID: session.sessionID, into: &state)
                    }
                    if let start = text.range(of: "<proposed_plan>"), let end = text.range(of: "</proposed_plan>", range: start.upperBound..<text.endIndex) {
                        let plan = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        SessionActivityReducer.ingest(.object(["method": .string("item/completed"), "params": .object([
                            "turnId": codexTurn.map(WireValue.string) ?? .null, "timestamp": e["timestamp"],
                            "item": .object(["id": p["id"].string.map(WireValue.string) ?? .string("saved-plan:" + (codexTurn ?? e["timestamp"].string ?? "unknown")), "type": .string("plan"), "text": .string(plan)])])]), provider: .codex, sessionID: session.sessionID, into: &state)
                    }
                }
                if type == "token_count" {
                    SessionActivityReducer.ingest(.object(["method": .string("thread/tokenUsage/updated"), "params": .object(["tokenUsage": p["info"], "turnId": codexTurn.map(WireValue.string) ?? .null, "timestamp": e["timestamp"]])]), provider: .codex, sessionID: session.sessionID, into: &state)
                }
                if ["function_call", "custom_tool_call", "function_call_output", "custom_tool_call_output"].contains(type),
                   let call = p["call_id"].string {
                    let finished = type.hasSuffix("_output")
                    let previous = state.records.first { $0.nativeID == call && $0.kind == "tool" && $0.turnID == codexTurn }
                    if previous?.data["nativeItem"].bool == true { continue }
                    let arguments = p["arguments"].string.flatMap { try? JSONDecoder().decode(WireValue.self, from: Data($0.utf8)) } ?? .null
                    let inner = p["input"].string.flatMap(ActivityParser.codeModeCall)
                    state.apply(SessionActivityRecord(id: session.id + ":tool:" + (codexTurn ?? "unknown") + ":" + call, provider: session.provider.rawValue,
                        sessionID: session.sessionID, turnID: codexTurn, nativeID: call, parentID: nil,
                        kind: "tool", title: inner?.tool ?? p["name"].string ?? previous?.title ?? "Tool",
                        status: finished ? "Returned" : "Called",
                        detail: inner?.detail ?? arguments["cmd"].string ?? arguments["command"].string ?? previous?.detail ?? "",
                        source: "Codex transcript", recordedAt: ActivityParser.date(e["timestamp"].string), observedAt: Date(), data: .null))
                }
                if p["type"].string == "function_call", p["name"].string == "update_plan",
                   let json = p["arguments"].string, let plan = try? JSONDecoder().decode(WireValue.self, from: Data(json.utf8)) {
                    SessionActivityReducer.ingest(.object(["method": .string("turn/plan/updated"), "params": .object(plan.object.merging(["turnId": codexTurn.map(WireValue.string) ?? .null, "timestamp": e["timestamp"]]) { _, new in new })]), provider: .codex, sessionID: session.sessionID, into: &state)
                }
            }
        }
        for index in state.records.indices { state.records[index].source = state.records[index].source.replacingOccurrences(of: " · saved history", with: "") + " · saved history" }
        for index in state.events.indices { state.events[index].source = state.events[index].source.replacingOccurrences(of: " · saved history", with: "") + " · saved history" }
        state.lastKnown = true; state.bound()
    }
}
