import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationScrollPerformanceTests {
    @Test func switchingAgentsRestoresIndependentHistoryAndPreparedRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(execution: ExecutionController(transport: MessagesFixtureTransport()), projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), navigation: WorkspaceNavigation(defaults: try #require(UserDefaults(suiteName: UUID().uuidString))), observationHookDirectory: nil, draftDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        for id in ["project-one/agent-a", "project-one/agent-b", "project-two/agent-a", "project-two/agent-b"] {
            model.selectedID = id
            #expect(model.transcript.entries.isEmpty)
            model.transcript.entries = [Entry(id: id, kind: "Assistant", text: "History for \(id)", timestamp: nil)]
            model.transcriptSessionID = id
            _ = model.conversationPresentation.rows(for: id).prepare(model.transcript.entries, mode: .conversation)
            model.drafts[id] = ConversationDraft()
            model.drafts[id]?.text = "Unsent for \(id)"
        }
        for _ in 0..<4 {
            for id in ["project-one/agent-a", "project-two/agent-a", "project-one/agent-b", "project-two/agent-b"] {
                model.selectedID = id
                #expect(model.transcriptSessionID == id)
                #expect(model.transcript.entries.first?.text == "History for \(id)")
                let cache = model.conversationPresentation.rows(for: id)
                _ = cache.prepare(model.transcript.entries, mode: .conversation)
                #expect(cache.revision == 1)
                #expect(model.drafts[id]?.text == "Unsent for \(id)")
            }
        }
        model.transcript.entries[0].text = "Refreshed content"
        let edited = model.selectedID
        model.selectedID = nil
        model.selectedID = edited
        #expect(model.transcript.entries.first?.text == "Refreshed content")
        model.selectedID = "uncached"
        #expect(model.transcriptSessionID == nil)
        #expect(model.transcript.entries.isEmpty, "A cold conversation must never show another agent's history")
    }

    @Test(arguments: ["none", "agents", "projects"]) func completedConversationScrollLayoutCost(switching: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ExecutionController(transport: MessagesFixtureTransport())
        var task = ExecutedTask(id: "scroll-cost", title: "Scroll cost", folder: root.path, turnID: "turn", attached: true)
        task.provider = .claude; task.phase = .finished
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set("Conversation", forKey: "conversationHistoryDisplayMode")
        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), navigation: WorkspaceNavigation(defaults: defaults), observationHookDirectory: nil, draftDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        if let path = ProcessInfo.processInfo.environment["DIORAMA_SCROLL_HISTORY"] {
            task.transcript = SessionLibrary.readTranscript(url: URL(fileURLWithPath: path), provider: .claude, limit: 1000)
        } else {
            task.transcript.entries = (0..<100).map { Entry(id: "row-\($0)", kind: "Assistant", text: "## Inspection \($0)\n\n" + String(repeating: "- Keep the **materials** and verify the animation.\n", count: $0 % 12 + 1), timestamp: nil) }
        }
        var other = ExecutedTask(id: "other-project-scroll", title: "Other project", folder: root.appendingPathComponent("other").path, turnID: "other-turn", attached: true)
        other.provider = .claude; other.phase = .finished; other.transcript = task.transcript
        controller.tasks[task.id] = task; controller.tasks[other.id] = other
        var firstProject = DioramaProject(name: "First", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        var secondProject = DioramaProject(name: "Second", folder: other.folder, commonDirectory: other.folder, base: "main", remote: nil)
        firstProject.selectedSession = task.session.id; secondProject.selectedSession = other.session.id
        model.projects.projects = [firstProject, secondProject]
        model.sessions = [task.session, other.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        let host = NSHostingView(rootView: SwitchingConversationFixture(model: model).environment(\.avatarMessages, true).environment(\.colorScheme, .light).defaultAppStorage(defaults))
        host.frame = NSRect(x: 0, y: 0, width: 410, height: 820)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(400))
        func scrolls(_ view: NSView) -> [NSScrollView] { if view.isHiddenOrHasHiddenAncestor { return [] }; return (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls) }
        var scroll = try #require(scrolls(host).max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) })
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        var costs: [Double] = []
        for step in 0..<240 {
            try await Task.sleep(for: .milliseconds(8))
            let start = ContinuousClock.now
            if switching != "none" && step > 0 && step % 60 == 0 {
                let target = step % 120 == 0 ? task : other
                if switching == "projects" { model.selectProjectTab(step % 120 == 0 ? firstProject.id : secondProject.id) }
                model.selectedID = target.session.id; model.viewMode = .conversation
                // A loaded history is essential: otherwise a paused model tests an
                // empty placeholder after the switch rather than conversation rows.
                model.transcriptSessionID = target.session.id
                host.layoutSubtreeIfNeeded()
                scroll = try #require(scrolls(host).max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) })
                #expect((scroll.documentView?.bounds.height ?? 0) > 820)
                NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                let elapsed = start.duration(to: .now).components
                print("\(switching) switch at step \(step): \(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15) ms")
            }
            let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
            // Smooth triangular traversal with reversals, including newly exposed rows.
            let fraction = CGFloat(abs(120 - step % 240)) / 120
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * fraction))
            scroll.reflectScrolledClipView(scroll.contentView)
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
            if step % 30 == 0 {
                func editors(_ view: NSView) -> [ComposerNSTextView] { (view as? ComposerNSTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
                let editor = try #require(editors(host).first)
                #expect(editor.isEditable)
                editor.insertText(" draft", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
                #expect(editor.string.hasSuffix(" draft"))
            }
            host.layoutSubtreeIfNeeded()
            let elapsed = start.duration(to: .now).components
            costs.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        costs.sort()
        print("Scroll/layout (switching=\(switching)) main-thread milliseconds: median=\(costs[120]), p95=\(costs[228]), max=\(costs.last!)")
        #expect(scroll.contentView.bounds.minY.isFinite)
        if switching == "projects", let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/diorama-conversation-switching.png"))
        }
    }

    @Test func repeatedLayoutReadsOfCompletedClaudeHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ExecutionController(transport: MessagesFixtureTransport())
        var task = ExecutedTask(id: "completed-scroll", title: "Completed history", folder: root.path, turnID: "turn", attached: true)
        task.provider = .claude
        task.phase = .finished
        task.liveStartedAt = Date(timeIntervalSince1970: 1_790_000_000)
        task.transcript.entries = [Entry(id: "live", kind: "Assistant", text: "Finished", timestamp: nil)]
        controller.tasks[task.id] = task
        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), navigation: WorkspaceNavigation(defaults: try #require(UserDefaults(suiteName: UUID().uuidString))), observationHookDirectory: nil, draftDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id
        model.transcript.entries = (0..<300).map { Entry(id: "saved-\($0)", kind: "Assistant", text: "Earlier message \($0)", timestamp: "2026-09-01T12:00:00.000Z") }
        let clock = ContinuousClock()
        let duration = clock.measure {
            for _ in 0..<120 { #expect(model.displayedTranscript.entries.count == 301) }
        }
        print("Completed history: 120 layout reads took \(duration)")
    }

    @Test func draftPersistenceCoalescesAndFlushesLatestSnapshot() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let persistence = ConversationDraftPersistence(defaults: defaults)
        var drafts = ["one": ConversationDraft(), "two": ConversationDraft()]
        for index in 0..<100 {
            drafts["one"]?.text = "Draft \(index)"
            persistence.schedule(drafts)
        }
        #expect(defaults.data(forKey: "conversationDrafts") == nil)
        persistence.flush()
        #expect(persistence.load()["one"]?.text == "Draft 99")
        drafts["two"]?.text = "Another conversation"
        persistence.schedule(drafts)
        try await Task.sleep(for: .milliseconds(400))
        #expect(persistence.load()["two"]?.text == "Another conversation")
        #expect(persistence.load()["one"]?.text == "Draft 99")
    }

    @Test func mergedHistoryInvalidatesOnContentAndSourceChanges() {
        let cache = ConversationTranscriptCache()
        var saved = Transcript()
        saved.entries = [Entry(id: "old", kind: "Assistant", text: "Earlier", timestamp: "2026-09-01T12:00:00Z"), Entry(id: "echo", kind: "Assistant", text: "Saved echo", timestamp: "2026-10-04T12:00:00.000Z")]
        var live = Transcript()
        live.entries = [Entry(id: "live", kind: "Assistant", text: "Streaming", timestamp: nil)]
        let cutoff = AvatarMessagePresentation.date("2026-10-04T11:00:00Z")!
        let first = cache.merged(saved: saved, live: live, claudeCutoff: cutoff)
        #expect(first.entries.map(\.id) == ["old", "live"])
        for _ in 0..<120 { #expect(cache.merged(saved: saved, live: live, claudeCutoff: cutoff) == first) }
        #expect(cache.revision == 1, "Layout reads must not repeat timestamp parsing or merging")
        live.entries[0].text = "Finished"
        #expect(cache.merged(saved: saved, live: live, claudeCutoff: cutoff).entries.last?.text == "Finished")
        saved.notice = "Older history loaded"
        #expect(cache.merged(saved: saved, live: live, claudeCutoff: cutoff).notice == saved.notice)
        #expect(cache.merged(saved: saved, live: nil, claudeCutoff: nil) == saved)
        #expect(cache.merged(saved: Transcript(), live: nil, claudeCutoff: nil).entries.isEmpty)
    }
}

@MainActor private struct SwitchingConversationFixture: View {
    @Bindable var model: LibraryModel
    var body: some View {
        Group {
            if let session = model.selected {
                SessionView(session: session, model: model, hasLocalReview: true, shellContent: true, embeddedWorkScreen: true).id(session.id)
            }
        }
    }
}
