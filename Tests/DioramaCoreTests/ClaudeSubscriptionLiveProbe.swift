import Foundation
import Testing
@testable import DioramaCore

@MainActor struct ClaudeSubscriptionLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_CLAUDE_SUBSCRIPTION_PROBE"] == "1"))
    func subscriptionCompletesRealTurn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-subscription-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = ClaudeExecutionTransport(folder: root.path)
        let controller = ExecutionController(transport: transport, journal: root.appendingPathComponent("owned.json"))
        do {
            try await transport.connect()
            await controller.connect()
            try #require(controller.connected)
            try #require(!controller.models.isEmpty)
            let id = try await controller.prepare(folder: root.path, title: "Claude subscription verification", model: "claude/haiku")
            try await controller.send(id: id, prompt: "Do not use tools or modify files. Reply exactly DIORAMA_SUBSCRIPTION_OK.", model: "claude/haiku")
            let deadline = Date().addingTimeInterval(90)
            while controller.tasks[id]?.phase != .finished && controller.tasks[id]?.phase != .failed {
                guard Date() < deadline else { throw AppServerFailure("Subscription live probe timed out") }
                try await Task.sleep(for: .milliseconds(100))
            }
            try #require(controller.tasks[id]?.phase == .finished)
            try #require(controller.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("DIORAMA_SUBSCRIPTION_OK") } == true)
            let evidence: [String: Any] = ["updatedAt": ISO8601DateFormatter().string(from: Date()), "subscriptionGateAccepted": true, "realTurnCompleted": true, "expectedReplyReceived": true, "model": "claude/haiku", "sessionID": id, "path": "ClaudeExecutionTransport → ExecutionController → transcript", "billingDashboardChecked": false]
            let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/claude-subscription-live.json"), options: .atomic)
            await transport.shutdown()
        } catch { await transport.shutdown(); throw error }
    }
}
