import AppKit
import SwiftUI
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct LiveAgentRosterTests {
    private func agent(_ id: String, time: Double? = nil, event: String = "start", status: WorkspaceAgentStatus = .working) -> SpatialAgent {
        var value = WorkspaceAgent(id: id, name: "Milo", provider: Provider.codex.rawValue, task: "Inspect a long task title and preserve actual worktree membership", action: "Editing", status: status, reportedStatus: status.rawValue, freshness: .live)
        value.meaningfulEventID = event
        value.meaningfulUpdatedAt = time.map(Date.init(timeIntervalSince1970:))
        value.latestActivity = "Updated the conversation history renderer."
        value.branch = "fix-scrolling"; value.worktree = "/tmp/shared-worktree"
        return SpatialAgent(projectID: "fixture", conversationID: "c", value: value)
    }
    @Test func hookReplayUUIDAndObservationTimeAreNotMeaningfulUpdates() {
        var a = ActivityEvent(id: "read-one", provider: Provider.codex.rawValue, sessionID: "session", kind: "toolStarted", source: "Hook", recordedAt: Date(timeIntervalSince1970: 1), observedAt: Date(timeIntervalSince1970: 2), tool: "Read", detail: "README.md")
        let first = WorkspaceAgentPresentation.activityIdentity(a)
        a.id = "read-two"; a.observedAt = Date(timeIntervalSince1970: 3)
        #expect(WorkspaceAgentPresentation.activityIdentity(a) == first)
        a.detail = "Package.swift"
        #expect(WorkspaceAgentPresentation.activityIdentity(a) != first)
        var row = AgentRosterRow(agent: agent("main"), updated: Date())
        row.agent.value.task = "Fix the website<diorama_html_view>Private context"
        #expect(row.taskTitle == "Fix the website")
    }
    @Test func recencyDoesNotAdvanceForObservationsReplayOrLateEvents() {
        var reducer = AgentRosterReducer()
        var a = agent("a", time: 10), b = agent("b", time: 20)
        reducer.ingest([a, b], received: Date(timeIntervalSince1970: 100))
        #expect(reducer.ordered.map(\.id) == [b.id, a.id])
        a.value.freshness = .lastKnown
        reducer.ingest([a, b], received: Date(timeIntervalSince1970: 200))
        #expect(reducer.ordered.last?.updated == Date(timeIntervalSince1970: 10))
        a = agent("a", time: 30, event: "next")
        reducer.ingest([a, b], received: Date(timeIntervalSince1970: 300))
        #expect(reducer.ordered.first?.id == a.id)
        reducer.ingest([agent("a", time: 5, event: "late"), b], received: Date(timeIntervalSince1970: 400))
        #expect(reducer.ordered.first?.agent.value.meaningfulEventID == "next")
        reducer.ingest([agent("a", time: 10), b], received: Date(timeIntervalSince1970: 500))
        #expect(reducer.ordered.first?.updated == Date(timeIntervalSince1970: 30))
    }
    @Test func liveApprovalIsNotHiddenByAnOlderToolTimestamp() {
        var reducer = AgentRosterReducer()
        reducer.ingest([agent("a", time: 100)], received: Date(timeIntervalSince1970: 100))
        var waiting = agent("a", time: 90, event: "older-tool", status: .waiting)
        waiting.value.attentionReason = .approval
        reducer.ingest([waiting], received: Date(timeIntervalSince1970: 101))
        #expect(reducer.ordered.first?.agent.needsAttention == true)
        #expect(reducer.ordered.first?.updated == Date(timeIntervalSince1970: 101))
    }
    @Test func untimestampedReceiptAndTerminalSectionsAreStable() {
        var reducer = AgentRosterReducer()
        let a = agent("a"), b = agent("b", status: .failed)
        reducer.ingest([a, b], received: Date(timeIntervalSince1970: 100))
        reducer.ingest([a, b], received: Date(timeIntervalSince1970: 200))
        #expect(reducer.ordered.allSatisfy { $0.updated == Date(timeIntervalSince1970: 100) })
        #expect(reducer.ordered.last?.recent == true)
        let finished = agent("a", event: "finished", status: .done)
        reducer.ingest([finished, b], received: Date(timeIntervalSince1970: 300))
        #expect(reducer.ordered.first?.id == a.id)
        let allRecent = reducer.ordered.allSatisfy { $0.recent }
        #expect(allRecent)
        #expect(reducer.ordered.first?.agent.value.latestActivity == finished.value.latestActivity)
    }
    @Test func identityMetadataAndRoutingDoNotConflateSharedFolders() {
        let a = agent("a"), b = agent("b")
        #expect(a.id != b.id)
        #expect(a.value.worktree == b.value.worktree && a.value.branch == b.value.branch)
        #expect(AgentRosterRow(agent: b, updated: Date()).destination == .agent(project: "fixture", conversation: "c", agent: b.id, expanded: true))
        var child = b; child.value.branch = nil; child.value.worktree = nil; child.value.parentName = "Ada"
        #expect(child.value.branch == nil && child.value.worktree == nil)
        #expect(child.value.parentName == "Ada")
    }
    @Test func burstsCoalesceAndPressedTargetsStayStable() async throws {
        let model = LiveAgentRosterModel()
        model.ingest([agent("a", time: 1), agent("b", time: 2)])
        model.flushForTesting()
        model.setPressed(true)
        model.ingest([agent("a", time: 5, event: "changed"), agent("b", time: 2)])
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.rows.first?.agent.value.id == "b")
        model.setPressed(false)
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.rows.first?.agent.value.id == "a")
        let before = model.publicationCount
        for i in 0..<64 { model.ingest([agent("a", time: Double(10 + i), event: "event-\(i)")]) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.publicationCount - before == 1)
        #expect(model.rows.first?.agent.value.meaningfulEventID == "event-63")
        model.setActive(false)
        model.ingest([agent("a", time: 100, event: "hidden")])
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.rows.first?.agent.value.meaningfulEventID == "event-63")
    }
    @Test func nativeRowsPreserveExactAnchorAndSelection() throws {
        let model = LiveAgentRosterModel()
        var agents = (0..<64).map { agent("a\($0)", time: Double($0)) }
        model.ingest(agents); model.flushForTesting()
        let parent = LiveAgentRosterTable(model: model, animate: false, paused: false, recentExpanded: false, jumpRevision: 0, open: { _ in })
        let coordinator = LiveAgentRosterTable.Coordinator(parent)
        let table = LiveAgentRosterTable.RosterTable(frame: NSRect(x: 0, y: 0, width: 300, height: 12000))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        table.addTableColumn(NSTableColumn(identifier: .init("agent")))
        table.headerView = nil; table.intercellSpacing = .zero
        table.delegate = coordinator; table.dataSource = coordinator
        scroll.documentView = table; coordinator.table = table; coordinator.scroll = scroll
        coordinator.update(parent)
        table.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1500))
        table.selectRowIndexes(IndexSet(integer: 12), byExtendingSelection: false)
        let selected = coordinator.ids[12], anchor = try #require(coordinator.currentAnchor())
        agents[0] = agent("a0", time: 200, event: "new")
        model.ingest(agents); model.flushForTesting(); coordinator.update(parent)
        let restored = try #require(coordinator.currentAnchor())
        #expect(restored.id == anchor.id)
        #expect(abs(restored.offset - anchor.offset) < 1)
        #expect(coordinator.ids[table.selectedRow] == selected)
        coordinator.saveAnchor(); #expect(model.anchor == restored)
    }

    @Test func native64AgentBurstScrollingBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_ROSTER_BENCHMARK"] == "1" else { return }
        var agents = (0..<64).map { agent("a\($0)", time: Double($0)) }
        let session = try #require(AppServerHistory.session(["id": "c", "cwd": "/tmp/roster-fixture", "name": "Fixture", "threadSource": "user"], archived: false))
        let world = SpatialWorld(projects: [.init(id: "fixture", name: "Fixture", teams: [.init(projectID: "fixture", session: session, agents: agents)])])
        let scene = SpatialSceneView(), model = LiveAgentRosterModel()
        model.ingest(agents); model.flushForTesting()
        let content = HStack(spacing: 0) {
            LiveAgentRosterPanel(model: model, agents: agents, active: true, paused: false, open: { _ in }).frame(width: 300)
            RosterBenchmarkScene(view: scene)
        }.frame(width: 1200, height: 800)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.title = "Diorama live roster benchmark"
        NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
        defer { model.setActive(false); scene.frameObserved = nil; scene.tearDown(); window.close() }
        scene.apply(world: world, focus: .project("fixture"), active: true, reducedMotion: false, reset: 1)
        await scene.meadow.settle(); try await Task.sleep(for: .seconds(4))
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let scroll = try #require(find(host)), start = CACurrentMediaTime()
        scene.frameTelemetry.reset()
        scene.frameObserved = { [weak scroll] now in
            guard let scroll, let document = scroll.documentView else { return }
            let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
            let fraction = (now - start).truncatingRemainder(dividingBy: 8) / 8
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * fraction)); scroll.reflectScrolledClipView(scroll.contentView)
        }
        var visible = true
        for tick in 0..<300 {
            try await Task.sleep(for: .milliseconds(100))
            visible = visible && window.occlusionState.contains(.visible)
            for j in 0..<8 {
                let i = (tick * 8 + j) % 64
                agents[i].value.meaningfulEventID = "burst-\(tick)-\(j)"
                agents[i].value.meaningfulUpdatedAt = Date()
                agents[i].value.latestActivity = "Reported update \(tick) for agent \(i)"
            }
            model.ingest(agents)
        }
        scene.frameObserved = nil
        let intervals = scene.frameTelemetry.snapshot().intervals.sorted()
        let p95 = intervals.isEmpty ? 0 : intervals[Int(Double(intervals.count - 1) * 0.95)] * 1000
        let report = "visible=\(visible); backing=\(scene.convertToBacking(scene.bounds).size); frames=\(intervals.count); p95=\(p95)ms; >33ms=\(intervals.filter { $0 > 0.033 }.count); publications=\(model.publicationCount); PASS=\(visible && !intervals.isEmpty && p95 <= 17.5)\n"
        try report.write(toFile: "/tmp/diorama-roster-performance.txt", atomically: true, encoding: .utf8)
        print(report); #expect(visible && !intervals.isEmpty)
    }
}
private struct RosterBenchmarkScene: NSViewRepresentable {
    let view: SpatialSceneView
    func makeNSView(context: Context) -> SpatialSceneView { view }
    func updateNSView(_ view: SpatialSceneView, context: Context) {}
}
