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
        for line in data.split(separator: 10) {
            if Task.isCancelled { break }
            guard let e = try? JSONDecoder().decode(WireValue.self, from: Data(line)) else { continue }
            if session.provider == .claude {
                SessionActivityReducer.ingest(.object(["method": .string("diorama/claudeActivity"), "params": .object(["event": e])]), provider: .claude, sessionID: session.sessionID, into: &state)
            } else {
                let p = e["payload"]
                if p["type"].string == "function_call", p["name"].string == "update_plan",
                   let json = p["arguments"].string, let plan = try? JSONDecoder().decode(WireValue.self, from: Data(json.utf8)) {
                    SessionActivityReducer.ingest(.object(["method": .string("turn/plan/updated"), "params": plan]), provider: .codex, sessionID: session.sessionID, into: &state)
                }
            }
        }
        for index in state.records.indices { state.records[index].source += " · saved history" }
        for index in state.events.indices { state.events[index].source += " · saved history" }
        state.lastKnown = true; state.bound()
        return state
    }
}
