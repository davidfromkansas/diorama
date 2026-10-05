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
    private var calls: [String: Call] = [:]
    /// Commands still running in a shell session, resolved by a later poll of that session.
    private var sessions: [String: Call] = [:]
    private enum Call: Equatable, Sendable { case command, test(Int), poll }

    public init() {}
    public var isEmpty: Bool { files.isEmpty && commands == 0 && tests.isEmpty }

    /// A tool call started. `call` pairs it with its result.
    public mutating func started(tool: String, detail: String, call: String?) {
        // Polling a running command's session is not a new command.
        if tool.lowercased() == "write_stdin" { if let call { calls[call] = .poll }; return }
        if KitchenActivity.isEditing(tool: tool) {
            for path in detail.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) where !path.isEmpty && !files.contains(path) {
                files.append(path)
            }
            return
        }
        switch KitchenActivity.classify(tool: tool, detail: detail) {
        case .testing:
            tests.append(TestRun(command: KitchenActivity.shellScript(detail), outcome: .running))
            if let call { calls[call] = .test(tests.count - 1) }
        case .commands:
            commands += 1
            if let call { calls[call] = .command }
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
            guard let session = fields["session"], fields["exit"] != nil, let running = sessions.removeValue(forKey: session) else { return }
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
    public static func from(_ records: [SessionActivityRecord]) -> TurnWork {
        let tools = records.filter { $0.kind == "tool" }
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
