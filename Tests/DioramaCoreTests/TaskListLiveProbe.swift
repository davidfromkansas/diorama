import Foundation
import Testing
@testable import DioramaCore

/// Opt-in, real agents: does the standing task-list instruction make agents keep a plan without
/// being asked, does it follow feedback, and what does it cost? Runs each kitchen-demo task with
/// the instruction on and off, on Claude and Codex, in throwaway copies of the demo project.
///
///     DIORAMA_TASKLIST_PROBE=1 swift test --filter TaskListLiveProbe
///
/// Results go to $DIORAMA_TASKLIST_OUT (default /tmp/diorama-tasklist-probe.jsonl).
@MainActor struct TaskListLiveProbe {
    static let prompts = [
        "t1": "Add a negate(n) function to math.js, export it, add a test for it in test.js, and run npm test.",
        "t5": "Build a small command-line calculator for this project: add cli.js that supports add, subtract, multiply, mean and median subcommands with argument validation and helpful error messages; add mean and median to math.js; add tests for every subcommand and for the error cases; document usage in README.md; include cli.js in the build output in build.js; and make sure npm test and npm run build both pass.",
        "t6": "Build a website that shows a three.js model of Salesforce Tower in San Francisco where the sun rises and sets in real time.",
        "t3": "Refactor this project: split math.js into src/arithmetic.js (add, subtract, multiply) and src/stats.js (add sum and average helpers), keep math.js as a thin re-export so existing imports keep working, update build.js so the build still works, add tests for the new helpers, and make sure npm test and npm run build both pass.",
    ]
    static let feedback = "Feedback: also add a mode(list) helper to src/stats.js with a test, and rename average to mean everywhere. Make sure npm test still passes."
    static let planTools: Set<String> = ["taskcreate", "taskupdate", "todowrite", "update_plan"]

    struct Run { let provider: Provider; let task: String; let on: Bool; var id = ""; var folder = "" }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_TASKLIST_PROBE"] == "1"))
    func taskListsFollowTheInstruction() async throws {
        let demo = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Diorama/kitchen-demo")
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DIORAMA_TASKLIST_OUT"] ?? "/tmp/diorama-tasklist-probe.jsonl")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-tasklist-" + UUID().uuidString).resolvingSymlinksInPath()
        let transport = AgentExecutionTransport()
        let c = ExecutionController(transport: transport)
        await c.connect(); await c.refreshModels(); await c.loadModes()
        let wanted = ProcessInfo.processInfo.environment["DIORAMA_TASKLIST_CLAUDE_MODEL"] ?? "sonnet"
        let claudeModel = c.models.first { $0.id.hasPrefix("claude/") && $0.id.contains(wanted) }?.id ?? c.models.first { $0.id.hasPrefix("claude/") && $0.id.contains("sonnet") }?.id ?? c.models.first { $0.id.hasPrefix("claude/") }?.id
        var runs: [Run] = []
        let env = ProcessInfo.processInfo.environment
        let providers = (env["DIORAMA_TASKLIST_PROVIDERS"] ?? "claude,codex").split(separator: ",").map { $0 == "claude" ? Provider.claude : .codex }
        let tasks = (env["DIORAMA_TASKLIST_TASKS"] ?? "t1,t3").split(separator: ",").map(String.init)
        for provider in providers where provider == .codex || claudeModel != nil {
            for task in tasks { for on in [true, false] { runs.append(Run(provider: provider, task: task, on: on)) } }
        }
        // Prepared one at a time: the instruction is read from the setting when the thread starts.
        for index in runs.indices {
            let folder = root.appendingPathComponent("\(runs[index].provider == .claude ? "claude" : "codex")-\(runs[index].task)-\(runs[index].on ? "on" : "off")")
            try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: demo, to: folder)
            UserDefaults.standard.set(runs[index].on, forKey: AgentInstructions.liveTaskListKey)
            runs[index].folder = folder.path
            runs[index].id = try await c.prepare(folder: folder.path, title: "Task list probe \(runs[index].task)", model: runs[index].provider == .claude ? claudeModel! : "", permission: .fullAccess)
        }
        UserDefaults.standard.removeObject(forKey: AgentInstructions.liveTaskListKey)
        func finish(_ id: String, timeout: TimeInterval) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while ![.finished, .failed, .interrupted].contains(c.tasks[id]?.phase ?? .ready) {
                guard Date() < deadline else { throw AppServerFailure("Timed out: \(id)") }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        func report(_ run: Run, turn: String, started: Date) throws {
            let task = c.tasks[run.id]
            let activity = task?.activity ?? []
            let turnStart = activity.lastIndex { $0.kind == "started" || $0.kind == "turnStarted" }.map { $0 + 1 } ?? 0
            let tools = activity[turnStart...].filter { $0.kind == "toolStarted" }.compactMap(\.tool)
            let plan = AgentPlan.reported(in: task?.structuredActivity ?? .init(), provider: run.provider.rawValue, sessionID: run.id)
            let row: [String: Any] = [
                "provider": run.provider.rawValue, "task": run.task, "instruction": run.on, "turn": turn,
                "seconds": Int(Date().timeIntervalSince(started)), "model": c.tasks[run.id]?.model ?? "", "phase": task?.phase.rawValue ?? "?",
                "tools": tools.count, "planTools": tools.filter { Self.planTools.contains($0.lowercased()) }.count,
                "plan": plan.checklist.map { "\($0.status): \($0.title)" }, "earlier": plan.earlier.count,
                "previousTurn": plan.tasksPreviousTurn, "folder": run.folder,
            ]
            let line = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            let handle = try? FileHandle(forWritingTo: out)
            if let handle { handle.seekToEndOfFile(); handle.write(line + Data("\n".utf8)); try handle.close() }
            else { try (line + Data("\n".utf8)).write(to: out) }
        }
        let jobs = runs.map { run in
            Task { @MainActor in
                let started = Date()
                try await c.sendWithGoal(id: run.id, prompt: Self.prompts[run.task]!, goal: false)
                try await finish(run.id, timeout: 2400)
                try report(run, turn: "first", started: started)
                // Feedback after the work is served: the list should follow the new goal.
                if run.task == "t3", run.on {
                    let again = Date()
                    try await c.sendWithGoal(id: run.id, prompt: Self.feedback, goal: false)
                    try await Task.sleep(for: .seconds(1))
                    try await finish(run.id, timeout: 900)
                    try report(run, turn: "feedback", started: again)
                }
            }
        }
        for job in jobs { try await job.value }
        await transport.shutdown()
    }
}
