import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationReplayTests {
    @Test func savedHistoryRemainsResponsive() async throws {
        let path = ProcessInfo.processInfo.environment["DIORAMA_REPLAY_HISTORY"]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ExecutionController(transport: MessagesFixtureTransport())
        let provider = Provider(rawValue: ProcessInfo.processInfo.environment["DIORAMA_REPLAY_PROVIDER"] ?? "Claude Code") ?? .claude
        var task = ExecutedTask(id: ProcessInfo.processInfo.environment["DIORAMA_REPLAY_SESSION"] ?? "replay", title: "History replay", folder: root.path, turnID: "turn", attached: true)
        task.provider = provider
        task.phase = .working
        if let path, path.hasSuffix(".json") {
            let thread = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
            task.transcript = try AppServerHistory.transcript(thread, limit: 300)
        } else if let path {
            task.transcript = SessionLibrary.readTranscript(url: URL(fileURLWithPath: path), provider: provider, limit: 300)
        } else {
            // A generated fixture exercises image/tool rows in normal CI without
            // requiring or committing a user's transcript or attachments.
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let encoded = try #require(bitmap.representation(using: .png, properties: [:])).base64EncodedString()
            task.transcript.entries = (0..<60).map { index in
                var entry = Entry(id: "fixture-\(index)", kind: index % 4 == 0 ? "Tool result" : (index % 3 == 0 ? "You" : "Assistant"), text: "## Model inspection\n\n" + String(repeating: "Verify the model and preserve its materials.\n\n", count: index % 6 + 1), timestamp: nil)
                if index % 4 == 0 {
                    entry.text = ""
                    entry.claude = ClaudePresentation(title: "Render preview", status: "Completed", callID: "call-\(index)", outputs: [ClaudeOutput(id: "image-\(index)", name: "Preview.png", kind: "image", encoded: encoded)])
                }
                return entry
            }
        }
        #expect(!task.transcript.entries.isEmpty)
        #expect(Set(task.transcript.entries.map(\.id)).count == task.transcript.entries.count)
        print("Replay entries: \(task.transcript.entries.count), rows: \(ConversationHistory.rows(task.transcript.entries, mode: .conversation).count)")
        controller.tasks[task.id] = task

        let defaults = try #require(UserDefaults(suiteName: "replay-" + UUID().uuidString))
        defaults.set("Conversation", forKey: "conversationHistoryDisplayMode")
        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), navigation: WorkspaceNavigation(defaults: defaults), observationHookDirectory: nil)
        model.transcript = task.transcript
        model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        let updates = AppUpdateCoordinator()
        let host = NSHostingView(rootView: SessionView(session: task.session, model: model, hasLocalReview: true, shellContent: true, embeddedWorkScreen: true).environment(\.avatarMessages, true)
            .overlayPreferenceValue(UpdateComposerAnchor.self) { anchor in AppUpdateOverlay(updates: updates, composer: anchor) }.defaultAppStorage(defaults))
        host.frame = NSRect(x: 0, y: 0, width: 410.58203125, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        func scrolls(_ view: NSView) -> [NSScrollView] { (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls) }
        for step in 0..<400 {
            try await Task.sleep(for: .milliseconds(40))
            model.observationClock = Date()
            if step < task.transcript.entries.count {
                model.transcript.entries = Array(task.transcript.entries.prefix(step + 1))
                controller.tasks[task.id]?.transcript.entries = model.transcript.entries
            }
            if step % 5 == 0 { host.frame.size.width = [320.0, 410.58203125, 520.0][(step / 5) % 3] }
            model.execution.observeActivity(task.session, snapshot: SessionActivitySnapshot())
            if step % 10 == 0 { model.sessions = [task.session] }
            if step % 20 == 0 { print("Replay checkpoint \(step)") }
            guard step > 10, let scroll = scrolls(host).max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }) else { continue }
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, min((scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height, ((scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height) * CGFloat(abs(20 - step % 40)) / 20))))
            scroll.reflectScrolledClipView(scroll.contentView)
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
            NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
            if step % 40 == 0 { print("Scroll extent: \(scroll.documentView?.bounds.height ?? 0), offset: \(scroll.contentView.bounds.minY)") }
        }
    }
}
