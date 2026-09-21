import Foundation
import Testing
@testable import DioramaCore

@MainActor struct IntegrationDiscoveryLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_INTEGRATIONS_PROBE"] == "1"))
    func readOnlyDiscoveryAndWarmReopen() async throws {
        let transport = CodexExecutionTransport(timeout: .seconds(35))
        let c = ExecutionController(transport: transport)
        let folder = FileManager.default.currentDirectoryPath
        let start = Date()
        await c.loadIntegrations(folder: folder, threadID: nil)
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        await c.loadIntegrations(folder: folder, threadID: nil)
        let warm = Date().timeIntervalSince(warmStart)
        let errors = c.featureErrors.filter { ["skills", "app/installed", "mcpServerStatus/list"].contains($0.key) }
        #expect(errors.isEmpty)
        #expect(!c.appDirectoryLoaded)
        let evidence: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "coldSeconds": cold, "warmSeconds": warm, "skills": c.skills.count, "installedApps": c.apps.count, "mcpServers": c.connectors.count, "errors": errors, "directoryFetched": c.appDirectoryLoaded, "scope": "Read-only controller discovery, not on-screen latency"]
        await transport.shutdown()
        let url = URL(fileURLWithPath: folder).appendingPathComponent("evidence/integration-discovery.json")
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}
