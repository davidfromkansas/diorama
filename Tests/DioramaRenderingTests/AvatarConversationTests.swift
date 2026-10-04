import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct AvatarConversationTests {
    @Test func conversationPanelToggleRetainsAgentAndDoesNotChangeToolInspector() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = LibraryModel(execution: ExecutionController(transport: MessagesFixtureTransport()),
            projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")))
        model.projects.selectedID = nil
        let selected = SpatialFocus.agent(project: "p", conversation: "c", agent: "a", expanded: true)
        model.spatial.focus = selected
        let inspector = model.navigation.layout.inspectorVisible
        #expect(model.spatial.conversationPanelVisible)
        model.toggleWorkspaceInspector()
        #expect(!model.spatial.conversationPanelVisible)
        model.toggleWorkspaceInspector()
        #expect(model.spatial.conversationPanelVisible)
        #expect(model.spatial.focus == selected)
        #expect(model.navigation.layout.inspectorVisible == inspector)
    }
    @Test func panelWidthFitsNarrowWindowsAndLeavesRoomForOffice() {
        #expect(SpatialWorkspaceView.conversationPanelWidth(available: 300) == 300)
        #expect(SpatialWorkspaceView.conversationPanelWidth(available: 740) < 400)
        #expect(SpatialWorkspaceView.conversationPanelWidth(available: 1500) == 600)
    }

    @Test func nestedPopoverDismissalCannotFallThroughInSameEvent() {
        let targets = AvatarPopoverDismissals()
        let outer = UUID(), inner = UUID()
        var outerClosed = false, innerClosed = false
        targets.register(outer) { outerClosed = true }
        targets.register(inner) { innerClosed = true }
        #expect(targets.dismissTop())
        #expect(innerClosed && !outerClosed)
        // Multiple handlers receiving the same event must not dismiss the parent.
        #expect(targets.dismissTop())
        #expect(!outerClosed)
        targets.remove(inner)
        #expect(targets.dismissTop())
        #expect(outerClosed)
        targets.remove(outer)
        #expect(!targets.dismissTop())
    }

    @Test func timestampsAndSenderGroupsUseReportedTimes() {
        let entries = [
            Entry(id: "a", kind: "You", text: "Hello", timestamp: nil),
            Entry(id: "b", kind: "You", text: "First known", timestamp: "2026-10-01T10:00:00Z"),
            Entry(id: "c", kind: "You", text: "Same group", timestamp: "2026-10-01T10:01:00.000Z"),
            Entry(id: "d", kind: "Assistant", text: "Reply", timestamp: "2026-10-01T10:07:00Z")
        ]
        #expect(AvatarMessagePresentation.separator(before: 0, entries: entries) == nil)
        #expect(AvatarMessagePresentation.separator(before: 1, entries: entries) != nil)
        #expect(AvatarMessagePresentation.separator(before: 2, entries: entries) == nil)
        #expect(AvatarMessagePresentation.separator(before: 3, entries: entries) != nil)
        #expect(!AvatarMessagePresentation.tail(after: 1, entries: entries))
        #expect(AvatarMessagePresentation.tail(after: 2, entries: entries))
        #expect(AvatarMessagePresentation.date("not a date") == nil)
    }
    @Test func branchRequiresMatchingConversation() {
        let session = Session(id: "Codex:test", provider: .codex, url: nil, sessionID: "test", title: "Task", project: "/repo", modified: .distantPast, bytes: 0, archived: false, parentID: nil)
        var workspace = ProjectWorkspace(id: "w", folder: "/repo", branch: "feature/messages", baseCommit: "", context: ProjectContext())
        workspace.threadID = "another"
        #expect(AvatarMessagePresentation.branch(session: session, workspaces: [workspace]) == "Branch unavailable")
        workspace.threadID = "test"
        #expect(AvatarMessagePresentation.branch(session: session, workspaces: [workspace]) == "feature/messages")
    }
    @Test func lightModalRendersAtNarrowAndStandardWidths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ExecutionController(transport: MessagesFixtureTransport())
        var task = ExecutedTask(id: "messages-fixture", title: "Messages layout", folder: root.path, turnID: "turn", attached: true)
        task.phase = .working
        task.transcript.entries = [
            Entry(id: "u", kind: "You", text: "Can you show me the update?", timestamp: "2026-10-01T12:00:00Z"),
            Entry(id: "a", kind: "Assistant", text: "The new layout is ready. **Messages stay readable**, with the same agent controls in the + menu.", timestamp: "2026-10-01T12:01:00Z"),
            Entry(id: "u2", kind: "You", text: "Nice!", timestamp: "2026-10-01T12:02:00Z")
        ]
        controller.tasks[task.id] = task
        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")))
        model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        for width in [390.0, 800.0] {
            let host = NSHostingView(rootView:
                SessionView(session: task.session, model: model, hasLocalReview: true, shellContent: true, embeddedWorkScreen: true)
                    .environment(\.avatarMessages, true).environment(\.colorScheme, .light).tint(.blue).background(.white)
            )
            host.frame = NSRect(x: 0, y: 0, width: width, height: 650)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            for _ in 0..<5 { try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded() }
            func editors(_ view: NSView) -> [ComposerNSTextView] { (view as? ComposerNSTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
            let editor = try #require(editors(host).first)
            #expect(host.bounds.contains(editor.convert(editor.bounds, to: host)))
            #expect(editor.enclosingScrollView!.frame.height <= 128)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-messages-\(Int(width)).png"))
            window.contentView = nil; window.orderOut(nil)
        }
    }
}

actor MessagesFixtureTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    func connect() {}
    func request(_ method: String, _ params: WireValue) throws -> WireValue {
        if method == "turn/start" { throw AppServerFailure("Fixture must never start a turn") }
        return .object([:])
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}
