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
    case conversation, activity, html, context, pullRequests, document(WorkspaceDocument)
    var title: String {
        switch self {
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
    var tabs: [String: WorkspaceTab] = [:] { didSet { schedulePersistence() } }
    var documents: [String: [WorkspaceDocument]] = [:] { didSet { schedulePersistence() } }
    var backStack: [WorkspaceDestination] = []
    var forwardStack: [WorkspaceDestination] = []
    var searchPresented = false
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var isRestoring = true
    private let defaults: UserDefaults
    let hadSavedLayout: Bool
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: "workspaceLayout.v1").flatMap { try? JSONDecoder().decode(WorkspaceLayout.self, from: $0) }
        hadSavedLayout = saved != nil
        layout = saved ?? WorkspaceLayout()
        layout.sidebarWidth = min(360, max(190, layout.sidebarWidth))
        layout.inspectorWidth = min(560, max(280, layout.inspectorWidth))
        if let data = defaults.data(forKey: "workspaceTabs.v1"), let saved = try? JSONDecoder().decode([String: WorkspaceTab].self, from: data) { tabs = saved }
        if let data = defaults.data(forKey: "workspaceDocuments.v1"), let saved = try? JSONDecoder().decode([String: [WorkspaceDocument]].self, from: data) { documents = saved }
        isRestoring = false
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
        if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: "workspaceLayout.v1") }
        if let data = try? JSONEncoder().encode(tabs) { defaults.set(data, forKey: "workspaceTabs.v1") }
        if let data = try? JSONEncoder().encode(documents) { defaults.set(data, forKey: "workspaceDocuments.v1") }
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
    static let canvas = Color(red: 0.075, green: 0.063, blue: 0.067)
    static let sidebar = Color(red: 0.105, green: 0.101, blue: 0.098)
    static let raised = Color(red: 0.14, green: 0.13, blue: 0.13)
    static let selection = Color.white.opacity(0.065)
    static let border = Color.white.opacity(0.08)
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
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
extension LibraryModel {
    func navigate(_ destination: WorkspaceDestination, record: Bool = true) {
        if record { navigation.visit(destination) }
        switch destination {
        case .home: projects.selectedID = nil; selectedID = nil
        case .imported(let session):
            projects.selectedID = "imported"
            selectedFolderID = sessions.first(where: { $0.id == session }).flatMap { WorkingFolder.group([$0]).first?.id }
            selectedID = session
        case .project(let id, let session):
            guard projects.projects.contains(where: { $0.id == id }) else { navigate(.home); return }
            projects.selectedID = id
            projects.update(id) {
                if $0.selectedSession != session { $0.fileLocation = nil; $0.fileSelection = nil }
                $0.selectedSession = session; if record { $0.section = "Sessions" }
            }
            selectedID = session
        }
        projectNavigation = projects.selectedID != "imported"
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
    var workspaceDestination: WorkspaceDestination {
        if projects.selectedID == "imported" { return .imported(selectedID) }
        if let project = projects.selected { return .project(project.id, project.selectedSession) }
        return .home
    }
}
