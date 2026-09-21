import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

private actor SettingsTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { _ in }
    func connect() {}
    func request(_ method: String, _ p: WireValue) -> WireValue {
        if method == "diorama/connections" { return .object(["codex": .bool(true), "claude": .bool(true)]) }
        return .object(["data": .array([.object(["model": .string("gpt-fixture"), "displayName": .string("OpenAI test model")]), .object(["model": .string("claude/sonnet"), "displayName": .string("Sonnet")])])])
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}
@MainActor struct AgentSettingsTests {
    @Test func settingsAndCombinedPickerRenderBothProviders() async throws {
        let controller = ExecutionController(transport: SettingsTransport())
        await controller.connect()
        #expect(controller.models.count == 2)
        try render(AgentSettingsView(controller: controller), to: "/tmp/diorama-agent-settings.png")
        try render(ExecutionModelPicker(controller: controller, model: .constant("claude/sonnet"), effort: .constant("")).padding(24).frame(width: 380), to: "/tmp/diorama-agent-model-picker.png")
    }
    private func render(_ view: some View, to path: String) throws {
        let host = NSHostingView(rootView: view.background(Color(white: 0.13)).environment(\.colorScheme, .dark))
        host.frame.size = host.fittingSize; host.layoutSubtreeIfNeeded()
        #expect(host.bounds.width > 300)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
