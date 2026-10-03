import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ProjectTabTests {
    @Test func pickerUsesHomeRecentsOrderingAndExcludesUnopenedProjects() {
        struct Project: Identifiable { let id: String }
        let store = ProjectTabStore()
        store.select(.project("b"), openedAt: Date(timeIntervalSince1970: 20))
        store.select(.project("a"), openedAt: Date(timeIntervalSince1970: 20))
        store.select(.project("c"), openedAt: Date(timeIntervalSince1970: 30))
        let values = ["a", "unopened", "b", "c"].map { Project(id: $0) }
        #expect(store.recentProjects(values).map(\.id) == ["c", "a", "b"])
        let restored = ProjectTabStore(data: store.encoded())
        #expect(restored.recentProjects(values).map(\.id) == ["c", "a", "b"])
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "desktop-tabs-" + UUID().uuidString)! }
    @Test func orderedTabsDeduplicateCloseAndRestore() {
        let store = ProjectTabStore()
        #expect(store.selected == .home)
        #expect(store.home.section == .all)
        store.select(.project("a")); store.select(.project("b")); store.select(.project("c"))
        store.select(.project("a")); #expect(store.projects == ["a", "b", "c"])
        store.close("b"); #expect(store.selected == .project("a"))
        store.select(.project("c")); store.close("c"); #expect(store.selected == .project("a"))
        store.select(.project("b")); store.move("b", before: "a")
        #expect(store.projects == ["b", "a"])
        store.home.query = "needle"; store.home.list = true; store.home.scrollID = "a"
        store.cameras["a"] = SpatialCameraPose(x: 14, scale: 15)
        let restored = ProjectTabStore(data: store.encoded())
        #expect(restored.projects == store.projects); #expect(restored.selected == store.selected)
        #expect(restored.home == store.home); #expect(restored.cameras == store.cameras)
        store.close("b"); #expect(store.selected == .home)
    }
    @Test func shortcutsRecentsAndMigration() {
        let store = ProjectTabStore(migration: .project("p", "c"))
        #expect(store.selected == .project("p")); #expect(store.workspaces["p"]?.focus.conversationID == "c")
        #expect(store.tab(at: 0) == .home); #expect(store.tab(at: 1) == .project("p")); #expect(store.tab(at: 2) == nil)
        #expect(store.adjacent(1) == .home); #expect(store.adjacent(-1) == .home)
        let now = Date(timeIntervalSince1970: 100)
        store.select(.project("p"), openedAt: now); store.select(.home); store.select(.project("p"))
        #expect(store.lastOpened["p"] == now)
        let imported = ProjectTabStore(migration: .imported("thread"))
        #expect(imported.projects.isEmpty); #expect(imported.home.section == .imported)
        #expect(imported.home.importedSession == "thread")
    }
    private func model() -> LibraryModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json")
        let projects = ProjectModel(storageURL: url)
        projects.projects = (0..<20).map { n in
            var value = DioramaProject(name: "Project \(n)", folder: "/fixture/\(n)", commonDirectory: "", base: "", remote: nil)
            value.id = "p\(n)"; return value
        }
        return LibraryModel(projects: projects, navigation: WorkspaceNavigation(defaults: defaults()))
    }
    @Test func windowSelectionsAreIndependentWhileExecutionAndDraftsAreShared() {
        let owner = model()
        let first = LibraryModel(navigation: WorkspaceNavigation(defaults: defaults()), sharedOwner: owner)
        let second = LibraryModel(navigation: WorkspaceNavigation(defaults: defaults()), sharedOwner: owner)
        first.navigate(.project("p0", "one")); second.navigate(.project("p0", "two"))
        #expect(first.projects.selected?.selectedSession == "one")
        #expect(second.projects.selected?.selectedSession == "two")
        #expect(first.execution === second.execution)
        #expect(first.library === second.library)
        #expect(first.projectInbox === second.projectInbox)
        first.drafts["one"] = ConversationDraft(); first.drafts["one"]?.text = "Keep this"
        #expect(second.drafts["one"]?.text == "Keep this")
        first.projects.update("p0") { $0.name = "Renamed"; $0.fileSelection = "a.swift" }
        #expect(second.projects.selected?.name == "Renamed")
        #expect(second.projects.selected?.fileSelection == nil)
        first.closeProjectTab("p0")
        #expect(first.navigation.projectTabs.selected == .home)
        #expect(second.navigation.projectTabs.selected == .project("p0"))
        #expect(second.selectedID == "two")
        #expect(first.drafts["one"]?.text == "Keep this")
    }
    @Test func restoringWorkspaceDoesNotLoseDocumentsCameraOrConversation() {
        let library = model()
        library.navigate(.project("p0", "thread"))
        library.spatial.focus = .agent(project: "p0", conversation: "thread", agent: "avatar", expanded: false)
        library.spatial.conversationPanelVisible = true
        library.navigation.layout.inspectorWidth = 420
        library.navigation.projectTabs.cameras["p0"] = SpatialCameraPose(x: 8, z: 9, scale: 16)
        let document = WorkspaceDocument(folder: "/fixture/0", path: "README.md")
        library.navigation.open(document, key: "p0:thread")
        library.selectProjectTab("p1"); library.selectProjectTab("p0")
        #expect(library.selectedID == "thread")
        #expect(library.spatial.focus.agentID == "avatar")
        #expect(library.spatial.conversationPanelVisible)
        #expect(library.navigation.layout.inspectorWidth == 420)
        #expect(library.navigation.tabs["p0:thread"] == .document(document))
        library.closeProjectTab("p0"); library.selectProjectTab("p0")
        #expect(library.spatial.focus.agentID == "avatar")
        #expect(library.navigation.projectTabs.cameras["p0"]?.x == 8)
    }
    @Test func namespacePersistenceAndMissingProjects() {
        let storage = defaults()
        let a = WorkspaceNavigation(defaults: storage, namespace: "window.1")
        let b = WorkspaceNavigation(defaults: storage, namespace: "window.2")
        a.projectTabs.select(.project("missing")); a.flushPersistence(); b.flushPersistence()
        #expect(WorkspaceNavigation(defaults: storage, namespace: "window.1").projectTabs.selected == .project("missing"))
        #expect(WorkspaceNavigation(defaults: storage, namespace: "window.2").projectTabs.selected == .home)
        let library = model(); library.selectProjectTab("missing")
        #expect(library.navigation.projectTabs.selected == .project("missing"))
        #expect(library.projects.selectedID == "missing")
    }
    @Test func rapidSwitchingTwentyTabsStoresOnlyPresentationAndNeverTouchesTasks() {
        let library = model()
        let task = ExecutedTask(id: "running", title: "Keep running", folder: "/fixture/0", turnID: "turn", attached: true)
        library.execution.tasks[task.id] = task
        let before = library.execution.tasks[task.id]?.phase
        for i in 0..<20 { library.selectProjectTab("p\(i)") }
        let clock = ContinuousClock(); let start = clock.now
        for i in 0..<1000 { library.selectDesktopTab(.project("p\(i % 20)")) }
        let elapsed = start.duration(to: clock.now)
        print("Desktop tab model: 1000 switches / 20 tabs: \(elapsed); persisted bytes: \(library.navigation.projectTabs.encoded()?.count ?? 0)")
        #expect(library.navigation.projectTabs.projects.count == 20)
        #expect(library.navigation.projectTabs.workspaces.count == 20)
        #expect(library.execution.tasks[task.id]?.phase == before)
        #expect(library.execution.tasks[task.id]?.attached == true)
        for i in 0..<20 { library.closeProjectTab("p\(i)") }
        #expect(library.execution.tasks[task.id]?.attached == true)
        #expect(library.navigation.projectTabs.selected == .home)
    }
}

@MainActor struct DesktopShellRenderingTests {
    @Test func homeThemesAndOneRendererDuringTwentyTabSwitches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-render-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        projects.projects = (0..<20).map { index in
            var project = DioramaProject(name: index == 0 ? "Diorama" : "Project \(index)", folder: root.path, commonDirectory: "", base: "", remote: nil)
            project.id = "native-\(index)"; return project
        }
        let nav = WorkspaceNavigation(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = LibraryModel(execution: ExecutionController(transport: DesktopFixtureTransport()), projects: projects, navigation: nav)
        model.paused = true
        for n in 0..<20 {
            var task = ExecutedTask(id: "fixture-\(n)", title: "Task \(n)", folder: root.path, turnID: "turn", attached: true)
            task.transcript.entries = (0..<1000).map { Entry(id: "\(n)-\($0)", kind: $0 % 2 == 0 ? "You" : "Assistant", text: String(repeating: "History fixture. ", count: 20), timestamp: nil) }
            model.execution.tasks[task.id] = task
            // Deliberately keep the office fixture empty: large histories must remain unhydrated.
            nav.projectTabs.select(.project("native-\(n)"))
        }
        nav.projectTabs.select(.home)
        let host = NSHostingView(rootView: WorkspaceShell(library: model) { Text("Connect project folder…") })
        host.frame = NSRect(x: 0, y: 0, width: 1320, height: 850)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func scenes(_ view: NSView) -> [SpatialSceneView] { (view as? SpatialSceneView).map { [$0] } ?? view.subviews.flatMap(scenes) }
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        let renderer = try #require(scenes(host).first)
        #expect(!renderer.isPlaying)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            host.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("home-\(name).png"))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-desktop-home-\(name).png"))
        }
        var intervals: [Double] = []
        var warmIntervals: [Double] = []
        for round in 0..<2 {
            for index in 0..<20 {
                let start = ContinuousClock.now
                model.selectDesktopTab(.project("native-\(index)"))
                try await Task.sleep(for: .milliseconds(20))
                host.layoutSubtreeIfNeeded()
                let elapsed = start.duration(to: .now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                intervals.append(seconds)
                if round == 1 { warmIntervals.append(seconds) }
                if seconds > 0.05 { print("Desktop slow switch: round \(round), project \(index), \(seconds)s") }
                #expect(scenes(host).count == 1)
                #expect(scenes(host).first === renderer)
                #expect(model.transcript.entries.isEmpty)
            }
            print("Desktop native switch round \(round): 20 tabs; resident bytes \(desktopResidentBytes())")
        }
        let officePose = renderer.pose
        let homeStart = ContinuousClock.now
        model.selectDesktopTab(.home)
        host.layoutSubtreeIfNeeded()
        let homeElapsed = homeStart.duration(to: .now).components
        print("Desktop warm Home synchronous switch/layout: \(Double(homeElapsed.seconds) + Double(homeElapsed.attoseconds) / 1e18)s")
        try await Task.sleep(for: .milliseconds(100))
        #expect(!renderer.isPlaying)
        #expect(renderer.pose == officePose, "Home must not reframe the hidden office camera")
        let warm = warmIntervals.sorted()
        print("Desktop return-to-open-project: p50=\(warm[warm.count/2])s p95=\(warm[Int(Double(warm.count)*0.95)])s max=\(warm.last!)s (includes 20ms scheduling wait)")
        let sorted = intervals.sorted()
        print("Desktop native switch-to-layout (includes 20ms scheduler wait), 20 tabs / 20000 stored messages, p50=\(sorted[sorted.count / 2])s, p95=\(sorted[Int(Double(sorted.count) * 0.95)])s, max=\(sorted.last!)s; backingScale=\(window.backingScaleFactor)")
        #expect(model.execution.tasks.count == 20)
        window.orderOut(nil)
    }
}

private actor DesktopFixtureTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue> = AsyncStream { $0.finish() }
    func connect() {}
    func request(_ method: String, _ params: WireValue) throws -> WireValue { throw AppServerFailure("No provider calls permitted in desktop shell fixture: " + method) }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}

import SwiftUI
import Darwin
private func desktopResidentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

extension ProjectTabTests {
    @Test func panelBookmarksAndHistorySurviveRelaunchWithoutKeepingViews() {
        let library = model()
        library.navigate(.project("p0", "thread"))
        library.spatial.inboxExpanded = true
        library.spatial.conversationWidth = 530
        library.spatial.roster(for: "p0").collapsed = true
        let anchor = ConversationViewportAnchor(id: "message-50", offset: -12)
        library.navigation.projectTabs.conversationBookmarks["thread"] = ConversationViewBookmark(followsLatest: false, anchor: anchor, oldestID: "message-1", window: 200, entryLimit: 600)
        library.navigation.projectTabs.inboxBookmarks["p0"] = InboxViewBookmark(filter: "Archived", listAnchor: anchor)
        library.selectProjectTab("p1"); library.selectProjectTab("p0")
        #expect(library.spatial.inboxExpanded)
        #expect(library.spatial.conversationWidth == 530)
        #expect(library.spatial.roster(for: "p0").collapsed)
        #expect(library.entryLimit == 600)
        library.captureProjectPresentation()
        let restored = ProjectTabStore(data: library.navigation.projectTabs.encoded())
        #expect(restored.conversationBookmarks["thread"]?.anchor == anchor)
        #expect(restored.inboxBookmarks["p0"]?.filter == "Archived")
        #expect(restored.workspaces["p0"]?.panels?.inboxExpanded == true)
    }
}

extension DesktopShellRenderingTests {
    @Test func remountRestoresHistoryAnchorInsteadOfJumpingToBottom() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nav = WorkspaceNavigation(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = LibraryModel(execution: ExecutionController(transport: DesktopFixtureTransport()), projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), navigation: nav)
        var task = ExecutedTask(id: "restore", title: "Restore", folder: root.path, turnID: "t", attached: true)
        task.phase = .finished
        task.transcript.entries = (0..<60).map { Entry(id: "r-\($0)", kind: "Assistant", text: "Message \($0). " + String(repeating: "Saved conversation. ", count: 15), timestamp: nil) }
        model.execution.tasks[task.id] = task; model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        func content() -> AnyView { AnyView(SessionView(session: task.session, model: model, hasLocalReview: true, embeddedWorkScreen: true).environment(\.avatarMessages, true)) }
        let host = NSHostingView(rootView: content())
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 750)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        func settle() async throws { for _ in 0..<5 { try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded() } }
        func scrolls(_ view: NSView) -> [NSScrollView] { (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls) }
        try await settle()
        let original = try #require(scrolls(host).max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) })
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: original)
        original.contentView.scroll(to: NSPoint(x: 0, y: 700))
        original.reflectScrolledClipView(original.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: original)
        try await settle()
        let saved = try #require(nav.projectTabs.conversationBookmarks[task.session.id])
        #expect(!saved.followsLatest)
        #expect(saved.anchor != nil)
        host.rootView = AnyView(Color.clear)
        try await settle()
        host.rootView = content()
        try await settle()
        let restored = try #require(scrolls(host).max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) })
        #expect(abs(restored.contentView.bounds.minY - 700) < 30, "History should restore its visible row and offset, actual \(restored.contentView.bounds.minY)")
    }
}


extension DesktopShellRenderingTests {
    @Test func assetPreparationKeepsOnlyTheLatestProjectRequest() async throws {
        let scene = SpatialSceneView()
        let world = SpatialWorld(projects: [SpatialProject(id: "a", name: "A", teams: []), SpatialProject(id: "b", name: "B", teams: [])])
        scene.applyWhenPrepared(world: world, focus: .project("a"), active: false, reducedMotion: true, reset: 0, page: 0)
        scene.applyWhenPrepared(world: world, focus: .project("b"), active: false, reducedMotion: true, reset: 0, page: 0)
        await OfficeAssetPreparation.ready.value
        try await Task.sleep(for: .milliseconds(50))
        #expect(scene.officeLayouts["a"] == nil)
        #expect(scene.officeLayouts["b"] != nil)
        scene.tearDown()
    }
}

extension DesktopShellRenderingTests {
    @Test func populatedProjectSwitchTiming() async throws {
        await OfficeAssetPreparation.ready.value
        let scene = SpatialSceneView()
        scene.frame = NSRect(x: 0, y: 0, width: 1320, height: 850)
        defer { scene.tearDown() }
        let now = Date()
        let projects = (0..<2).map { p in
            let id = "populated-\(p)"
            let session = Session(id: id, provider: .codex, url: nil, sessionID: id, title: "Populated office", project: "/fixture/\(id)", modified: now, bytes: 0, archived: false, parentID: nil, classification: .conversation)
            let agents = (0..<34).map { n in
                SpatialAgent(projectID: id, conversationID: id, value: WorkspaceAgent(id: "\(id)-\(n)", name: "Agent \(n)", provider: "Codex", task: "Build offline support", action: "Editing", status: n < 16 ? .working : .done, reportedStatus: n < 16 ? "working" : "done", freshness: .live, observedAt: now))
            }
            return SpatialProject(id: id, name: id, teams: [SpatialTeam(projectID: id, session: session, agents: agents)])
        }
        let world = SpatialWorld(projects: projects)
        var durations: [Double] = []
        var originalNodes: Set<ObjectIdentifier>?
        for n in 0..<12 {
            let start = ContinuousClock.now
            scene.apply(world: world, focus: .project(projects[n % 2].id), active: false, reducedMotion: true, reset: 0)
            let duration = start.duration(to: .now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            print("Populated project switch \(n): \(seconds)s; avatars \(scene.officeWorkstations.count)")
            if n >= 2 { durations.append(seconds) }
            #expect(scene.officeWorkstations.count == 34)
            let nodes = Set(scene.officeWorkstations.values.map(ObjectIdentifier.init))
            if let originalNodes { #expect(nodes == originalNodes, "Project switching must reuse the bounded avatar pool") }
            else { originalNodes = nodes }
            for (id, station) in scene.officeWorkstations {
                #expect(station.person.name == "agent:" + id)
                #expect(station.monitor.name == "screen:" + id)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let values = durations.sorted()
        print("Populated 34-avatar warm reconciliation: p50=\(values[values.count/2])s max=\(values.last!)s")
    }
}
