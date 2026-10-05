import Foundation

/// What an agent has actually done in its current turn, read from its tool calls: the files it
/// edited, the commands it ran and its test runs. Always available, unlike a reported checklist,
/// but it says what was done, not what is left.
public struct TurnWork: Equatable, Sendable {
    public enum Outcome: String, Sendable { case running, passed, failed }
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
    private enum Call: Equatable, Sendable { case command, test(Int) }

    public init() {}
    public var isEmpty: Bool { files.isEmpty && commands == 0 && tests.isEmpty }

    /// A tool call started. `call` pairs it with its result.
    public mutating func started(tool: String, detail: String, call: String?) {
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
    /// A tool call returned, successfully or not.
    public mutating func finished(call: String?, failed: Bool) {
        guard let call, let kind = calls.removeValue(forKey: call) else { return }
        switch kind {
        case .command: if failed { failedCommands += 1 }
        case .test(let index): tests[index].outcome = failed ? .failed : .passed
        }
    }

    /// The current turn's work from an activity stream (oldest first): everything after the last
    /// turn start.
    public static func from(_ events: [ActivityEvent]) -> TurnWork {
        let start = events.lastIndex { $0.kind == "started" || $0.kind == "turnStarted" }.map { $0 + 1 } ?? 0
        var work = TurnWork()
        for event in events[start...] {
            switch event.kind {
            case "toolStarted": work.started(tool: event.tool ?? "", detail: event.detail ?? "", call: event.callID)
            case "toolFinished", "toolFailed": work.finished(call: event.callID, failed: event.kind == "toolFailed")
            default: break
            }
        }
        return work
    }
    /// The current turn's work from tool records (one per call, carrying its latest status).
    public static func from(_ records: [SessionActivityRecord]) -> TurnWork {
        var work = TurnWork()
        for record in records where record.kind == "tool" {
            let detail = record.data["command"].string ?? record.detail
            work.started(tool: record.title, detail: detail, call: record.id)
            switch record.status.lowercased() {
            case "failed", "error", "errored": work.finished(call: record.id, failed: true)
            case "completed", "finished", "done": work.finished(call: record.id, failed: false)
            default: break
            }
        }
        return work
    }
}
