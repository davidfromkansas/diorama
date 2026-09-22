import Foundation
import Testing
@testable import DioramaCore

@MainActor struct PersonaClaudeLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_PERSONA_CLAUDE_LIVE"] == "1"))
    func routedPlanningTurn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-persona-router-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = AgentExecutionTransport()
        let controller = ExecutionController(transport: transport, journal: root.appendingPathComponent("owned.json"))
        do {
            await controller.connect()
            try #require(controller.connected)
            await controller.loadModes()
            let id = try await controller.prepare(folder: root.path, title: "Persona routed Claude plan probe", model: "claude/sonnet")
            try await controller.send(id: id, prompt: "Do not use tools or modify files. Give a three-line plan for a garden landing page, beginning with PERSONA_PLAN_OK.", model: "claude/sonnet", mode: "plan")
            let deadline = Date().addingTimeInterval(75)
            while [.working, .submitting].contains(controller.tasks[id]?.phase ?? .failed), Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            let task = try #require(controller.tasks[id])
            let evidence: [String: Any] = ["sessionID": id, "phase": task.phase.rawValue, "attached": task.attached, "error": task.error ?? "", "entries": task.transcript.entries.map { ["kind": $0.kind, "text": String($0.text.prefix(1000))] }, "eventCount": task.activity.count, "mode": task.workflow.mode]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/diorama-persona-claude-probe.json"))
            try #require(task.phase == .finished)
            #expect(task.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("PERSONA_PLAN_OK") })
            await transport.shutdown()
        } catch { await transport.shutdown(); throw error }
    }
}
