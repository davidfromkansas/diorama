import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationReplayTests {
    @Test func savedHistoryRemainsResponsive() async throws {
        guard let path = ProcessInfo.processInfo.environment["DIORAMA_REPLAY_HISTORY"] else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ExecutionController(transport: MessagesFixtureTransport())
        var task = ExecutedTask(id: ProcessInfo.processInfo.environment["DIORAMA_REPLAY_SESSION"] ?? "replay", title: "History replay", folder: root.path, turnID: "turn", attached: false)
        task.phase = .finished
        task.transcript = SessionLibrary.readTranscript(url: URL(fileURLWithPath: path), provider: .codex, limit: 300)
        print("Replay entries: \(task.transcript.entries.count), rows: \(ConversationHistory.rows(task.transcript.entries, mode: .conversation).count)")
        controller.tasks[task.id] = task

        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")))
        model.transcript = task.transcript
        model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        let host = NSHostingView(rootView: SessionView(session: task.session, model: model, hasLocalReview: true, shellContent: true, embeddedWorkScreen: true).environment(\.avatarMessages, true))
        host.frame = NSRect(x: 0, y: 0, width: 418, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        func scrolls(_ view: NSView) -> [NSScrollView] { (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls) }
        for step in 0..<200 {
            try await Task.sleep(for: .milliseconds(100))
            model.observationClock = Date()
            model.execution.observeActivity(task.session, snapshot: SessionActivitySnapshot())
            if step % 10 == 0 { model.sessions = [task.session] }
            host.layoutSubtreeIfNeeded()
            if step % 20 == 0 { print("Replay checkpoint \(step)") }
            guard step > 10, let scroll = scrolls(host).max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }) else { continue }
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, scroll.contentView.bounds.minY - 160)))
            scroll.reflectScrolledClipView(scroll.contentView)
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
            NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        }
    }
}
