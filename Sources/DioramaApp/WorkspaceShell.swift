import SwiftUI
import DioramaCore

struct WorkspaceShell<AddActions: View>: View {
    @Bindable var library: LibraryModel
    @ViewBuilder var addActions: () -> AddActions
    @State private var sidebarDrag: Double?
    @State private var showArchived = false
    @Environment(\.openSettings) private var openSettings
    private var navigation: WorkspaceNavigation { library.navigation }
    var body: some View {
        @Bindable var tabs = navigation.projectTabs
        VStack(spacing: 0) {
            DesktopProjectTabs(library: library)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if tabs.selected != .home && !tabs.pickerPresented {
                        HStack(spacing: 14) {
                            Button { if let roster = library.spatial.focus.projectID { library.spatial.roster(for: roster).collapsed.toggle() } } label: { Image(systemName: "sidebar.left") }.pointingHand().help("Toggle agents")
                            Button { if let route = navigation.back() { library.navigate(route, record: false) } } label: { Image(systemName: "chevron.left") }.pointingHand().disabled(navigation.backStack.isEmpty)
                            Button { if let route = navigation.forward() { library.navigate(route, record: false) } } label: { Image(systemName: "chevron.right") }.pointingHand().disabled(navigation.forwardStack.isEmpty)
                            // The kitchen is the only scene for now; the Office stays in code for future scenes.
                            Spacer()
                            Button { library.showNewTask = true } label: { Label("New agent", systemImage: "plus") }.pointingHand()
                            Button { library.toggleWorkspaceInspector() } label: { Image(systemName: "sidebar.right") }.pointingHand().help("Toggle conversation panel")
                        }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 32).background(DioramaStyle.sidebar)
                    }
                    WorkspacePaneStack {
                        // One native renderer per window; tabs store no scene graphs.
                        SpatialWorkspaceView(library: library, visible: spatialVisible)
                            .opacity(spatialVisible ? 1 : 0).allowsHitTesting(spatialVisible).accessibilityHidden(!spatialVisible)
                        DesktopHome(library: library, visible: tabs.selected == .home && !tabs.pickerPresented, addActions: addActions)
                            .opacity(tabs.selected == .home && !tabs.pickerPresented ? 1 : 0)
                            .allowsHitTesting(tabs.selected == .home && !tabs.pickerPresented).accessibilityHidden(tabs.selected != .home || tabs.pickerPresented)
                        if tabs.selected != .home && !spatialVisible && !tabs.pickerPresented {
                            if let project = library.projects.selected {
                                if folderAvailable {
                                    ProjectDetailView(projectID: project.id, projects: library.projects, library: library).id(project.id)
                                        .environment(\.workspaceWide, WorkspaceNavigation.inlineInspector(width: geometry.size.width))
                                        .environment(\.workspaceContentWidth, geometry.size.width)
                                } else { unavailable(project.name) }
                            } else { unavailable("Project") }
                        }
                        if tabs.pickerPresented { DesktopProjectPicker(library: library, addActions: addActions) }
                    }
                }
            }
        }.background(DioramaStyle.canvas).tint(DioramaStyle.accent)
        .background(DesktopKeyboardMonitor(library: library))
        .sheet(isPresented: Binding(get: { navigation.searchPresented }, set: { navigation.searchPresented = $0 })) {
            VStack(spacing: 0) {
                HStack { Text("Find a session").font(.headline); Spacer(); Button("Done") { navigation.searchPresented = false }.pointingHand() }.padding(20)
                WorkspaceHome(library: library, imported: false, searching: true)
            }.frame(width: 720, height: 550)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            library.flushDrafts(); library.captureProjectPresentation(); navigation.flushPersistence()
        }
        .onChange(of: library.workspaceDestination) {
            // Existing connection and session-creation flows may set ProjectModel selection.
            // Route those through the same outer tabs without changing execution ownership.
            if let id = library.projects.selectedID, id != "imported", tabs.selected != .project(id) { library.selectProjectTab(id) }
            navigation.visit(library.workspaceDestination)
        }
        .onAppear {
            if !navigation.hadSavedLayout, tabs.selected == .home, let id = library.projects.selected?.id {
                tabs.select(.project(id)); library.captureProjectPresentation()
            }
            library.scrollPositions.merge(tabs.historyAnchors) { _, saved in saved }; library.restoreDesktopSelection(); checkFolder() }
        .onChange(of: tabs.selected) { checkFolder() }
        .onChange(of: library.spatial.focus) { library.captureProjectPresentation() }
        .onChange(of: library.projects.presentation) { library.captureProjectPresentation() }
        .onChange(of: library.spatial.conversationPanelVisible) { library.captureProjectPresentation() }
        .onChange(of: library.spatial.conversationWidth) { library.captureProjectPresentation() }
        .onChange(of: library.spatial.inboxExpanded) { library.captureProjectPresentation() }
        .onChange(of: library.spatial.serversExpanded) { library.captureProjectPresentation() }
        .onChange(of: library.viewMode) { library.captureProjectPresentation() }
        .onDisappear { library.flushDrafts(); library.captureProjectPresentation(); navigation.flushPersistence() }
    }
    @State private var folderAvailable = true
    private func checkFolder() {
        guard let project = library.projects.selected else { folderAvailable = false; return }
        let id = project.id, generation = navigation.projectTabs.generation, path = project.folder
        Task {
            let exists = await Task.detached { var directory: ObjCBool = false; return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue }.value
            guard library.projects.selectedID == id, navigation.projectTabs.generation == generation else { return }
            folderAvailable = exists
        }
    }
    private func unavailable(_ name: String) -> some View {
        ContentUnavailableView {
            Label(name + " unavailable", systemImage: "folder.badge.questionmark")
        } description: { Text("The project folder is not available. Its conversations and drafts are retained.") }
        actions: {
            Button("Retry") { checkFolder() }.pointingHand()
            Button("Locate folder…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                let id = library.projects.selectedID
                panel.begin { response in
                    guard response == .OK, let url = panel.url, let id else { return }
                    Task {
                        do {
                            let found = try await ProjectFolder.open(url.path)
                            library.projects.update(id) { $0.folder = found.folder; $0.commonDirectory = found.commonDirectory }
                            checkFolder()
                        } catch { library.projects.error = error.localizedDescription }
                    }
                }
            }.pointingHand()
        }
    }
    private var spatialVisible: Bool { !navigation.projectTabs.pickerPresented && navigation.projectTabs.selected != .home && folderAvailable && library.spatialWorkspaceVisible }
}

/// Keep disclosure changes inside the project group rather than re-evaluating the entire shell.
struct WorkspaceProjectGroup: View {
    let project: DioramaProject
    @Bindable var library: LibraryModel
    let showArchived: Bool
    private var navigation: WorkspaceNavigation { library.navigation }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    if navigation.layout.collapsedProjects.contains(project.id) { navigation.layout.collapsedProjects.remove(project.id) }
                    else { navigation.layout.collapsedProjects.insert(project.id) }
                } label: { Image(systemName: navigation.layout.collapsedProjects.contains(project.id) ? "chevron.right" : "chevron.down").font(.system(size: 9)).frame(width: 22, height: 30).contentShape(Rectangle()) }.pointingHand().help("Expand or collapse \(project.name)")
                Button { library.navigate(.project(project.id, nil)) } label: {
                    Label(project.name, systemImage: "folder").fontWeight(.medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.pointingHand().help(project.folder)
                Button { library.navigate(.project(project.id, nil)); library.focusWorkspaceComposer() } label: { Image(systemName: "plus").foregroundStyle(.secondary) }.pointingHand().help("New session in \(project.name)")
            }.buttonStyle(.plain).padding(.horizontal, 8).frame(height: 34)
            if !navigation.layout.collapsedProjects.contains(project.id) {
                ForEach(SessionPresentation.rows(orderedSessions, showInternal: library.showInternal)) { row in
                    Button { library.openInWorkspace(row.session) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: library.pinned.contains(row.session.id) ? "pin.fill" : "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(library.needsAttention(row.session) ? .orange : library.isWorking(row.session) ? .mint : DioramaStyle.accent)
                            Text(row.session.displayTitle).help(TaskTitle.full(row.session.title)).accessibilityLabel(TaskTitle.full(row.session.title)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(row.session.observationOnly ? "Desktop" : row.session.provider == .codex ? "C" : "A").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            if row.session.archived { Image(systemName: "archivebox").font(.system(size: 10)) }
                        }.padding(.leading, 18 + CGFloat(min(row.depth, 4)) * 10).padding(.trailing, 8).frame(height: 32)
                            .background(project.id == library.projects.selectedID && project.selectedSession == row.session.id ? DioramaStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
                    }.pointingHand().buttonStyle(.plain).help(markdownTitle(row.session.title) + " · " + row.session.sourceLabel + " · " + row.label)
                        .contextMenu { ConversationActions(model: library, session: row.session) }
                }
            }
        }
    }
    private var orderedSessions: [Session] {
        library.projects.sessions(project, library: library).filter { showArchived || !$0.archived }.sorted {
            if library.pinned.contains($0.id) != library.pinned.contains($1.id) { return library.pinned.contains($0.id) }
            return $0.modified > $1.modified
        }
    }
}

struct WorkspaceHome: View {
    @Bindable var library: LibraryModel
    var imported: Bool
    var searching = false
    @State private var query = ""
    @State private var projectID = "all"
    @State private var provider = "All"
    @State private var archive = "Active"
    @State private var activity = "All"
    @FocusState private var searchFocused: Bool
    private var sessions: [Session] {
        let pool = library.projects.projects.first(where: { $0.id == projectID }).map { library.projects.sessions($0, library: library) } ?? library.sessions
        return pool.filter { session in
            (library.showInternal || session.classification != .internalReview) &&
            (provider == "All" || session.provider.rawValue == provider) &&
            (archive == "All" || session.archived == (archive == "Archived")) &&
            (activity == "All" || (activity == "Working" ? library.isWorking(session) : library.needsAttention(session))) &&
            (query.isEmpty || session.title.localizedCaseInsensitiveContains(query) || session.project.localizedCaseInsensitiveContains(query) || session.sessionID.localizedCaseInsensitiveContains(query))
        }.sorted { $0.modified > $1.modified }
    }
    private func bucket(_ session: Session) -> String {
        if Calendar.current.isDateInToday(session.modified) { return "Today" }
        if Calendar.current.isDateInYesterday(session.modified) { return "Yesterday" }
        if session.modified > Date().addingTimeInterval(-7 * 86400) { return "This week" }
        return "Earlier"
    }
    var body: some View {
        let visibleSessions = sessions
        let groups = Dictionary(grouping: visibleSessions, by: bucket)
        VStack(alignment: .leading, spacing: 20) {
            if !searching {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(imported ? "Imported Activity" : "Home").font(.system(size: 22, weight: .semibold))
                        Text(imported ? "Your local Codex and Claude Code conversations" : "Pick up where you left off").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("New Session") { library.showNewTask = true }.pointingHand()
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sessions", text: $query).textFieldStyle(.plain).focused($searchFocused)
                if !searching { Button("Search messages") { library.showMessageSearch = true }.pointingHand().font(.caption) }
            }
            HStack {
                Picker("Project", selection: $projectID) { Text("All projects").tag("all"); ForEach(library.projects.projects) { Text($0.name).tag($0.id) } }.pointingHand()
                Picker("Provider", selection: $provider) { Text("All providers").tag("All"); ForEach(Provider.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.pointingHand()
                Picker("Archive", selection: $archive) { Text("Active").tag("Active"); Text("Archived").tag("Archived"); Text("All").tag("All") }.pointingHand()
                Picker("Activity", selection: $activity) { Text("All activity").tag("All"); Text("Working").tag("Working"); Text("Needs attention").tag("Needs attention") }.pointingHand()
            }.labelsHidden().controlSize(.small)
            Divider()
            if visibleSessions.isEmpty {
                ContentUnavailableView(library.isScanning ? "Discovering sessions" : "No matching sessions", systemImage: "bubble.left.and.bubble.right", description: Text("Open a project or adjust your filters."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(["Today", "Yesterday", "This week", "Earlier"], id: \.self) { group in
                            let rows = groups[group] ?? []
                            if !rows.isEmpty {
                                Text(group).font(.caption).foregroundStyle(.secondary).padding(.top, 14).padding(.bottom, 4)
                                ForEach(rows) { session in
                                    Button {
                                        library.openInWorkspace(session); library.navigation.searchPresented = false
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: library.pinned.contains(session.id) ? "pin.fill" : "arrow.triangle.branch").foregroundStyle(DioramaStyle.accent)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(session.displayTitle).help(TaskTitle.full(session.title)).accessibilityLabel(TaskTitle.full(session.title)).lineLimit(1)
                                                Text(URL(fileURLWithPath: session.project).lastPathComponent + " · " + session.sourceLabel).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if library.needsAttention(session) { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                                            if library.isWorking(session) { Text("Working").foregroundStyle(.mint).font(.caption) }
                                            Text(session.modified, style: .relative).font(.caption).foregroundStyle(.secondary)
                                        }.padding(12).background(DioramaStyle.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
                                    }.pointingHand().buttonStyle(.plain).contextMenu { ConversationActions(model: library, session: session) }
                                }
                            }
                        }
                    }
                }
            }
        }.padding(searching ? 20 : 32).frame(maxWidth: 1000).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { if searching { searchFocused = true } }
    }
}
private struct WorkspaceContentWidthKey: EnvironmentKey { static let defaultValue = 1080.0 }
private struct WorkspaceWideKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var workspaceContentWidth: Double { get { self[WorkspaceContentWidthKey.self] } set { self[WorkspaceContentWidthKey.self] = newValue } }
    var workspaceWide: Bool { get { self[WorkspaceWideKey.self] } set { self[WorkspaceWideKey.self] = newValue } }
}
struct WorkspaceImportedSession: View {
    let session: Session
    @Bindable var library: LibraryModel
    @Environment(\.workspaceWide) private var wide
    @State private var overlay = false
    var body: some View {
        HStack(spacing: 0) {
            SessionView(session: session, model: library, hasLocalReview: true, activityAction: { section in
                library.activityState(session).section = section; library.viewMode = .activity
            })
            if wide && library.navigation.layout.inspectorVisible && session.provider == .codex {
                Divider()
                inspector.frame(width: 340)
            }
        }
        .overlay(alignment: .trailing) {
            if !wide && overlay && session.provider == .codex {
                VStack { HStack { Spacer(); Button("Close") { overlay = false }.pointingHand() }.padding(12); inspector }
                    .frame(width: 340).background(DioramaStyle.sidebar).shadow(radius: 12)
            }
        }
        .onChange(of: library.navigation.layout.inspectorVisible) { if !wide { overlay.toggle() } }
        .task(id: session.id + String(library.windowIsActive)) {
            guard library.windowIsActive else { return }
            while !Task.isCancelled {
                if !library.paused { await library.readSelected() }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private var inspector: some View {
        VStack(spacing: 0) {
            HStack { WorkspaceTabButton(title: "Changes", selected: true) {}; Spacer() }
            Divider()
            ReviewChangesControls(model: library, session: session)
            ExecutionChangesView(work: library.execution.tasks[session.sessionID]?.work ?? ExecutionWork())
        }
    }
}
