import Foundation
import Testing
@testable import DioramaCore

private actor OnboardingCodex: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { _ in }
    let failure: Bool
    let delay: Bool
    init(failure: Bool, delay: Bool = false) { self.failure = failure; self.delay = delay }
    func connect() async throws { if delay { try await Task.sleep(for: .milliseconds(200)) } }
    func request(_ method: String, _ params: WireValue) throws -> WireValue {
        if method == "account/read" { return .object(["account": .object(["type": .string("chatgpt")])]) }
        if failure { throw AppServerFailure("Offline") }
        return .object(["data": .array([.object(["model": .string("gpt-test")])])])
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}
struct OnboardingConnectionTests {
    @Test func failuresAreNotAllSignOut() {
        #expect(AgentConnectionState.resolve(installed: false, connected: false, checking: false, error: "missing") == .missing)
        #expect(AgentConnectionState.resolve(installed: true, connected: false, checking: false, error: nil) == .signedOut)
        #expect(AgentConnectionState.resolve(installed: true, connected: false, checking: false, error: "Offline") == .unavailable)
        #expect(AgentConnectionState.resolve(installed: true, connected: false, checking: false, error: "Please run /login") == .signedOut)
        #expect(AgentConnectionState.resolve(installed: true, connected: true, checking: true, error: nil) == .connected)
    }
    @Test func failedOpenAICatalogPreservesClaude() async throws {
        let router = AgentExecutionTransport(codex: OnboardingCodex(failure: true), claudeProbe: { [.object(["model": .string("claude/test")])] })
        try await router.connect()
        let info = try await router.request("diorama/connections", .null)
        #expect(info["claude"].bool && !info["codex"].bool)
        let models = try await router.request("model/list", .null)
        #expect(models["data"].array.first?["model"].string == "claude/test")
    }
    @Test func failedClaudePreservesOpenAI() async throws {
        let router = AgentExecutionTransport(codex: OnboardingCodex(failure: false), claudeProbe: { throw AppServerFailure("Claude unavailable") })
        try await router.connect()
        let info = try await router.request("diorama/connections", .null)
        #expect(info["codex"].bool && !info["claude"].bool)
        #expect(try await router.request("model/list", .null)["data"].array.count == 1)
    }
    @Test func slowProviderDoesNotHideReadyProvider() async throws {
        let router = AgentExecutionTransport(codex: OnboardingCodex(failure: false, delay: true), claudeProbe: { [.object(["model": .string("claude/test")])] })
        let task = Task { try await router.connect() }
        for _ in 0..<15 {
            if try await router.request("diorama/connections", .null)["claude"].bool { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let info = try await router.request("diorama/connections", .null)
        #expect(info["claude"].bool)
        #expect(info["codexChecking"].bool)
        try await task.value
    }
    @Test func missingExplicitToolDoesNotSilentlyUseAnotherInstallation() throws {
        let suite = "onboarding-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/absent/tool-" + UUID().uuidString, forKey: "agentExecutable.codex")
        #expect(AgentExecutable.resolve("codex", defaults: defaults) == nil)
    }
    @Test func rejectsWrongExecutable() async {
        await #expect(throws: (any Error).self) { try await AgentExecutable.validate(URL(fileURLWithPath: "/usr/bin/true"), name: "codex") }
    }
}
