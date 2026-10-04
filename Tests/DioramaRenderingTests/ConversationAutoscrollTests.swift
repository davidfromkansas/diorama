import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationAutoscrollTests {
    @Test(arguments: [false, true]) func sendingStreamingAndUserScrollMaintainCorrectFollowIntent(messages: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ExecutionController(transport: MessagesFixtureTransport())
        var task = ExecutedTask(id: "scroll-fixture", title: "Scroll fixture", folder: root.path, turnID: "turn", attached: true)
        task.phase = .working
        task.transcript.entries = (0..<35).map {
            Entry(id: "row-\($0)", kind: "Assistant", text: String(repeating: "Earlier message content.\n\n", count: 4), timestamp: nil)
        }
        controller.tasks[task.id] = task
        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), navigation: WorkspaceNavigation(defaults: UserDefaults(suiteName: "scroll-" + UUID().uuidString)!))
        model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        let host = NSHostingView(rootView: SessionView(session: task.session, model: model, hasLocalReview: true, shellContent: messages, embeddedWorkScreen: messages).environment(\.avatarMessages, messages))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        func settle() async throws {
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(80))
                host.layoutSubtreeIfNeeded()
            }
        }
        func scrolls(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        try await settle()
        let scroll = try #require(scrolls(host).max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) })
        func atBottom() -> Bool {
            guard let document = scroll.documentView else { return false }
            return document.bounds.maxY - scroll.contentView.bounds.maxY < 65
        }
        #expect(atBottom(), "Initial history must settle at its actual bottom")
        let message = OutgoingMessage(sessionID: task.id, text: "A new prompt", attachmentPaths: [], baselineIDs: Set(task.transcript.entries.map(\.id)))
        model.outgoing[message.id] = message
        try await settle()
        #expect(atBottom(), "Optimistic send must retain follow mode: offset \(scroll.contentView.bounds.minY), content \(scroll.documentView!.bounds.height), viewport \(scroll.contentView.bounds.height)")
        controller.tasks[task.id]?.transcript.entries.append(Entry(id: "response", kind: "Assistant", text: "Beginning", timestamp: nil))
        for _ in 0..<3 {
            controller.tasks[task.id]?.transcript.entries[35].text += String(repeating: "\n\nNew streamed paragraph.", count: 12)
            try await settle()
            #expect(atBottom(), "Growing response must remain visible")
        }
        // The first small movement must detach immediately, even inside the old 64pt threshold.
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        let nearBottom = max(0, scroll.contentView.bounds.minY - 24)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: nearBottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        try await settle()
        #expect(abs(scroll.contentView.bounds.minY - nearBottom) < 5, "A small upward scroll must not snap back")
        controller.tasks[task.id]?.phase = .finished
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        try await settle()
        #expect(!atBottom())
        let restingOffset = scroll.contentView.bounds.minY
        for _ in 0..<4 {
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            try await settle()
        }
        #expect(abs(scroll.contentView.bounds.minY - restingOffset) < 5, "Idle manual position must not drift during layout updates")
        controller.tasks[task.id]?.transcript.entries[35].text += String(repeating: "\n\nMore text.", count: 12)
        try await settle()
        #expect(!atBottom(), "Incoming text must not pull a history reader to the bottom")
        let next = OutgoingMessage(sessionID: task.id, text: "Another prompt", attachmentPaths: [], baselineIDs: [])
        model.outgoing[next.id] = next
        try await settle()
        #expect(atBottom(), "Sending from earlier history must resume follow mode: offset \(scroll.contentView.bounds.minY), content \(scroll.documentView!.bounds.height), viewport \(scroll.contentView.bounds.height)")
    }
}


extension ConversationAutoscrollTests {
    @Test func nativeScrollCallbacksAreDeferredAndCancelledOnDetach() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2000))
        scroll.documentView = document
        let probe = ConversationScrollTracking.Probe(onUserScroll: { _ in })
        document.addSubview(probe)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.contentView = nil; window.orderOut(nil) }
        var began = 0
        var following: [Bool] = []
        probe.onScrollBegan = {
            #expect(probe.userIsScrolling, "Native state must settle before publishing to SwiftUI")
            began += 1
            // SwiftUI layout may cause another native notification while handling a callback.
            if began == 1 { NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll) }
        }
        probe.onUserScroll = { following.append($0) }
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        #expect(probe.userIsScrolling)
        #expect(!probe.followsLatest, "Bottom pinning must stop before the first wheel delta")
        #expect(began == 0 && following.isEmpty, "Native event dispatch must not mutate SwiftUI state")
        try await Task.sleep(for: .milliseconds(30))
        #expect(began == 1)
        #expect(following == [false])
        probe.stopObserving()
        try await Task.sleep(for: .milliseconds(250))
        #expect(following == [false], "Detached views must not publish a pending scroll completion")
    }
}

extension ConversationAutoscrollTests {
    @Test func olderHistoryLoadsDuringScrollWithoutDuplicateRequests() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 4000))
        scroll.documentView = document
        let probe = ConversationScrollTracking.Probe(onUserScroll: { _ in })
        probe.followsLatest = false
        document.addSubview(probe)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.contentView = nil; window.orderOut(nil) }
        var requests = 0
        probe.onOlderHistory = { requests += 1 }
        func move(_ y: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        }
        move(900)
        try await Task.sleep(for: .milliseconds(25))
        #expect(requests == 0)
        move(450)
        #expect(requests == 0, "Loading must be deferred out of native event dispatch")
        try await Task.sleep(for: .milliseconds(25))
        #expect(requests == 1 && probe.userIsScrolling, "Fetch before scrolling ends")
        for _ in 0..<10 { move(400) }
        try await Task.sleep(for: .milliseconds(25))
        #expect(requests == 1, "Momentum must not duplicate a page request")
        move(2000) // The preserved anchor moves down after older rows are inserted.
        try await Task.sleep(for: .milliseconds(25))
        move(450)
        try await Task.sleep(for: .milliseconds(25))
        #expect(requests == 2, "Continuing into another page must load again")
        move(2000)
        try await Task.sleep(for: .milliseconds(25))
        move(400)
        probe.stopObserving()
        try await Task.sleep(for: .milliseconds(25))
        #expect(requests == 2, "Switching conversations cancels queued pagination")
    }
}
