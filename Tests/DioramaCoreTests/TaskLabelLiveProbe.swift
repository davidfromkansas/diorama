import Foundation
import Testing
@testable import DioramaCore

/// Opt-in, real providers: four-word task labels through Diorama's own connections.
///
///     DIORAMA_LABEL_PROBE=1 swift test --filter TaskLabelLiveProbe
@MainActor struct TaskLabelLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_LABEL_PROBE"] == "1"))
    func labelsComeFromTheAgentsProvider() async throws {
        let transport = AgentExecutionTransport()
        let c = ExecutionController(transport: transport)
        await c.connect(); await c.refreshModels()
        let tasks = ["Build a website that shows a three.js model of Salesforce Tower in San Francisco where the sun rises and sets in real time.",
                     "can you fix the bug where the login button doesn't respond on mobile safari",
                     "Create a early 2000s inspired website that shows SF Tech Events schedule"]
        for provider in [Provider.codex, .claude] {
            for task in tasks {
                let start = Date()
                let label = await c.taskLabel(task, provider: provider)
                print(String(format: "LABEL %@ %.1fs → %@", provider.rawValue, Date().timeIntervalSince(start), label ?? "nil"))
                #expect(label.map { $0.split(separator: " ").count <= 4 } ?? true)
            }
        }
        #expect(c.tasks.isEmpty)
        await transport.shutdown()
    }
}
