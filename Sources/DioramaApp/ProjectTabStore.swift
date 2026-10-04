import SwiftUI
import Observation
import DioramaCore

/// The outer shell is deliberately independent of conversation/document WorkspaceTab.
enum DesktopTab: Codable, Equatable { case home, project(String) }
enum HomeSection: String, Codable, CaseIterable {
    case recents = "Recents", all = "All projects", search = "Search", attention = "Attention", imported = "Imported Activity"
    var icon: String {
        switch self { case .recents: "clock"; case .all: "square.grid.2x2"; case .search: "magnifyingglass"; case .attention: "bell"; case .imported: "tray.full" }
    }
}
struct DesktopHomeState: Codable, Equatable {
    var section: HomeSection = .all
    var query = ""
    var list = false
    var scrollID: String?
    var importedSession: String?
}
struct ProjectPresentationSnapshot: Codable, Equatable {
    var focus: SpatialFocus
    var selection: ProjectViewSelection?
    var conversationVisible = false
    var sidebarVisible = true
    var sidebarWidth = 240.0
    var inspectorVisible = true
    var inspectorWidth = 340.0
    var viewMode = "Workspace"
    var showArchived = false
    var page = 0
    var panels: OfficePanelBookmark?
    var conversationWidth: Double?
}
struct OfficePanelBookmark: Codable, Equatable {
    var inboxExpanded = false
    var serversExpanded = false
    var selectedInbox: String?
    var rosterCollapsed = false
    var rosterRecentExpanded = false
}
struct InboxViewBookmark: Codable, Equatable {
    var filter = "Inbox"
    var listAnchor: ConversationViewportAnchor?
    var detailAnchor: ConversationViewportAnchor?
}

struct ConversationViewBookmark: Codable, Equatable {
    var followsLatest: Bool
    var anchor: ConversationViewportAnchor?
    var oldestID: String?
    var window: Int
    var entryLimit: Int
}
private struct DesktopTabPersistence: Codable {
    var projects: [String] = []
    var selected: DesktopTab = .home
    var home = DesktopHomeState()
    var lastOpened: [String: Date] = [:]
    var workspaces: [String: ProjectPresentationSnapshot] = [:]
    var cameras: [String: SpatialCameraPose] = [:]
    var historyAnchors: [String: String] = [:]
    var inboxBookmarks: [String: InboxViewBookmark]?
    var conversationBookmarks: [String: ConversationViewBookmark]?
}
@Observable final class ProjectTabStore {
    private(set) var projects: [String] = []
    private(set) var selected: DesktopTab = .home
    var home = DesktopHomeState() { didSet { changed?() } }
    private(set) var lastOpened: [String: Date] = [:]
    var workspaces: [String: ProjectPresentationSnapshot] = [:] { didSet { changed?() } }
    @ObservationIgnored var cameras: [String: SpatialCameraPose] = [:] { didSet { changed?() } }
    var historyAnchors: [String: String] = [:] { didSet { changed?() } }
    var inboxBookmarks: [String: InboxViewBookmark] = [:] { didSet { changed?() } }
    var conversationBookmarks: [String: ConversationViewBookmark] = [:] { didSet { changed?() } }
    var pickerPresented = false
    private(set) var generation: UInt64 = 0
    @ObservationIgnored var changed: (() -> Void)?
    init(data: Data? = nil, migration: WorkspaceDestination = .home) {
        if let data, let saved = try? JSONDecoder().decode(DesktopTabPersistence.self, from: data) {
            var seen = Set<String>()
            projects = saved.projects.filter { !$0.isEmpty && seen.insert($0).inserted }
            selected = saved.selected; home = saved.home; lastOpened = saved.lastOpened
            workspaces = saved.workspaces; cameras = saved.cameras; historyAnchors = saved.historyAnchors; inboxBookmarks = saved.inboxBookmarks ?? [:]; conversationBookmarks = saved.conversationBookmarks ?? [:]
            if case .project(let id) = selected, !projects.contains(id) { selected = .home }
        } else {
            switch migration {
            case .project(let id, let session):
                projects = [id]; selected = .project(id)
                workspaces[id] = ProjectPresentationSnapshot(focus: session.map { .team(project: id, conversation: $0) } ?? .project(id))
            case .imported(let session): home.section = .imported; home.importedSession = session
            case .home: break
            }
        }
    }
    func recentProjects<Project: Identifiable>(_ values: [Project]) -> [Project] where Project.ID == String {
        values.filter { lastOpened[$0.id] != nil }.sorted {
            let a = lastOpened[$0.id] ?? .distantPast, b = lastOpened[$1.id] ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
    }
    func encoded() -> Data? {
        try? JSONEncoder().encode(DesktopTabPersistence(projects: projects, selected: selected, home: home,
            lastOpened: lastOpened, workspaces: workspaces, cameras: cameras, historyAnchors: historyAnchors, inboxBookmarks: inboxBookmarks, conversationBookmarks: conversationBookmarks))
    }
    func select(_ tab: DesktopTab, openedAt: Date? = nil) {
        if case .project(let id) = tab {
            if !projects.contains(id) { projects.append(id) }
            if let openedAt { lastOpened[id] = openedAt }
        }
        if selected != tab { generation &+= 1; selected = tab }
        changed?()
    }
    func invalidatePresentation() { generation &+= 1 }
    func close(_ id: String) {
        guard let index = projects.firstIndex(of: id) else { return }
        if selected == .project(id) { select(index == 0 ? .home : .project(projects[index - 1])) }
        projects.remove(at: index); changed?()
    }
    func move(_ id: String, before destination: String) {
        guard id != destination, projects.contains(id), projects.contains(destination) else { return }
        projects.removeAll { $0 == id }
        projects.insert(id, at: projects.firstIndex(of: destination)!)
        changed?()
    }
    func tab(at index: Int) -> DesktopTab? {
        if index == 0 { return .home }
        guard projects.indices.contains(index - 1) else { return nil }
        return .project(projects[index - 1])
    }
    func adjacent(_ delta: Int) -> DesktopTab {
        let index: Int
        if case .project(let id) = selected { index = (projects.firstIndex(of: id) ?? -1) + 1 } else { index = 0 }
        let count = projects.count + 1
        return tab(at: (index + delta + count) % count) ?? .home
    }
}

extension LibraryModel {
    func captureProjectPresentation() {
        guard case .project(let id) = navigation.projectTabs.selected, projects.selectedID == id else { return }
        let layout = navigation.layout
        navigation.projectTabs.workspaces[id] = ProjectPresentationSnapshot(focus: spatial.focus,
            selection: projects.selected.map(ProjectViewSelection.init), conversationVisible: spatial.conversationPanelVisible,
            sidebarVisible: layout.sidebarVisible, sidebarWidth: layout.sidebarWidth,
            inspectorVisible: layout.inspectorVisible, inspectorWidth: layout.inspectorWidth,
            viewMode: viewMode.rawValue, showArchived: spatial.showArchived, page: spatial.page,
            panels: OfficePanelBookmark(inboxExpanded: spatial.inboxExpanded, serversExpanded: spatial.serversExpanded, selectedInbox: spatial.inboxSelection?.id,
                rosterCollapsed: spatial.roster(for: id).collapsed, rosterRecentExpanded: spatial.roster(for: id).recentExpanded),
            conversationWidth: spatial.conversationWidth)
        navigation.projectTabs.historyAnchors = scrollPositions
    }
    func selectProjectTab(_ id: String) { selectDesktopTab(.project(id), userOpened: true) }
    func selectDesktopTab(_ tab: DesktopTab, userOpened: Bool = false) {
        navigation.projectTabs.pickerPresented = false
        if navigation.projectTabs.selected == tab, projects.selectedID != nil {
            if userOpened { navigation.projectTabs.select(tab, openedAt: Date()) }
            return
        }
        captureProjectPresentation()
        navigation.projectTabs.select(tab, openedAt: userOpened ? Date() : nil)
        navigation.projectTabs.pickerPresented = false
        spatial.notice = nil
        spatial.inboxExpanded = false; spatial.serversExpanded = false; spatial.inboxSelection = nil
        switch tab {
        case .home:
            projects.selectedID = nil; selectedID = nil; spatial.focus = .portfolio
            spatial.conversationPanelVisible = false; viewMode = .workspace
            if navigation.projectTabs.home.section == .imported {
                projects.selectedID = "imported"; selectedID = navigation.projectTabs.home.importedSession
                viewMode = .conversation
            }
            navigation.visit(.home)
        case .project(let id):
            projects.selectedID = id
            if let saved = navigation.projectTabs.workspaces[id] {
                if let selection = saved.selection { projects.presentation[id] = selection }
                spatial.focus = saved.focus
                selectedID = saved.focus.conversationID ?? saved.selection?.session
                spatial.conversationPanelVisible = saved.conversationVisible
                spatial.conversationWidth = saved.conversationWidth
                spatial.showArchived = saved.showArchived; spatial.page = saved.page
                if let panels = saved.panels {
                    spatial.inboxExpanded = panels.inboxExpanded; spatial.serversExpanded = panels.serversExpanded
                    spatial.roster(for: id).collapsed = panels.rosterCollapsed
                    spatial.roster(for: id).recentExpanded = panels.rosterRecentExpanded
                    if let threadID = panels.selectedInbox {
                        let generation = navigation.projectTabs.generation
                        Task {
                            let thread = try? await projectInbox.store.summaries([threadID])[threadID]
                            guard navigation.projectTabs.generation == generation, projects.selectedID == id else { return }
                            spatial.inboxSelection = thread
                        }
                    }
                }
                navigation.layout.sidebarVisible = saved.sidebarVisible; navigation.layout.sidebarWidth = saved.sidebarWidth
                navigation.layout.inspectorVisible = saved.inspectorVisible; navigation.layout.inspectorWidth = saved.inspectorWidth
                viewMode = ConversationViewMode(rawValue: saved.viewMode) ?? .workspace
            } else {
                selectedID = projects.selected?.selectedSession
                spatial.focus = .project(id); spatial.conversationPanelVisible = false; spatial.page = 0; viewMode = .workspace
            }
            navigation.visit(.project(id, selectedID))
        }
        projectNavigation = projects.selectedID != "imported"
        entryLimit = selectedID.flatMap { navigation.projectTabs.conversationBookmarks[$0]?.entryLimit } ?? 300
        // Selection restores its last snapshot immediately; readSelected refreshes it.
    }
    func closeProjectTab(_ id: String) {
        captureProjectPresentation()
        let wasSelected = navigation.projectTabs.selected == .project(id)
        navigation.projectTabs.close(id)
        if wasSelected {
            // The store has already selected the left neighbor. Clear the outgoing project
            // so restoration cannot mistake this for a repeated selection.
            projects.selectedID = nil
            restoreDesktopSelection()
        }
    }
    func restoreDesktopSelection() {
        let tab = navigation.projectTabs.selected
        let saved = navigation.projectTabs.workspaces
        // Avoid capturing outgoing presentation under the newly selected identity.
        projects.selectedID = nil
        switch tab {
        case .home: spatial.focus = .portfolio
        case .project(let id): spatial.focus = saved[id]?.focus ?? .project(id)
        }
        restoreSelectionWithoutCapture(tab)
    }
    private func restoreSelectionWithoutCapture(_ tab: DesktopTab) {
        // selectDesktopTab captures only when the displayed project matches the selected tab.
        selectDesktopTab(tab)
    }
}
