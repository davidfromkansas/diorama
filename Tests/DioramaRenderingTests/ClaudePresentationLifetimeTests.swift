import AppKit
import SwiftUI
import Testing
@testable import DioramaCore
@testable import DioramaApp

private actor LifetimeFixtureTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue> = AsyncStream { $0.finish() }
    func connect() {}
    func request(_ method: String, _ params: WireValue) -> WireValue { .object(["data": .array([]), "goal": .null]) }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}

@MainActor struct ClaudePresentationLifetimeTests {
    @Test func nativeClaudePresentationSurvivesActivityUpdatesAndTeardown() async throws {
        let controller = ExecutionController(transport: LifetimeFixtureTransport())
        let session = Session(id: "Claude Code:lifetime-fixture", provider: .claude, url: nil, sessionID: "lifetime-fixture", title: "Claude presentation lifetime", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        var task = ExecutedTask(id: session.sessionID, provider: .claude, title: session.title, folder: session.project, phase: .working, turnID: "turn", attached: true)
        task.model = "claude/sonnet"
        task.workflow.goal = .object(["objective": .string("Verify fixture activity"), "status": .string("paused")])
        task.workflow.queue = [.object(["id": .string("queued"), "input": .array([.object(["type": .string("text"), "text": .string("Follow-up fixture")])])])]
        controller.tasks[session.sessionID] = task
        let library = LibraryModel(execution: controller)
        library.sessions = [session]; library.selectedID = session.id; library.transcriptSessionID = session.id; library.projectNavigation = true
        // Type erasure lets this exercise native presentation destruction without
        // launching a provider or depending on macOS accessibility automation.
        var host: NSHostingView<AnyView>? = NSHostingView(rootView: AnyView(SessionView(session: session, model: library, hasLocalReview: true)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        for index in 0..<50 {
            await controller.receive(.object(["method": .string("diorama/claudeActivity"), "params": .object([
                "threadId": .string(session.sessionID),
                "event": .object(["type": .string("system"), "subtype": .string("task_started"), "task_id": .string("child-\(index)"), "task_type": .string("local_agent"), "description": .string("Fixture child \(index)")])
            ])]))
            await controller.receive(.object(["method": .string("item/agentMessage/delta"), "params": .object(["threadId": .string(session.sessionID), "turnId": .string("turn"), "itemId": .string("response"), "delta": .string("Event \(index). ")])]))
            host?.layoutSubtreeIfNeeded()
            // Let native popover/presentation graph closures be replaced.
            try await Task.sleep(for: .milliseconds(5))
            if index % 10 == 9 {
                host?.rootView = AnyView(EmptyView())
                host?.layoutSubtreeIfNeeded()
                host?.rootView = AnyView(SessionView(session: session, model: library, hasLocalReview: true))
            }
        }
        #expect(controller.tasks[session.sessionID]?.structuredActivity.agents.count == 50)
        host?.rootView = AnyView(EmptyView()); host?.layoutSubtreeIfNeeded()
        window.contentView = nil
        host = nil
        controller.tasks.removeAll()
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.tasks.isEmpty)
        window.orderOut(nil)
    }
}
