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
        let restored = ProjectTabStore(data: store.encoded())
        #expect(restored.projects == store.projects); #expect(restored.selected == store.selected)
        #expect(restored.home == store.home)
        store.close("b"); #expect(store.selected == .home)
    }
    @Test func homeLayoutRestoresAndToleratesOlderSavedState() throws {
        var home = DesktopHomeState()
        home.layout = .city
        #expect(home.city && !home.list)
        let restored = try JSONDecoder().decode(DesktopHomeState.self, from: JSONEncoder().encode(home))
        #expect(restored.layout == .city)
        let legacy = try JSONDecoder().decode(DesktopHomeState.self, from: Data(#"{"section":"Recents","query":"x","list":true}"#.utf8))
        #expect(legacy.layout == .list); #expect(legacy.section == .recents); #expect(legacy.query == "x")
    }
    @Test func buildingSizeFollowsConversationsAndLogTokens() {
        let empty = PortfolioBuildingMetrics(conversations: 0, tokens: nil)
        #expect(empty == PortfolioBuildingMetrics(width: 2, depth: 2, floors: 2))
        #expect(PortfolioBuildingMetrics(conversations: 4, tokens: 1_000_000).floors == 5)
        // The skyline follows the tallest building present, never the theoretical maximum.
        let street = PortfolioBuilding.skyline([(id: "a", metrics: empty), (id: "b", metrics: empty)])
        #expect(street >= PortfolioBuilding.minimumSkyline)
        #expect(PortfolioBuilding.skyline([(id: "a", metrics: empty), (id: "t", metrics: .init(width: 4, depth: 4, floors: 9))]) > street)
        let huge = PortfolioBuildingMetrics(conversations: 500, tokens: 900_000_000_000)
        #expect(huge == PortfolioBuildingMetrics(width: 4, depth: 4, floors: PortfolioBuildingMetrics.maxFloors))
        #expect(PortfolioBuilding.hash("p", 3) == PortfolioBuilding.hash("p", 3))
        #expect(PortfolioBuildingStyle.lowRises.count == 12); #expect(PortfolioBuildingStyle.towers.count == 12)
        #expect(Set(PortfolioBuildingStyle.lowRises + PortfolioBuildingStyle.towers).count == PortfolioBuildingStyle.allCases.count)
        let low = PortfolioBuildingMetrics(width: 3, depth: 3, floors: 3), tower = PortfolioBuildingMetrics(width: 4, depth: 4, floors: 9)
        #expect(PortfolioBuildingStyle.lowRises.contains(.of(projectID: "p", metrics: low)))
        #expect(PortfolioBuildingStyle.towers.contains(.of(projectID: "p", metrics: tower)))
        #expect(PortfolioBuildingStyle.of(projectID: "p", metrics: tower) == PortfolioBuildingStyle.of(projectID: "p", metrics: tower))
        for style in PortfolioBuildingStyle.allCases {
            // Every silhouette fits the shared scale, including its roof and spire.
            #expect(PortfolioMassing(style, metrics: tower).extent <= PortfolioBuilding.maxExtent)
        }
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
    @Test func restoringWorkspaceDoesNotLoseDocumentsOrConversation() {
        let library = model()
        library.navigate(.project("p0", "thread"))
        library.spatial.focus = .agent(project: "p0", conversation: "thread", agent: "avatar", expanded: false)
        library.spatial.conversationPanelVisible = true
        library.navigation.layout.inspectorWidth = 420
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
    }
    @Test func removingAProjectClosesItsTabAndDropsItFromTheList() {
        let library = model()
        library.selectProjectTab("p1"); library.selectProjectTab("p2")
        library.removeProject("p2")
        #expect(!library.projects.projects.contains { $0.id == "p2" })
        #expect(!library.navigation.projectTabs.projects.contains("p2"))
        #expect(library.navigation.projectTabs.selected == .project("p1")) // The neighbouring tab.
        #expect(library.projects.selectedID != "p2")
        library.removeProject("p5") // Not open in a tab: just leaves the list.
        #expect(!library.projects.projects.contains { $0.id == "p5" })
        #expect(library.projects.projects.count == 18)
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
    @Test func remountOpensLatestInsteadOfRestoringHistoryAnchor() async throws {
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
        let document = try #require(restored.documentView)
        #expect(abs(document.bounds.maxY - restored.contentView.bounds.maxY) < 30,
                "Reopening should show the latest message even when an older reading bookmark exists")
    }
}


extension DesktopShellRenderingTests {
}

extension DesktopShellRenderingTests {
}
