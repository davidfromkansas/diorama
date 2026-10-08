import Foundation

/// What an agent has actually done in its current turn, read from its tool calls: the files it
/// edited, the commands it ran and its test runs. Always available, unlike a reported checklist,
/// but it says what was done, not what is left.
public struct TurnWork: Equatable, Sendable {
    public enum Outcome: String, Sendable { case running, passed, failed, unknown }
    public struct TestRun: Equatable, Sendable {
        public var command: String
        public var outcome: Outcome
    }
    /// Edited files in first-edit order, without repeats.
    public private(set) var files: [String] = []
    /// Commands that may change something (builds, installs, scripts); read-only lookups and tests
    /// are not counted.
    public private(set) var commands = 0
    public private(set) var failedCommands = 0
    public private(set) var tests: [TestRun] = []
    /// Skills, plugins and MCP tools used (fetched from the pantry), in order.
    public private(set) var resources: [String] = []
    private var calls: [String: Call] = [:]
    /// Commands still running in a shell session, resolved by a later poll of that session.
    private var sessions: [String: Call] = [:]
    private enum Call: Equatable, Sendable { case command, test(Int), poll }
    /// The session each poll reads, when its call named it.
    private var polled: [String: String] = [:]
    static func session(_ detail: String) -> String? {
        detail.split(separator: " ").first { $0.hasPrefix("session=") }.map { String($0.dropFirst(8)) }
    }

    public init() {}
    public var isEmpty: Bool { files.isEmpty && commands == 0 && tests.isEmpty }

    /// A tool call started. `call` pairs it with its result.
    public mutating func started(tool: String, detail: String, call: String?) {
        // Polling a running command's session is not a new command.
        if tool.lowercased() == "write_stdin" { if let call { calls[call] = .poll; polled[call] = Self.session(detail) }; return }
        let written = KitchenActivity.commandTools.contains(tool.lowercased()) ? KitchenActivity.writtenFiles(command: detail) : []
        // A shell write is an edit of the files it writes; the same command may also build or test.
        for path in written { addFile(path) }
        if !written.isEmpty, KitchenActivity.classify(tool: tool, detail: detail) != .testing {
            if let call { calls[call] = .command }
            commands += 1
            return
        }
        if KitchenActivity.isEditing(tool: tool) {
            for path in detail.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) where !path.isEmpty { addFile(path) }
            return
        }
        switch KitchenActivity.classify(tool: tool, detail: detail) {
        case .testing:
            tests.append(TestRun(command: KitchenActivity.shellScript(detail), outcome: .running))
            if let call { calls[call] = .test(tests.count - 1) }
        case .commands:
            commands += 1
            if let call { calls[call] = .command }
        case .resources:
            // A skill fetched by MCP resource keeps its URI, which names the skill (and its plugin).
            // Claude's Skill tool names its skill in the detail ("vercel:vercel-cli").
            let skill = tool.lowercased() == "skill" ? detail.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            resources.append(KitchenActivity.pluginSkillName(detail) ?? KitchenActivity.skillName(detail) ?? (detail.hasPrefix("skill://") ? detail : skill.isEmpty ? tool : skill))
        default: break
        }
    }
    /// A tool call returned, successfully or not. `result` is the parser's `exit=N session=S`
    /// detail when the output reported them.
    public mutating func finished(call: String?, failed: Bool, result: String = "") {
        guard let call, let kind = calls.removeValue(forKey: call) else { return }
        let fields = Dictionary(result.split(separator: " ").compactMap { field -> (String, String)? in
            let parts = field.split(separator: "=", maxSplits: 1); return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }, uniquingKeysWith: { $1 })
        var target = kind
        if case .poll = kind {
            // A poll that reports an exit settles the command running in its session.
            guard let session = fields["session"] ?? polled.removeValue(forKey: call), fields["exit"] != nil, let running = sessions.removeValue(forKey: session) else { return }
            target = running
        } else if let session = fields["session"], fields["exit"] == nil {
            sessions[session] = kind; return
        }
        switch target {
        case .command: if failed { failedCommands += 1 }
        case .test(let index): tests[index].outcome = failed ? .failed : .passed
        case .poll: break
        }
    }
    /// One entry per file, whether it was named relative to the project or by its full path.
    private mutating func addFile(_ path: String) {
        if files.contains(where: { $0 == path || $0.hasSuffix("/" + path) }) { return }
        if let index = files.firstIndex(where: { path.hasSuffix("/" + $0) }) { files[index] = path; return }
        files.append(path)
    }
    /// The turn is over: tests whose result never arrived are unknown rather than running.
    public mutating func settle() {
        for index in tests.indices where tests[index].outcome == .running { tests[index].outcome = .unknown }
    }

    /// The current turn's work from an activity stream (oldest first): everything after the last
    /// turn start.
    /// Codex streams can report a shell call twice, as the model's call (`exec_command`…) and as
    /// the item that ran it (`commandExecution`); then only the item counts.
    public static func from(_ events: [ActivityEvent]) -> TurnWork {
        let start = events.lastIndex { $0.kind == "started" || $0.kind == "turnStarted" }.map { $0 + 1 } ?? 0
        let turn = events[start...]
        let native = turn.contains { $0.kind == "toolStarted" && $0.tool?.lowercased() == "commandexecution" }
        var work = TurnWork()
        for event in turn {
            switch event.kind {
            case "toolStarted":
                let tool = event.tool ?? ""
                if native && tool.lowercased() != "commandexecution" && KitchenActivity.commandTools.contains(tool.lowercased()) { continue }
                work.started(tool: tool, detail: event.detail ?? "", call: event.callID)
            case "toolFinished", "toolFailed": work.finished(call: event.callID, failed: event.kind == "toolFailed", result: event.detail ?? "")
            case "finished", "interrupted", "failed": work.settle()
            default: break
            }
        }
        return work
    }
    /// The current turn's work from tool records (one per call, carrying its latest status).
    /// Codex history records each call twice: the model's tool call and the native item that ran
    /// (`commandExecution`, `fileChange`) with its exit code and files. When native items exist,
    /// only they count.
    /// Event lists hold one revision per update of a call (running, then completed); the latest
    /// revision of each call stands, in the order calls first appeared.
    public static func from(_ records: [SessionActivityRecord]) -> TurnWork {
        var order: [String] = [], latest: [String: SessionActivityRecord] = [:]
        for record in records where record.kind == "tool" {
            let key = record.nativeID.isEmpty ? record.id : record.nativeID
            if latest[key] == nil { order.append(key) }
            latest[key] = record
        }
        let tools = order.compactMap { latest[$0] }
        let native = tools.contains { $0.data["nativeItem"].bool }
        let shellOrPatch = KitchenActivity.commandTools.union(KitchenActivity.editingTools)
        var work = TurnWork()
        for record in tools {
            if native && !record.data["nativeItem"].bool && shellOrPatch.contains(record.title.lowercased()) { continue }
            let files = record.data["files"].array.compactMap { $0["path"].string }
            let detail = files.isEmpty ? record.data["command"].string ?? record.detail : files.joined(separator: "\n")
            work.started(tool: record.title, detail: detail, call: record.id)
            let exitFailed: Bool = { if case .number(let code) = record.data["exitCode"] { return code != 0 }; return false }()
            switch record.status.lowercased() {
            case "failed", "error", "errored": work.finished(call: record.id, failed: true)
            case "completed", "finished", "done": work.finished(call: record.id, failed: exitFailed)
            default: break // Still running, or returned without an outcome.
            }
        }
        return work
    }
}
