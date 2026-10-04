import AppKit
import SwiftUI
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ProjectInboxRenderingTests {
    @Test func timestampUsesTimeTodayAndDateEarlier() {
        let now = Date(), yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(InboxThreadRow.timestamp(now, received: false, now: now) == now.formatted(date: .omitted, time: .shortened))
        #expect(InboxThreadRow.timestamp(yesterday, received: false, now: now) == yesterday.formatted(date: .abbreviated, time: .shortened))
        #expect(InboxThreadRow.timestamp(now, received: true, now: now).hasPrefix("Received "))
    }

    /// Opt-in native-window test, not an offscreen snapshot or a paid agent turn.
    @Test func nativeOfficeAndInboxScrollingCapture() async throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_INBOX_BENCHMARK"] == "1" else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InboxRender-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectInboxStore(directory: directory)
        let date = Date()
        for i in 0..<10_000 {
            try await store.ingest(project: "fixture", conversation: "c\(i)", title: "A longer project task title \(i)",
                updates: [.init(id: "u\(i)", text: "Fixture output with a file and detailed explanation.",
                               outputs: [.init(id: "image", name: "Image", kind: "image", encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")],
                               date: date.addingTimeInterval(Double(-i)))], historicalBefore: date)
        }
        let agents = (0..<16).map { i in SpatialAgent(projectID: "fixture", conversationID: "c", value: WorkspaceAgent(id: "a\(i)", name: "Agent", provider: "Codex", task: "Performance fixture", action: "Editing", status: .working, reportedStatus: "working", freshness: .live, observedAt: Date())) }
        let session = AppServerHistory.session(["id": "c", "cwd": "/tmp/inbox-fixture", "name": "Fixture", "threadSource": "user"], archived: false)!
        let world = SpatialWorld(projects: [.init(id: "fixture", name: "Fixture", teams: [.init(projectID: "fixture", session: session, agents: agents)])])
        let scene = SpatialSceneView()
        let model = ProjectInboxModel(store: store)
        let content = ZStack(alignment: .bottomTrailing) {
            InboxBenchmarkScene(view: scene)
            ProjectInboxView(model: model, project: "fixture", height: 460, expanded: .constant(true), selected: .constant(nil), reply: { _ in }, canReply: { _ in true })
                .frame(width: 400).padding(16)
        }.frame(width: 1080, height: 780)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1080, height: 780), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.title = "Diorama Inbox performance fixture"
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<30 where !window.occlusionState.contains(.visible) { try await Task.sleep(for: .milliseconds(100)) }
        defer { scene.frameObserved = nil; scene.tearDown(); window.close() }
        scene.apply(world: world, focus: .project("fixture"), active: true, reducedMotion: false, reset: 1)
        await scene.meadow.settle()
        try await Task.sleep(for: .seconds(4))
        func scrollView(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.hasVerticalScroller { return scroll }
            for child in view.subviews { if let found = scrollView(child) { return found } }
            return nil
        }
        let scroll = try #require(scrollView(host))
        let start = CACurrentMediaTime()
        scene.frameTelemetry.reset()
        scene.frameObserved = { [weak scroll] now in
            guard let scroll, let document = scroll.documentView else { return }
            let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
            let cycle = (now - start).truncatingRemainder(dividingBy: 12) / 12
            let fraction = cycle < 0.8 ? cycle / 0.8 : 1 - (cycle - 0.8) / 0.2
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * fraction))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        var visible = true
        for _ in 0..<300 {
            try await Task.sleep(for: .milliseconds(100))
            visible = visible && window.occlusionState.contains(.visible)
        }
        scene.frameObserved = nil
        let intervals = scene.frameTelemetry.snapshot().intervals.sorted()
        let p95 = intervals.isEmpty ? 0 : intervals[Int(Double(intervals.count - 1) * 0.95)] * 1000
        let report = "visible=\(visible); backing=\(scene.convertToBacking(scene.bounds).size); frames=\(intervals.count); p95=\(p95)ms; >33ms=\(intervals.filter { $0 > 0.033 }.count); target=\(scene.preferredFramesPerSecond); PASS=\(visible && !intervals.isEmpty && p95 <= 17.5)\n"
        try report.write(toFile: "/tmp/diorama-inbox-native-performance.txt", atomically: true, encoding: .utf8)
        print(report)
        #expect(visible && !intervals.isEmpty)
        // Timing is reported separately so unsupported/occluded display environments
        // cannot be mistaken for evidence that the acceptance target was met.
    }
}

private struct InboxBenchmarkScene: NSViewRepresentable {
    let view: SpatialSceneView
    func makeNSView(context: Context) -> SpatialSceneView { view }
    func updateNSView(_ view: SpatialSceneView, context: Context) {}
}
