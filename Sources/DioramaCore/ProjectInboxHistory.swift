import Foundation
import CryptoKit

/// Uses native completion evidence. Silence, tool returns and elapsed time are never completion.
public enum ProjectInboxHistory {
    public struct Result: Sendable { public var updates: [InboxUpdate]; public var notice: String? }
    public static func parse(_ data: Data, session: Session) -> Result {
        var buffer = Data(), turn: String?, lastAssistant: String?, updates: [InboxUpdate] = []
        var uncertain = false
        func finish(_ outcome: String, stamp: String?, fallback: String? = nil) {
            guard let identity = session.provider == .codex ? turn : lastAssistant else { uncertain = true; return }
            var transcript = SessionLibrary.parseTranscript(data: buffer, provider: session.provider, limit: 5000, scope: session.id)
            if let fallback, !fallback.isEmpty, !transcript.entries.contains(where: { $0.kind == "Assistant" }) {
                transcript.entries.append(Entry(id: identity + ":final", kind: "Assistant", text: fallback, timestamp: stamp))
            }
            if let update = InboxUpdate.make(session: session, turn: identity, entries: transcript.entries,
                                            outcome: outcome, date: ActivityParser.date(stamp)) {
                if let i = updates.firstIndex(where: { $0.id == update.id }) { updates[i] = update } else { updates.append(update) }
            }
        }
        for line in SessionLibrary.completeLines(data) {
            if Task.isCancelled { break }
            guard let row = try? JSONDecoder().decode(WireValue.self, from: Data(line)) else { continue }
            if session.provider == .codex {
                let p = row["payload"], type = p["type"].string ?? ""
                if let id = p["turn_id"].string, id != turn { turn = id; buffer.removeAll(keepingCapacity: true) }
                buffer.append(contentsOf: line); buffer.append(10)
                if type == "task_complete" { finish("completed", stamp: row["timestamp"].string, fallback: p["last_agent_message"].string) }
                if type == "turn_aborted" { finish("interrupted", stamp: row["timestamp"].string) }
            } else {
                guard row["parent_tool_use_id"].string == nil, !row["isSidechain"].bool else { continue }
                let type = row["type"].string
                if type == "user", !row["isMeta"].bool,
                   !row["message"]["content"].array.contains(where: { $0["type"].string == "tool_result" }) {
                    buffer.removeAll(keepingCapacity: true); lastAssistant = nil
                }
                if type == "assistant" { lastAssistant = row["message"]["id"].string ?? row["uuid"].string ?? lastAssistant }
                buffer.append(contentsOf: line); buffer.append(10)
                if type == "assistant", ["end_turn", "stop_sequence"].contains(row["message"]["stop_reason"].string ?? "") {
                    finish("completed", stamp: row["timestamp"].string)
                }
                if type == "result" { finish(row["is_error"].bool ? "failed" : "completed", stamp: row["timestamp"].string, fallback: row["result"].string) }
            }
        }
        return Result(updates: updates, notice: uncertain ? "Some history has no reliable turn identity." : nil)
    }
    @concurrent public static func read(_ session: Session) async -> Result {
        guard let url = session.url else { return Result(updates: [], notice: "History unavailable for some conversations.") }
        do {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let size = try handle.seekToEnd(), bound: UInt64 = 16 * 1024 * 1024
            let start = size > bound ? size - bound : 0
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: Int(bound)) ?? Data()
            if start > 0, let newline = data.firstIndex(of: 10) { data.removeSubrange(...newline) }
            var result = parse(data, session: session)
            if start > 0 { result.notice = "Partial history · older source content is outside the discovery window." }
            return result
        } catch { return Result(updates: [], notice: "History unavailable · " + error.localizedDescription) }
    }
}

/// Cache completion fingerprints so streaming file notifications do not repeatedly
/// normalize an entire saved conversation before a new terminal record arrives.
public actor ProjectInboxHistoryReader {
    private struct Fingerprint { var size: Int; var terminal: String; var notice: String? = nil }
    private var fingerprints: [String: Fingerprint] = [:]
    public init() {}
    public func read(_ session: Session, identity: String? = nil) async -> ProjectInboxHistory.Result {
        guard let url = session.url else { return .init(updates: [], notice: "History unavailable for some conversations.") }
        do {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: size > 512 * 1024 ? size - 512 * 1024 : 0)
            var tail = try handle.read(upToCount: 512 * 1024) ?? Data()
            if size > 512 * 1024, let newline = tail.firstIndex(of: 10) { tail.removeSubrange(...newline) }
            let terminal = SessionLibrary.completeLines(tail).reversed().first { line in
                guard let row = try? JSONDecoder().decode(WireValue.self, from: Data(line)) else { return false }
                if session.provider == .codex { return ["task_complete", "turn_aborted"].contains(row["payload"]["type"].string ?? "") }
                return row["type"].string == "result" || ["end_turn", "stop_sequence"].contains(row["message"]["stop_reason"].string ?? "")
            }.map { SHA256.hash(data: Data($0)).description } ?? ""
            if let old = fingerprints[identity ?? url.path], old.size <= size, old.terminal == terminal {
                fingerprints[identity ?? url.path] = Fingerprint(size: Int(size), terminal: terminal, notice: old.notice)
                return .init(updates: [], notice: old.notice)
            }
            let result = await ProjectInboxHistory.read(session)
            fingerprints[identity ?? url.path] = Fingerprint(size: Int(size), terminal: terminal, notice: result.notice)
            return result
        } catch { return .init(updates: [], notice: "History unavailable · " + error.localizedDescription) }
    }
}
