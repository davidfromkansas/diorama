import Foundation

/// One line of an agent's distilled activity: what it did, in a few words, and how it went.
public struct FeedEntry: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case started, finished, failed, interrupted, research, planning, editing, command, test, resource, tool }
    public enum Outcome: String, Sendable { case running, done, failed }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var outcome: Outcome?
    public var time: Date?
    public var duration: TimeInterval?
    public init(id: String, kind: Kind, title: String, detail: String = "", outcome: Outcome? = nil, time: Date? = nil, duration: TimeInterval? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.outcome = outcome; self.time = time; self.duration = duration
    }
}

/// Turns an agent's tool calls into a short activity feed (oldest first): turn markers, merged
/// runs of reading, edits by file, commands and tests with their outcome. Codex's double reports
/// of one call (the model's call and the item that ran it) count once, as in `TurnWork`.
public enum AgentActivityFeed {
    public static let limit = 200
    static let plumbing: Set<String> = ["js", "js_reset", "wait", "sleep", "exec"]

    /// From an activity stream (oldest first).
    public static func entries(from events: [ActivityEvent]) -> [FeedEntry] {
        var builder = Builder()
        // Codex reports a shell call twice within a turn when its native item is known.
        var native = false
        for (index, event) in events.enumerated() {
            switch event.kind {
            case "started", "turnStarted":
                native = events[(index + 1)...].prefix { !["started", "turnStarted"].contains($0.kind) }
                    .contains { $0.kind == "toolStarted" && $0.tool?.lowercased() == "commandexecution" }
                builder.marker(.started, id: event.id, time: event.time)
            case "finished": builder.marker(.finished, id: event.id, time: event.time)
            case "interrupted": builder.marker(.interrupted, id: event.id, time: event.time)
            case "failed": builder.marker(.failed, id: event.id, time: event.time)
            case "toolStarted":
                let tool = event.tool ?? ""
                if native && tool.lowercased() != "commandexecution" && KitchenActivity.commandTools.contains(tool.lowercased()) { continue }
                builder.started(id: event.id, tool: tool, detail: event.detail ?? "", call: event.callID, time: event.time)
            case "toolFinished", "toolFailed":
                builder.finished(call: event.callID, failed: event.kind == "toolFailed", result: event.detail ?? "", time: event.time)
            default: break
            }
        }
        return builder.result
    }

    /// From activity records: one per call revision (the latest stands), plus turn records.
    public static func entries(from records: [SessionActivityRecord]) -> [FeedEntry] {
        var order: [String] = [], latest: [String: SessionActivityRecord] = [:]
        for record in records where record.kind == "tool" || record.kind == "turn" {
            let key = record.kind + ":" + (record.nativeID.isEmpty ? record.id : record.nativeID)
            if latest[key] == nil { order.append(key) }
            latest[key] = record
        }
        let items = order.compactMap { latest[$0] }
        let native = items.contains { $0.data["nativeItem"].bool }
        let shellOrPatch = KitchenActivity.commandTools.union(KitchenActivity.editingTools)
        var builder = Builder()
        for record in items {
            let time = record.recordedAt ?? record.observedAt
            if record.kind == "turn" {
                builder.marker(.started, id: record.id, time: time)
                switch record.status.lowercased() {
                case "completed": builder.marker(.finished, id: record.id + ":end", time: time)
                case "failed": builder.marker(.failed, id: record.id + ":end", time: time)
                case "interrupted": builder.marker(.interrupted, id: record.id + ":end", time: time)
                default: break
                }
                continue
            }
            if native && !record.data["nativeItem"].bool && shellOrPatch.contains(record.title.lowercased()) { continue }
            let files = record.data["files"].array.compactMap { $0["path"].string }
            let detail = files.isEmpty ? record.data["command"].string ?? record.detail : files.joined(separator: "\n")
            builder.started(id: record.id, tool: record.title, detail: detail, call: record.id, time: time)
            let failedExit: Bool = { if case .number(let code) = record.data["exitCode"] { return code != 0 }; return false }()
            let duration = record.data["durationMs"].number.map { $0 / 1000 }
            switch record.status.lowercased() {
            case "failed", "error", "errored": builder.finished(call: record.id, failed: true, duration: duration)
            case "completed", "finished", "done", "returned": builder.finished(call: record.id, failed: failedExit, duration: duration)
            default: break
            }
        }
        return builder.result
    }

    private struct Builder {
        var result: [FeedEntry] = []
        /// Open calls by id, pointing at their entry; commands still running in a shell session.
        var open: [String: Int] = [:]
        var sessions: [String: Int] = [:]
        /// Polls by call, with the session each reads ("" when unnamed).
        var polls: [String: String] = [:]

        mutating func marker(_ kind: FeedEntry.Kind, id: String, time: Date?) {
            let title: String
            switch kind {
            case .started: title = "Started a turn"
            case .finished: title = "Turn finished"
            case .failed: title = "Turn failed"
            default: title = "Turn interrupted"
            }
            // A stream can repeat a marker; one per turn edge is enough.
            if result.last?.kind == kind { return }
            append(FeedEntry(id: id, kind: kind, title: title, outcome: kind == .failed ? .failed : nil, time: time))
            // Calls still open when a turn ends never reported back.
            if kind != .started { open.removeAll(); sessions.removeAll() }
        }

        mutating func started(id: String, tool: String, detail: String, call: String?, time: Date?) {
            if tool.lowercased() == "write_stdin" { if let call { polls[call] = TurnWork.session(detail) ?? "" }; return }
            // Codex code mode's own plumbing (its script runner and waits) is not the agent's work.
            if AgentActivityFeed.plumbing.contains(tool.lowercased()) { return }
            let written = KitchenActivity.commandTools.contains(tool.lowercased()) ? KitchenActivity.writtenFiles(command: detail) : []
            let alsoTests = !written.isEmpty && KitchenActivity.classify(tool: tool, detail: detail) == .testing
            if KitchenActivity.isEditing(tool: tool) || !written.isEmpty {
                let files = (written.isEmpty ? detail.split(whereSeparator: \.isNewline).map(String.init) : written).map { Self.name($0) }.filter { !$0.isEmpty }
                // Consecutive edits of the same files read as one step.
                if let last = result.last, last.kind == .editing, last.detail == files.joined(separator: "\n") { return }
                append(FeedEntry(id: id, kind: .editing, title: "Edited " + Self.list(files.isEmpty ? ["a file"] : files), detail: files.joined(separator: "\n"), outcome: .done, time: time))
                // A command that writes a file and then runs the tests shows both.
                guard alsoTests else { return }
                let script = KitchenActivity.withoutHeredocs(KitchenActivity.shellScript(detail))
                let line = script.split(whereSeparator: \.isNewline).last.map(String.init) ?? script
                append(FeedEntry(id: id + ":test", kind: .test, title: "Tested · " + (line.count > 60 ? String(line.prefix(59)) + "…" : line), detail: script, outcome: .running, time: time))
                if let call { open[call] = result.count - 1 }
                return
            }
            let activity = KitchenActivity.classify(tool: tool, detail: detail)
            switch activity {
            case .researching:
                let item = Self.subject(tool: tool, detail: detail)
                // Runs of reading and searching merge into one line.
                if let index = result.indices.last, result[index].kind == .research {
                    var items = result[index].detail.split(separator: "\n").map(String.init)
                    if !items.contains(item) { items.append(item) }
                    result[index].detail = items.joined(separator: "\n")
                    result[index].title = "Looked at " + Self.list(items)
                    return
                }
                append(FeedEntry(id: id, kind: .research, title: "Looked at " + item, detail: item, outcome: .done, time: time))
            case .checking:
                let what = detail.isEmpty ? Self.toolName(tool) : String(detail.prefix(60))
                if let last = result.last, last.kind == .test, last.detail == what { return }
                append(FeedEntry(id: id, kind: .test, title: "Checked · " + what, detail: what, time: time))
            case .resources:
                let item = Self.resourceName(tool: tool, detail: detail)
                if let last = result.last, last.kind == .resource, last.detail == item { return }
                append(FeedEntry(id: id, kind: .resource, title: "Fetched " + item, detail: item, outcome: .done, time: time))
            case .planning:
                if result.last?.kind == .planning { return }
                append(FeedEntry(id: id, kind: .planning, title: "Updated the plan", outcome: .done, time: time))
            case .testing, .commands:
                let script = KitchenActivity.shellScript(detail)
                let line = script.split(whereSeparator: \.isNewline).first.map(String.init) ?? script
                let short = line.count > 60 ? String(line.prefix(59)) + "…" : line
                append(FeedEntry(id: id, kind: activity == .testing ? .test : .command, title: (activity == .testing ? "Tested · " : "Ran ") + short,
                                 detail: script, outcome: .running, time: time))
                if let call { open[call] = result.count - 1 }
            default:
                let name = Self.toolName(tool)
                if let last = result.last, last.kind == .tool, last.title == "Used " + name { return }
                append(FeedEntry(id: id, kind: .tool, title: "Used " + name, detail: detail, outcome: .done, time: time))
            }
        }

        mutating func finished(call: String?, failed: Bool, result output: String = "", time: Date? = nil, duration: TimeInterval? = nil) {
            guard let call else { return }
            let fields = Dictionary(output.split(separator: " ").compactMap { field -> (String, String)? in
                let parts = field.split(separator: "=", maxSplits: 1); return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
            }, uniquingKeysWith: { $1 })
            var index: Int?
            if let polled = polls.removeValue(forKey: call) {
                // A poll that reports an exit settles the command running in its session.
                guard let session = fields["session"] ?? (polled.isEmpty ? nil : polled), fields["exit"] != nil else { return }
                index = sessions.removeValue(forKey: session)
            } else if let opened = open.removeValue(forKey: call) {
                if let session = fields["session"], fields["exit"] == nil { sessions[session] = opened; return }
                index = opened
            }
            guard let index, result.indices.contains(index) else { return }
            result[index].outcome = failed ? .failed : .done
            if let duration { result[index].duration = duration }
            else if let time, let start = result[index].time { result[index].duration = max(0, time.timeIntervalSince(start)) }
        }

        mutating func append(_ entry: FeedEntry) {
            result.append(entry)
            if result.count > AgentActivityFeed.limit {
                let drop = result.count - AgentActivityFeed.limit
                result.removeFirst(drop)
                open = open.compactMapValues { $0 >= drop ? $0 - drop : nil }
                sessions = sessions.compactMapValues { $0 >= drop ? $0 - drop : nil }
            }
        }

        static func name(_ path: String) -> String {
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            return (trimmed as NSString).lastPathComponent
        }
        /// What a read or search looked at: a file name, or the command in short.
        static func subject(tool: String, detail: String) -> String {
            let lower = tool.lowercased()
            if ["read", "view_image", "imageview"].contains(lower), !detail.isEmpty { return name(detail) }
            if KitchenActivity.commandTools.contains(lower) {
                let script = KitchenActivity.shellScript(detail)
                let words = KitchenActivity.commandWords(script).first?.map { Substring($0) } ?? script.split(separator: " ")
                // Listing the tree reads as browsing the project; `pwd` says nothing.
                if let first = words.first, ["ls", "find", "fd", "tree", "pwd"].contains(String(first)) || (first == "rg" && words.contains("--files")) {
                    return "project files"
                }
                // `cat README.md` reads as the file it shows.
                if let first = words.first, ["cat", "head", "tail", "less", "more", "nl"].contains(String(first)), let file = words.last(where: { !$0.hasPrefix("-") && $0 != first }) {
                    return name(String(file))
                }
                let line = script.split(whereSeparator: \.isNewline).first.map(String.init) ?? script
                return line.count > 40 ? String(line.prefix(39)) + "…" : line
            }
            if lower.contains("search") || lower.contains("fetch") { return detail.isEmpty ? "the web" : String(detail.prefix(40)) }
            return detail.isEmpty ? toolName(tool) : name(detail)
        }
        /// A skill by name, or an MCP server's tool as "server tool".
        static func resourceName(tool: String, detail: String) -> String {
            if tool.lowercased() == "skill" { return detail.isEmpty ? "a skill" : detail }
            if let skill = KitchenActivity.skillName(detail) { return "the " + skill + " skill" }
            if tool.lowercased() == "computer_use" { return "Computer Use · " + (detail.isEmpty ? "browser" : detail) }
            return toolName(tool)
        }
        static func toolName(_ tool: String) -> String {
            // `mcp__server__tool` reads as "server tool".
            if tool.hasPrefix("mcp__") { return tool.dropFirst(5).replacingOccurrences(of: "__", with: " ").replacingOccurrences(of: "_", with: " ") }
            return tool.isEmpty ? "a tool" : tool
        }
        static func list(_ items: [String]) -> String {
            items.count <= 2 ? items.joined(separator: ", ") : items.prefix(2).joined(separator: ", ") + " +\(items.count - 2)"
        }
    }
}
