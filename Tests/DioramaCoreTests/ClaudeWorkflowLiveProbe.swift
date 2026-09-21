import Foundation
import Testing
@testable import DioramaCore

@MainActor struct ClaudeWorkflowLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_CLAUDE_WORKFLOW_PROBE"] == "1"))
    func subscriptionSteeringAndGoal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-workflow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let transport = ClaudeExecutionTransport(folder: folder.path)
        let controller = ExecutionController(transport: transport, journal: folder.appendingPathComponent("owned.json"))
        do {
            await controller.connect()
            try #require(controller.connected)
            await controller.loadModes()
            let id = try await controller.prepare(folder: folder.path, title: "Claude workflow verification", model: "claude/haiku")
            try await controller.send(id: id, prompt: "Use only Bash to execute /bin/sleep 30, then reply ORIGINAL_FINISHED. Do not read or modify files or use any other tools.", model: "claude/haiku")
            try await until { !controller.requests.isEmpty || controller.tasks[id]?.phase == .finished }
            if let request = controller.requests.values.first {
                let description = request.params["command"].string ?? ""
                print("Verification permission:", description)
                try #require(description.replacingOccurrences(of: "\\/", with: "/").contains("/bin/sleep 30"))
                try await controller.answer(id: request.id, result: .object(["decision": .string("accept")]))
            }
            try await until { controller.canSteer(id: id) }
            // Allow execution to enter its tool wait before applying the correction.
            try await Task.sleep(for: .seconds(1))
            let original = try #require(controller.tasks[id]?.turnID)
            try await controller.steer(id: id, expectedTurnID: original, prompt: "Cancel the original sleep task. Do not use tools. Reply exactly CLAUDE_STEER_VERIFIED.")
            try await until { controller.tasks[id]?.phase == .finished }
            try #require(controller.tasks[id]?.transcript.entries.contains { $0.text.contains("CLAUDE_STEER_VERIFIED") && $0.kind == "Assistant" } == true)
            try await controller.sendWithGoal(id: id, prompt: "This is a two-response verification. Use no tools. On your first response report progress FIRST_STEP and choose CONTINUE using the Diorama goal status instruction. On the next continuation respond SECOND_STEP and choose COMPLETE. Do not finish both steps in one response.", model: "claude/haiku", goal: true)
            try await until { ["complete", "paused"].contains(controller.tasks[id]?.workflow.goal["status"].string ?? "") && (controller.tasks[id]?.workflow.goal["turnsUsed"].number ?? 0) >= 2 }
            try #require(controller.tasks[id]?.workflow.goal["status"].string == "complete")
            try #require(controller.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("SECOND_STEP") } == true)
            try #require(controller.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("DIORAMA_GOAL_") } == false)
            let evidence: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "session": id, "subscriptionGate": true, "steering": "interrupt confirmed, replacement replied", "goal": "two responses, continuation then completion", "goalTurns": controller.tasks[id]?.workflow.goal["turnsUsed"].number ?? 0, "provider": "Claude only"]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/claude-workflow-live.json"), options: .atomic)
            await transport.shutdown()
        } catch { await transport.shutdown(); throw error }
    }
    private func until(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(100)
        while !condition() {
            guard Date() < end else { throw AppServerFailure("Live workflow check timed out") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
