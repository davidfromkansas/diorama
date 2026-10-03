import SwiftUI
import Observation
import DioramaCore

/// UI-only state. Provider identities and worktree lifecycle remain owned by the existing models.
enum WorkspaceDestination: Codable, Equatable {
    case home
    case imported(String?)
    case project(String, String?)
}
enum WorkspaceInspector: String, Codable, CaseIterable { case files = "Files", changes = "Changes", checks = "Checks" }
struct WorkspaceDocument: Codable, Hashable, Identifiable {
    let folder: String
    let path: String
    var revision: String? = nil
    var workspaceID: String? = nil
    var changeScope: String? = nil
    var id: String { [folder, path, revision ?? "working", workspaceID ?? "", changeScope ?? "file"].joined(separator: "\u{0}") }
    var title: String { URL(fileURLWithPath: path).lastPathComponent + (changeScope == nil ? "" : " · Diff") }
}
enum WorkspaceTab: Codable, Equatable {
    case workspace, conversation, activity, html, context, pullRequests, document(WorkspaceDocument)
    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .conversation: "Conversation"
        case .activity: "Activity"
        case .html: "HTML view"
        case .context: "Context"
        case .pullRequests: "Pull Requests"
        case .document(let document): document.title
        }
    }
}
private struct WorkspaceLayoutSnapshot: Codable, Equatable {
    var sidebarVisible = true
    var inspectorVisible = true
    var sidebarWidth = 240.0
    var inspectorWidth = 340.0
    var collapsedProjects: Set<String> = []
    var inspector: WorkspaceInspector = .changes
    var destination: WorkspaceDestination = .home
}

/// Observe each preference independently. A disclosure must not invalidate the pane layout.
@Observable final class WorkspaceLayout: Codable, Equatable {
    var sidebarVisible: Bool { didSet { changed?() } }
    var inspectorVisible: Bool { didSet { changed?() } }
    var sidebarWidth: Double { didSet { changed?() } }
    var inspectorWidth: Double { didSet { changed?() } }
    var collapsedProjects: Set<String> { didSet { changed?() } }
    var inspector: WorkspaceInspector { didSet { changed?() } }
    var destination: WorkspaceDestination { didSet { changed?() } }
    @ObservationIgnored var changed: (() -> Void)?
    private var snapshot: WorkspaceLayoutSnapshot {
        WorkspaceLayoutSnapshot(sidebarVisible: sidebarVisible, inspectorVisible: inspectorVisible,
            sidebarWidth: sidebarWidth, inspectorWidth: inspectorWidth, collapsedProjects: collapsedProjects,
            inspector: inspector, destination: destination)
    }
    private init(_ value: WorkspaceLayoutSnapshot) {
        sidebarVisible = value.sidebarVisible; inspectorVisible = value.inspectorVisible
        sidebarWidth = min(360, max(190, value.sidebarWidth)); inspectorWidth = min(560, max(280, value.inspectorWidth))
        collapsedProjects = value.collapsedProjects; inspector = value.inspector; destination = value.destination
    }
    convenience init() { self.init(WorkspaceLayoutSnapshot()) }
    required convenience init(from decoder: any Decoder) throws { self.init(try WorkspaceLayoutSnapshot(from: decoder)) }
    func encode(to encoder: any Encoder) throws { try snapshot.encode(to: encoder) }
    static func == (lhs: WorkspaceLayout, rhs: WorkspaceLayout) -> Bool { lhs.snapshot == rhs.snapshot }
}
@Observable final class WorkspaceNavigation {
    let layout: WorkspaceLayout
    let projectTabs: ProjectTabStore
    private let namespace: String
    var tabs: [String: WorkspaceTab] = [:] { didSet { schedulePersistence() } }
    var documents: [String: [WorkspaceDocument]] = [:] { didSet { schedulePersistence() } }
    var backStack: [WorkspaceDestination] = []
    var forwardStack: [WorkspaceDestination] = []
    var searchPresented = false
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var isRestoring = true
    private let defaults: UserDefaults
    let hadSavedLayout: Bool
    init(defaults: UserDefaults = .standard, namespace: String = "") {
        self.defaults = defaults
        self.namespace = namespace
        func key(_ value: String) -> String { namespace.isEmpty ? value : namespace + "." + value }
        let saved = (defaults.data(forKey: key("workspaceLayout.v1")) ?? (namespace == "window.1" ? defaults.data(forKey: "workspaceLayout.v1") : nil)).flatMap { try? JSONDecoder().decode(WorkspaceLayout.self, from: $0) }
        hadSavedLayout = saved != nil
        layout = saved ?? WorkspaceLayout()
        projectTabs = ProjectTabStore(data: defaults.data(forKey: key("projectTabs.v1")), migration: saved?.destination ?? .home)
        layout.sidebarWidth = min(360, max(190, layout.sidebarWidth))
        layout.inspectorWidth = min(560, max(280, layout.inspectorWidth))
        if let data = (defaults.data(forKey: key("workspaceTabs.v1")) ?? (namespace == "window.1" ? defaults.data(forKey: "workspaceTabs.v1") : nil)), let saved = try? JSONDecoder().decode([String: WorkspaceTab].self, from: data) { tabs = saved }
        if let data = (defaults.data(forKey: key("workspaceDocuments.v1")) ?? (namespace == "window.1" ? defaults.data(forKey: "workspaceDocuments.v1") : nil)), let saved = try? JSONDecoder().decode([String: [WorkspaceDocument]].self, from: data) { documents = saved }
        isRestoring = false
        projectTabs.changed = { [weak self] in self?.schedulePersistence() }
        layout.changed = { [weak self] in self?.schedulePersistence() }
    }
    private func schedulePersistence() {
        guard !isRestoring else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            self?.flushPersistence()
        }
    }
    func waitForPendingPersistence() async { await persistenceTask?.value }

    /// Flush on app termination and before an explicit restore. Normal clicks never encode or write preferences.
    func flushPersistence() {
        persistenceTask?.cancel(); persistenceTask = nil
        func key(_ value: String) -> String { namespace.isEmpty ? value : namespace + "." + value }
        if let data = projectTabs.encoded() { defaults.set(data, forKey: key("projectTabs.v1")) }
        if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: key("workspaceLayout.v1")) }
        if let data = try? JSONEncoder().encode(tabs) { defaults.set(data, forKey: key("workspaceTabs.v1")) }
        if let data = try? JSONEncoder().encode(documents) { defaults.set(data, forKey: key("workspaceDocuments.v1")) }
    }
    func visit(_ destination: WorkspaceDestination) {
        guard layout.destination != destination else { return }
        backStack.append(layout.destination); forwardStack = []; layout.destination = destination
    }
    func back() -> WorkspaceDestination? {
        guard let destination = backStack.popLast() else { return nil }
        forwardStack.append(layout.destination); layout.destination = destination; return destination
    }
    func forward() -> WorkspaceDestination? {
        guard let destination = forwardStack.popLast() else { return nil }
        backStack.append(layout.destination); layout.destination = destination; return destination
    }
    func open(_ document: WorkspaceDocument, key: String) {
        if !(documents[key] ?? []).contains(where: { $0.id == document.id }) { documents[key, default: []].append(document) }
        tabs[key] = .document(document)
    }
    func close(_ document: WorkspaceDocument, key: String) {
        documents[key]?.removeAll { $0.id == document.id }
        if tabs[key] == .document(document) { tabs[key] = .conversation }
    }
    static func inlineInspector(width: Double) -> Bool { width >= 1100 }
}
enum DioramaStyle {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .controlBackgroundColor)
    static let raised = Color(nsColor: .textBackgroundColor)
    static let selection = Color.primary.opacity(0.065)
    static let border = Color.primary.opacity(0.10)
    static let accent = Color(red: 0.69, green: 0.42, blue: 0.96)
}
struct WorkspaceTabButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? .primary : .secondary).padding(.horizontal, 12).frame(height: 38)
                .overlay(alignment: .bottom) { if selected { Rectangle().fill(DioramaStyle.accent).frame(height: 2) } }
                .contentShape(Rectangle())
        }.pointingHand().buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
extension LibraryModel {
    func navigate(_ destination: WorkspaceDestination, record: Bool = true) {
        switch destination {
        case .project(let id, _): if navigation.projectTabs.selected != .project(id) { selectProjectTab(id) }
        case .home: selectDesktopTab(.home); return
        case .imported(let session):
            if navigation.projectTabs.selected != .home { selectDesktopTab(.home) }
            navigation.projectTabs.home.section = .imported; navigation.projectTabs.home.importedSession = session
        }
        navigation.projectTabs.invalidatePresentation()
        if record { navigation.visit(destination) }
        viewMode = .workspace
        spatial.notice = nil
        spatial.page = 0
        switch destination {
        case .home: spatial.focus = .portfolio
        case .project(let id, let session): spatial.focus = session.map { .team(project: id, conversation: $0) } ?? .project(id)
        case .imported(let session): spatial.focus = session.map { .team(project: nil, conversation: $0) } ?? .portfolio
        }
        switch destination {
        case .home: projects.selectedID = nil; selectedID = nil
        case .imported(let session):
            projects.selectedID = "imported"
            selectedFolderID = sessions.first(where: { $0.id == session }).flatMap { WorkingFolder.group([$0]).first?.id }
            selectedID = session
        case .project(let id, let session):
            navigation.tabs[id + ":" + (session ?? "draft")] = .workspace
            projects.selectedID = id
            projects.update(id) {
                if $0.selectedSession != session { $0.fileLocation = nil; $0.fileSelection = nil }
                $0.selectedSession = session; if record { $0.section = "Sessions" }
            }
            selectedID = session
        }
        projectNavigation = projects.selectedID != "imported"
        entryLimit = selectedID.flatMap { navigation.projectTabs.conversationBookmarks[$0]?.entryLimit } ?? 300
    }
    func openInWorkspace(_ session: Session) {
        if let project = projects.projects.first(where: { projects.sessions($0, library: self).contains(where: { $0.id == session.id }) }) {
            navigate(.project(project.id, session.id))
            navigation.layout.collapsedProjects.remove(project.id)
        } else { navigate(.imported(session.id)) }
    }
    func focusWorkspaceComposer() {
        if let project = projects.selected { navigation.tabs[project.id + ":" + (project.selectedSession ?? "draft")] = .conversation }
        viewMode = .conversation
        DispatchQueue.main.async { ComposerNSTextView.focusVisible() }
    }
    var spatialWorkspaceVisible: Bool {
        if let project = projects.selected {
            return (navigation.tabs[project.id + ":" + (project.selectedSession ?? "draft")] ?? .workspace) == .workspace
        }
        if projects.selectedID == "imported" { return selected != nil && viewMode == .workspace }
        return true
    }
    func toggleWorkspaceInspector() {
        if spatialWorkspaceVisible { spatial.conversationPanelVisible.toggle() }
        else { navigation.layout.inspectorVisible.toggle() }
    }
    var workspaceDestination: WorkspaceDestination {
        if projects.selectedID == "imported" { return .imported(selectedID) }
        if let project = projects.selected { return .project(project.id, project.selectedSession) }
        return .home
    }
}
