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
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if navigation.layout.sidebarVisible {
                    sidebar.frame(width: navigation.layout.sidebarWidth)
                    Rectangle().fill(DioramaStyle.border).frame(width: 1).overlay {
                        Color.clear.frame(width: 7).contentShape(Rectangle()).gesture(DragGesture().onChanged { value in
                            if sidebarDrag == nil { sidebarDrag = navigation.layout.sidebarWidth }
                            navigation.layout.sidebarWidth = min(360, max(190, (sidebarDrag ?? 240) + value.translation.width))
                        }.onEnded { _ in sidebarDrag = nil })
                    }
                }
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Button { library.navigation.layout.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle sidebar (⌘B)")
                        Button { if let route = navigation.back() { library.navigate(route, record: false) } } label: { Image(systemName: "chevron.left") }.disabled(navigation.backStack.isEmpty).help("Back (⌘[)")
                        Button { if let route = navigation.forward() { library.navigate(route, record: false) } } label: { Image(systemName: "chevron.right") }.disabled(navigation.forwardStack.isEmpty).help("Forward (⌘])")
                        Spacer()
                        if library.isScanning { ProgressView().controlSize(.mini) }
                        Button { navigation.layout.inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }.help("Toggle inspector (⌘⌥B)").disabled(library.projects.selected == nil && library.selected == nil)
                    }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 32).background(DioramaStyle.sidebar)
                    ZStack {
                        SpatialWorkspaceView(library: library, visible: spatialVisible)
                            .opacity(spatialVisible ? 1 : 0)
                            .allowsHitTesting(spatialVisible).accessibilityHidden(!spatialVisible)
                        if !spatialVisible {
                            if let project = library.projects.selected {
                                ProjectDetailView(projectID: project.id, projects: library.projects, library: library).id(project.id)
                                    .environment(\.workspaceWide, WorkspaceNavigation.inlineInspector(width: geometry.size.width))
                                    .environment(\.workspaceContentWidth, geometry.size.width - (navigation.layout.sidebarVisible ? navigation.layout.sidebarWidth + 1 : 0))
                            } else if library.projects.selectedID == "imported", let session = library.selected {
                                WorkspaceImportedSession(session: session, library: library)
                                    .environment(\.workspaceWide, WorkspaceNavigation.inlineInspector(width: geometry.size.width))
                            } else {
                                WorkspaceHome(library: library, imported: library.projects.selectedID == "imported")
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(DioramaStyle.canvas).tint(DioramaStyle.accent)
        }
        .sheet(isPresented: Binding(get: { navigation.searchPresented }, set: { navigation.searchPresented = $0 })) {
            VStack(spacing: 0) {
                HStack { Text("Find a session").font(.headline); Spacer(); Button("Done") { navigation.searchPresented = false } }.padding(20)
                WorkspaceHome(library: library, imported: false, searching: true)
            }.frame(width: 720, height: 550)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in navigation.flushPersistence() }
         .onChange(of: library.workspaceDestination) {
            let destination = library.workspaceDestination
            navigation.visit(destination)
            let expected: SpatialFocus
            switch destination {
            case .home: expected = .portfolio
            case .project(let project, let session): expected = session.map { .team(project: project, conversation: $0) } ?? .project(project)
            case .imported(let session): expected = session.map { .team(project: nil, conversation: $0) } ?? .portfolio
            }
            if expected.projectID != library.spatial.focus.projectID || expected.conversationID != library.spatial.focus.conversationID {
                library.spatial.focus = expected; library.spatial.page = 0
            }
        }
        .onAppear {
            if navigation.hadSavedLayout { library.navigate(navigation.layout.destination, record: false) }
            else { navigation.visit(library.workspaceDestination) }
        }
    }
    private var spatialVisible: Bool {
        if let project = library.projects.selected {
            return (navigation.tabs[project.id + ":" + (project.selectedSession ?? "draft")] ?? .workspace) == .workspace
        }
        if library.projects.selectedID == "imported" { return library.selected != nil && library.viewMode == .workspace }
        return true
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Image(systemName: "square.stack.3d.up.fill").foregroundStyle(DioramaStyle.accent); Text("Diorama").fontWeight(.semibold); Spacer() }.padding(16)
            navRow("Home", icon: "house", selected: library.projects.selectedID == nil) { library.navigate(.home) }
            navRow("New Session", icon: "plus", selected: false) { library.showNewTask = true }
            navRow("Search", icon: "magnifyingglass", selected: false) { navigation.searchPresented = true }
            Divider().padding(.vertical, 12)
            HStack {
                Text("Projects").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Menu { Toggle("Show archived", isOn: $showArchived); Toggle("Show internal sessions", isOn: $library.showInternal); Divider(); addActions() } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).fixedSize().help("Project and sidebar options")
            }.padding(.horizontal, 16).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(library.projects.projects) { project in
                        WorkspaceProjectGroup(project: project, library: library, showArchived: showArchived)
                    }
                    if library.projects.projects.isEmpty {
                        Menu("Add a project") { addActions() }.padding(12)
                    }
                }.padding(.horizontal, 6)
            }
            Divider()
            navRow("Imported Activity", icon: "tray.full", selected: library.projects.selectedID == "imported") { library.navigate(.imported(nil)) }
            navRow("Attention inbox" + (library.attentionSessions.isEmpty ? "" : " · \(library.attentionSessions.count)"), icon: "bell", selected: false) { library.showInbox = true }
            HStack {
                Button { library.showConnections = true } label: { Image(systemName: "externaldrive.connected.to.line.below") }.help("Connections")
                Button { library.paused.toggle() } label: { Image(systemName: library.paused ? "play" : "pause") }.help(library.paused ? "Resume observation" : "Pause observation; agents keep working")
                Spacer()
                Button { openSettings() } label: { Image(systemName: "gearshape") }.help("Settings")
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(16)
        }.font(.system(size: 12)).background(DioramaStyle.sidebar)
    }
    private func navRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 32).background(selected ? DioramaStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 5)) }
            .buttonStyle(.plain).padding(.horizontal, 6)
    }
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
                } label: { Image(systemName: navigation.layout.collapsedProjects.contains(project.id) ? "chevron.right" : "chevron.down").font(.system(size: 9)).frame(width: 22, height: 30).contentShape(Rectangle()) }.help("Expand or collapse \(project.name)")
                Button { library.navigate(.project(project.id, nil)) } label: {
                    Label(project.name, systemImage: "folder").fontWeight(.medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.help(project.folder)
                Button { library.navigate(.project(project.id, nil)); library.focusWorkspaceComposer() } label: { Image(systemName: "plus").foregroundStyle(.secondary) }.help("New session in \(project.name)")
            }.buttonStyle(.plain).padding(.horizontal, 8).frame(height: 34)
            if !navigation.layout.collapsedProjects.contains(project.id) {
                ForEach(SessionPresentation.rows(orderedSessions, showInternal: library.showInternal)) { row in
                    Button { library.openInWorkspace(row.session) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: library.pinned.contains(row.session.id) ? "pin.fill" : "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(library.needsAttention(row.session) ? .orange : library.isWorking(row.session) ? .mint : DioramaStyle.accent)
                            Text(markdownTitle(row.session.title)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(row.session.observationOnly ? "Desktop" : row.session.provider == .codex ? "C" : "A").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            if row.session.archived { Image(systemName: "archivebox").font(.system(size: 10)) }
                        }.padding(.leading, 18 + CGFloat(min(row.depth, 4)) * 10).padding(.trailing, 8).frame(height: 32)
                            .background(project.id == library.projects.selectedID && project.selectedSession == row.session.id ? DioramaStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(markdownTitle(row.session.title) + " · " + row.session.sourceLabel + " · " + row.label)
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
                    Button("New Session") { library.showNewTask = true }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sessions", text: $query).textFieldStyle(.plain).focused($searchFocused)
                if !searching { Button("Search messages") { library.showMessageSearch = true }.font(.caption) }
            }
            HStack {
                Picker("Project", selection: $projectID) { Text("All projects").tag("all"); ForEach(library.projects.projects) { Text($0.name).tag($0.id) } }
                Picker("Provider", selection: $provider) { Text("All providers").tag("All"); ForEach(Provider.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
                Picker("Archive", selection: $archive) { Text("Active").tag("Active"); Text("Archived").tag("Archived"); Text("All").tag("All") }
                Picker("Activity", selection: $activity) { Text("All activity").tag("All"); Text("Working").tag("Working"); Text("Needs attention").tag("Needs attention") }
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
                                                Text(markdownTitle(session.title)).lineLimit(1)
                                                Text(URL(fileURLWithPath: session.project).lastPathComponent + " · " + session.sourceLabel).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if library.needsAttention(session) { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                                            if library.isWorking(session) { Text("Working").foregroundStyle(.mint).font(.caption) }
                                            Text(session.modified, style: .relative).font(.caption).foregroundStyle(.secondary)
                                        }.padding(12).background(DioramaStyle.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
                                    }.buttonStyle(.plain).contextMenu { ConversationActions(model: library, session: session) }
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
                VStack { HStack { Spacer(); Button("Close") { overlay = false } }.padding(12); inspector }
                    .frame(width: 340).background(DioramaStyle.sidebar).shadow(radius: 12)
            }
        }
        .onChange(of: library.navigation.layout.inspectorVisible) { if !wide { overlay.toggle() } }
        .task(id: session.id) {
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
