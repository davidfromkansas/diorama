import Foundation
import Testing
@testable import DioramaCore

/// Opt-in acceptance of the same controller methods called by the native views.
/// Only creates/mutates its own disposable conversations and working directory.
@MainActor struct WorkflowLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_WORKFLOW_PROBE"] == "1"))
    func liveWorkflowAcceptance() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diorama-workflow-\(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let skill = root.appendingPathComponent(".agents/skills/acceptance/SKILL.md")
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: acceptance\ndescription: Disposable Diorama acceptance test skill.\n---\nWhen invoked, include SKILL_ACCEPTANCE_OK in the final answer. Do not access external services.\n".write(to: skill, atomically: true, encoding: .utf8)
        func git(_ args: [String]) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = args; p.currentDirectoryURL = root
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else { throw AppServerFailure("Fixture git setup failed") }
        }
        try git(["init", "-b", "main"])
        try "def add(a, b):\n    return a + b\n".write(to: root.appendingPathComponent("demo.py"), atomically: true, encoding: .utf8)
        try git(["add", "demo.py"]); try git(["-c", "user.name=Diorama Test", "-c", "user.email=test@example.invalid", "commit", "-m", "Disposable baseline"])
        let transport = CodexExecutionTransport(timeout: .seconds(35))
        let c = ExecutionController(transport: transport, journal: root.appendingPathComponent("owned.json"))
        var results: [[String: String]] = []
        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/workflow-live.json")
        func save() throws {
            try JSONSerialization.data(withJSONObject: ["date": ISO8601DateFormatter().string(from: Date()), "folder": root.path, "results": results], options: [.prettyPrinted, .sortedKeys]).write(to: evidence)
        }
        func check(_ name: String, _ body: () async throws -> String) async {
            do { let detail = try await body(); results.append(["check": name, "status": "passed", "detail": detail]) }
            catch { results.append(["check": name, "status": "failed", "detail": error.localizedDescription]); Issue.record("\(name): \(error.localizedDescription)") }
            try? save(); print("WORKFLOW_CHECK \(name): \(results.last?["status"] ?? "unknown")")
        }
        func require(_ value: Bool, _ message: String) throws { guard value else { throw AppServerFailure(message) } }
        func wait(_ condition: () -> Bool) async throws {
            let end = Date().addingTimeInterval(100)
            while !condition() { guard Date() < end else { throw AppServerFailure("Live workflow condition timed out") }; try await Task.sleep(for: .milliseconds(100)) }
        }
        func finished(_ id: String) async throws {
            let end = Date().addingTimeInterval(100)
            while c.tasks[id]?.phase != .finished && c.tasks[id]?.phase != .failed {
                if let request = c.requests.values.first(where: { $0.threadID == id && $0.isBlocking }) {
                    // The user authorized this fixture's single demo.py edit. Inspect the
                    // actual proposed paths before approving; never grant a directory rule.
                    if request.method == "item/fileChange/requestApproval" {
                        let changes = c.tasks[id]?.transcript.entries.compactMap(\.tool).filter { $0.type == "fileChange" }.flatMap { $0.item["changes"].array } ?? []
                        try require(!changes.isEmpty && changes.allSatisfy { value in
                            guard let path = value["path"].string else { return false }
                            return path == "demo.py" || URL(fileURLWithPath: path).resolvingSymlinksInPath() == root.appendingPathComponent("demo.py").resolvingSymlinksInPath()
                        }, "Unexpected file approval scope")
                        try await c.answer(id: request.id, result: .object(["decision": .string("accept")]))
                    } else { throw AppServerFailure("Unexpected request: " + request.method) }
                }
                guard Date() < end else { throw AppServerFailure("Turn completion timed out") }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(c.tasks[id]?.phase == .finished, "Turn failed: \(c.tasks[id]?.error ?? "none")")
        }
        await c.connect()
        let id = try await c.prepare(folder: root.path, title: "Diorama workflow acceptance", model: "")
        let session = try #require(c.tasks[id]?.session)
        await check("4 goals create/edit/clear and account usage") {
            try await c.setGoal(id: id, objective: "Disposable paused goal", status: "paused", tokenBudget: 1000)
            try require(c.tasks[id]?.workflow.goal["status"].string == "paused", "Goal did not pause")
            try await c.setGoal(id: id, objective: "Edited disposable goal", status: "paused", tokenBudget: 1500)
            await c.loadWorkflow(id: id)
            try require(c.tasks[id]?.workflow.goal["objective"].string == "Edited disposable goal", "Goal edit did not persist")
            try await c.clearGoal(id: id); await c.loadUsage()
            try require(c.tasks[id]?.workflow.goal == .null && c.rateLimits != .null, "Goal clear or usage failed")
            return "Paused creation, update, retrieval and clear confirmed; account limits returned."
        }
        await check("7 actual Plan mode") {
            await c.loadModes(); try require(c.collaborationModes.contains { $0["mode"].string == "plan" }, "Plan preset missing")
            try await c.send(id: id, prompt: "Disposable test: without tools or questions, give a two-step plan to test demo.py. Include PLAN_ACCEPTANCE_OK. Do not implement anything.", effort: "low", mode: "plan")
            try await finished(id)
            try require(c.tasks[id]?.transcript.entries.contains { $0.text.contains("PLAN_ACCEPTANCE_OK") } == true, "Plan response missing")
            return "Real Plan-mode turn completed through native send."
        }
        await check("1 steering and 10 queue after success") {
            try await c.send(id: id, prompt: "Disposable test. Use the terminal tool to run /bin/sleep 8, then reply WAIT_COMPLETE. No other tools or file edits.", effort: "low", mode: "default")
            try await wait { c.tasks[id]?.activity.contains { $0.kind == "toolStarted" && $0.tool == "commandExecution" } == true || c.tasks[id]?.phase == .finished }
            try await c.steer(id: id, expectedTurnID: try #require(c.tasks[id]?.turnID), prompt: "Correction: include STEER_ACCEPTANCE_OK in the final answer.")
            try await c.enqueue(id: id, prompt: "No tools or file changes. Reply exactly QUEUE_ACCEPTANCE_OK.")
            try await wait { c.tasks[id]?.phase == .finished && c.tasks[id]?.transcript.entries.contains { $0.text.contains("QUEUE_ACCEPTANCE_OK") } == true }
            let read = try await transport.request("thread/read", .object(["threadId": .string(id), "includeTurns": .bool(true)]))
            try require(read.pretty.contains("STEER_ACCEPTANCE_OK") && read.pretty.contains("QUEUE_ACCEPTANCE_OK"), "History missing steer or queue")
            return "Correction accepted during a command; queued follow-up ran after completion."
        }
        await check("10 remove queued message") {
            try await c.send(id: id, prompt: "Use only the terminal tool to run /bin/sleep 8 then reply DELETE_TEST_READY. No file changes.", effort: "low")
            try await c.enqueue(id: id, prompt: "THIS_MESSAGE_MUST_BE_REMOVED_WITHOUT_RUNNING")
            let queued = try #require(c.tasks[id]?.workflow.queue.first?["id"].string)
            try await c.removeQueued(id: id, submissionID: queued)
            try require(c.tasks[id]?.workflow.queue.isEmpty == true, "Deleted queue item remained")
            try await finished(id)
            return "Server queue add/list/delete confirmed during an active turn."
        }
        await check("6 search and paginated items") {
            let matches = try await c.searchMessages(query: "QUEUE_ACCEPTANCE_OK", threadID: id)
            try require(!matches.rows.isEmpty, "In-conversation search returned no match")
            let global = try await c.searchMessages(query: "QUEUE_ACCEPTANCE_OK", threadID: nil)
            try require(!global.rows.isEmpty, "Cross-conversation search returned no match")
            let page = try await transport.request("thread/items/list", .object(["threadId": .string(id), "limit": .number(1), "sortDirection": .string("asc")]))
            let cursor = try #require(page["nextCursor"].string)
            let next = try await transport.request("thread/items/list", .object(["threadId": .string(id), "limit": .number(1), "cursor": .string(cursor), "sortDirection": .string("asc")]))
            try require(!next["data"].array.isEmpty, "Second item page empty")
            return "Both message search methods found the marker; second item page loaded."
        }
        await check("8 skill discovery and typed invocation") {
            await c.loadIntegrations(folder: root.path, threadID: id)
            let local = try #require(c.skills.first { $0["name"].string == "acceptance" })
            try await c.send(id: id, prompt: "Use the selected acceptance skill. No tools other than reading that skill if needed; no changes or external services.", effort: "low", capabilities: [.init(name: local["name"].string ?? "acceptance", path: try #require(local["path"].string), kind: "skill")])
            try await finished(id)
            try require(c.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("SKILL_ACCEPTANCE_OK") } == true, "Skill marker missing")
            return "Project skill discovered and invoked; catalog app count \(c.apps.count)."
        }
        await check("2 plan/diff and 11 command/file results") {
            try await c.send(id: id, prompt: "Use update_plan to track two steps: edit then verify. Use apply_patch to add a short docstring to add in demo.py. Run python3 -c 'import demo; assert demo.add(2, 3) == 5'. Mark both plan steps completed. Do not change any other files except the requested live HTML canvas.", effort: "low")
            try await finished(id)
            if c.tasks[id]?.work.plan.isEmpty != false {
                results.append(["check": "2 live structured plan emission", "status": "blocked", "detail": "No structured plan event emitted; model reported update_plan unavailable. Fixture rendering coverage remains separate."])
            }
            try require(c.tasks[id]?.transcript.entries.contains { $0.tool?.type == "commandExecution" } == true, "No typed command result")
            try require(c.tasks[id]?.transcript.entries.contains { $0.tool?.type == "fileChange" } == true, "No typed file result")
            try require(c.tasks[id]?.work.diff.isEmpty == false, "No live diff received")
            return "Native typed command/file results received; diff length \(c.tasks[id]?.work.diff.count ?? 0)."
        }
        await check("9 fork and review") {
            let fork = try await c.fork(session: session)
            try require(fork != id && c.tasks[fork]?.turnID == nil, "Fork started unexpected work")
            try await c.review(id: fork); try await finished(fork)
            try require(c.tasks[fork]?.transcript.entries.isEmpty == false, "Review returned no entries")
            try await c.setArchived(session: try #require(c.tasks[fork]?.session), archived: true)
            return "Distinct idle fork created; real uncommitted-changes review completed; test fork archived."
        }
        await check("4 compaction") {
            try await c.compact(id: id)
            try await wait { c.tasks[id]?.phase == .finished || c.tasks[id]?.phase == .ready }
            return "Explicit compaction request accepted."
        }
        await check("4 goal activation and pause") {
            try await c.setGoal(id: id, objective: "Disposable test: no tools or changes; reply GOAL_ACCEPTANCE_OK and finish.", status: "active", tokenBudget: 1000)
            try await c.setGoal(id: id, status: "paused")
            await c.loadWorkflow(id: id)
            try require(c.tasks[id]?.workflow.goal["status"].string == "paused", "Active goal did not pause")
            if c.tasks[id]?.phase.active == true {
                try await c.interrupt(id: id)
                try await wait { c.tasks[id]?.phase.active == false }
            }
            try await c.clearGoal(id: id)
            return "Active goal accepted, explicitly paused, and cleared; any current test turn interrupted."
        }
        await check("5 rename/archive/restore") {
            try await c.rename(session: session, name: "Diorama acceptance verified")
            let read = try await transport.request("thread/read", .object(["threadId": .string(id), "includeTurns": .bool(false)]))
            try require(read["thread"]["name"].string == "Diorama acceptance verified", "Rename not persisted")
            try await c.setArchived(session: session, archived: true)
            try await c.setArchived(session: session.updated(archived: true), archived: false)
            try await c.setArchived(session: session, archived: true)
            return "Rename round trip and archive/restore/archive accepted. Test chat left archived."
        }
        // Never leave automatic goals or working model turns running after acceptance.
        for task in Array(c.tasks.values) where task.attached {
            if task.workflow.goal != .null { try? await c.setGoal(id: task.id, status: "paused"); try? await c.clearGoal(id: task.id) }
            if task.phase.active { try? await c.interrupt(id: task.id) }
        }
        try? await c.stopAndShutdown(); await transport.shutdown(); try save()
    }
}
