import SwiftUI
import DioramaCore
import UniformTypeIdentifiers

struct DesktopProjectTabs: View {
    @Bindable var library: LibraryModel
    @State private var dragging: String?
    @State private var tabContentWidth: CGFloat = 0
    private var tabs: ProjectTabStore { library.navigation.projectTabs }
    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 6) {
            Button { library.selectDesktopTab(.home) } label: {
                Label("Home", systemImage: "square.grid.2x2").padding(.horizontal, 12).frame(height: 32)
                    .background(tabs.selected == .home ? DioramaStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }.pointingHand().buttonStyle(.plain).help("Home (⌘1)").accessibilityAddTraits(tabs.selected == .home ? .isSelected : [])
            Divider().frame(height: 20)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(tabs.projects, id: \.self) { id in
                            DesktopProjectTab(library: library, id: id).id(id)
                                .onDrag { dragging = id; return NSItemProvider(object: id as NSString) }
                                .onDrop(of: [.text], delegate: ProjectTabDrop(id: id, dragging: $dragging, store: tabs))
                        }
                    }.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tabContentWidth = $0 }
                }.scrollIndicators(.hidden)
                    .frame(width: min(tabContentWidth, max(0, geometry.size.width - 180)))
                    .onChange(of: tabs.selected) { _, selection in if case .project(let id) = selection { proxy.scrollTo(id) } }
            }
            Button { tabs.pickerPresented = true } label: { Image(systemName: "plus").frame(width: 32, height: 32) }.pointingHand()
                .buttonStyle(.plain).help("Open project (⌘T)").accessibilityLabel("Open project")
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).frame(height: 46)
        }.frame(height: 46).background(DioramaStyle.sidebar)
            .overlay(alignment: .bottom) { Divider() }
    }
}
private struct DesktopProjectTab: View {
    @Bindable var library: LibraryModel
    let id: String
    @State private var hovering = false
    @FocusState private var focused: Bool
    private var selected: Bool { library.navigation.projectTabs.selected == .project(id) }
    private var project: DioramaProject? { library.projects.projects.first { $0.id == id } }
    private var name: String { project?.name ?? "Unavailable project" }
    private var attention: Bool {
        guard let project else { return false }
        return library.projects.sessions(project, library: library).contains { library.needsAttention($0) }
    }
    var body: some View {
        Button { library.selectProjectTab(id) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                    ProjectTabTitle(text: name, active: library.windowIsActive)
                    if attention { Circle().fill(.orange).frame(width: 6, height: 6).accessibilityLabel("Needs attention") }
                }
                .padding(.leading, 12).padding(.trailing, 32).frame(height: 32)
                .contentShape(Rectangle())
            }.pointingHand().buttonStyle(.plain).focused($focused).accessibilityLabel("Project: " + name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            .overlay(alignment: .trailing) {
            Button { library.closeProjectTab(id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 32).padding(.trailing, 4).contentShape(Rectangle()) }.pointingHand()
                .buttonStyle(.plain).opacity(hovering || focused ? 1 : 0.01)
                .help("Close \(name)").accessibilityLabel("Close project tab " + name)
            }
            .background(selected ? DioramaStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }.help(name)
            .contextMenu {
                Button("Close tab") { library.closeProjectTab(id) }.pointingHand()
                if let index = library.navigation.projectTabs.projects.firstIndex(of: id), index > 0 {
                    Button("Move tab left") { library.navigation.projectTabs.move(id, before: library.navigation.projectTabs.projects[index - 1]) }.pointingHand()
                }
                if let index = library.navigation.projectTabs.projects.firstIndex(of: id), index + 1 < library.navigation.projectTabs.projects.count {
                    Button("Move tab right") { library.navigation.projectTabs.move(library.navigation.projectTabs.projects[index + 1], before: id) }.pointingHand()
                }
            }
    }
}
/// Only the clipped text animates; tab width and neighboring controls stay fixed.
struct ProjectTabTitle: View {
    let text: String
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var scrolling = false
    private var textWidth: CGFloat { ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width) + 2 }
    private var overflow: CGFloat { max(0, textWidth - 170) }
    var body: some View {
        Text(text).font(.system(size: NSFont.systemFontSize)).fixedSize()
            .offset(x: scrolling ? -overflow : 0)
            .frame(width: min(170, textWidth), alignment: .leading).clipped()
            .accessibilityLabel(text)
            .task(id: "\(text)|\(active)|\(reducedMotion)") {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { scrolling = false }
                guard active, !reducedMotion, overflow > 0 else { return }
                do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                withAnimation(.linear(duration: max(3, Double(overflow / 28))).delay(1.2).repeatForever(autoreverses: true)) { scrolling = true }
            }
    }
}
private struct ProjectTabDrop: DropDelegate {
    let id: String
    @Binding var dragging: String?
    let store: ProjectTabStore
    func dropEntered(info: DropInfo) { if let dragging { store.move(dragging, before: id) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

struct DesktopProjectPicker<AddActions: View>: View {
    @Bindable var library: LibraryModel
    @ViewBuilder var addActions: () -> AddActions
    @State private var query = ""
    @FocusState private var searching: Bool
    private var projects: [DioramaProject] {
        library.navigation.projectTabs.recentProjects(library.projects.projects)
            .filter { query.isEmpty || ($0.name + " " + $0.folder).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Open project").font(.system(size: 26, weight: .semibold))
                Spacer()
                Button { library.navigation.projectTabs.pickerPresented = false } label: {
                    Image(systemName: "xmark").frame(width: 30, height: 30).contentShape(Rectangle())
                }.pointingHand().buttonStyle(.plain).accessibilityLabel("Close project picker")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { addActions() }
                VStack(alignment: .leading, spacing: 12) { addActions() }
            }.buttonStyle(.bordered).controlSize(.large)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search projects", text: $query).textFieldStyle(.plain).focused($searching)
                    .accessibilityLabel("Search projects by name or path")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.pointingHand()
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }.padding(14).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
            Text(query.isEmpty ? "Recents" : "Search results").font(.headline)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(projects) { project in
                        Button { library.selectProjectTab(project.id) } label: {
                            HStack(spacing: 18) {
                                PortfolioPlatform(surface: PortfolioSurface(projectID: project.id))
                                    .frame(width: 88, height: 62)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(project.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                    Text(project.folder).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if let date = library.navigation.projectTabs.lastOpened[project.id] {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Opened").font(.caption2)
                                        Text(date.formatted(.relative(presentation: .named))).font(.caption)
                                    }.foregroundStyle(.secondary).help(date.formatted(date: .complete, time: .shortened))
                                }
                            }.padding(12).frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.pointingHand().buttonStyle(.plain).help(project.name + "\n" + project.folder)
                    }
                    if projects.isEmpty {
                        Text(query.isEmpty ? "Projects you open will appear here." : "No matching projects")
                            .foregroundStyle(.secondary).padding(32)
                    }
                }
            }
        }.padding(32).frame(maxWidth: 920).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DioramaStyle.canvas).onAppear { searching = true }
            .onExitCommand { library.navigation.projectTabs.pickerPresented = false }
    }
}

struct DesktopHome<AddActions: View>: View {
    @Bindable var library: LibraryModel
    var visible = true
    @ViewBuilder var addActions: () -> AddActions
    @State private var projects: [SpatialProject] = []
    @State private var refreshTask: Task<Void, Never>?
    @Environment(\.openSettings) private var openSettings
    private var store: ProjectTabStore { library.navigation.projectTabs }
    var body: some View {
        @Bindable var state = store
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Diorama").font(.headline).padding(16)
                ForEach(HomeSection.allCases, id: \.self) { section in
                    Button {
                        state.home.section = section
                        library.projects.selectedID = section == .imported ? "imported" : nil
                        if section != .imported { library.selectedID = nil }
                    } label: {
                        Label(section.rawValue, systemImage: section.icon).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(state.home.section == section ? DioramaStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.pointingHand().buttonStyle(.plain).padding(.horizontal, 8)
                }
                Spacer()
                Button { library.showConnections = true } label: { Label("Connections", systemImage: "externaldrive.connected.to.line.below") }.pointingHand().padding(10)
                Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }.pointingHand().padding(10)
            }.buttonStyle(.plain).padding(.bottom, 12).frame(width: 205).frame(maxHeight: .infinity).background(DioramaStyle.sidebar)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(state.home.section.rawValue).font(.system(size: 25, weight: .medium))
                    Spacer()
                    Menu("Connect project") { addActions() }.pointingHand()
                    if state.home.section == .all || state.home.section == .recents || state.home.section == .search {
                        Picker("View", selection: $state.home.list) {
                            Image(systemName: "square.grid.2x2").tag(false)
                            Image(systemName: "list.bullet").tag(true)
                        }.pointingHand().pickerStyle(.segmented).frame(width: 74).labelsHidden().help("Grid or list view")
                    }
                }.padding(24)
                if state.home.section == .search {
                    TextField("Search projects", text: $state.home.query).textFieldStyle(.roundedBorder).padding(.horizontal, 24).padding(.bottom, 16)
                }
                switch state.home.section {
                case .imported where visible:
                    if let session = library.selected { WorkspaceImportedSession(session: session, library: library) }
                    else { WorkspaceHome(library: library, imported: true) }
                case .attention where visible:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if library.attentionSessions.isEmpty { Text("No agents need attention").foregroundStyle(.secondary).padding() }
                            ForEach(library.attentionSessions) { session in
                                Button { library.openAttention(session) } label: {
                                    VStack(alignment: .leading, spacing: 4) { Text(session.displayTitle); Text(session.project).font(.caption).foregroundStyle(.secondary) }
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(DioramaStyle.raised, in: RoundedRectangle(cornerRadius: 8))
                                }.pointingHand().buttonStyle(.plain)
                            }
                        }.padding(24)
                    }
                default:
                    projectLibrary
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(DioramaStyle.canvas)
            .onChange(of: library.sessionsRevision, initial: true) { refresh() }
            .onChange(of: library.projects.projects.map { $0.id + $0.name }) { refresh() }
            .onChange(of: library.scannedAt) { refresh() }
            .onChange(of: library.observationClock) { refresh() }
            .onChange(of: library.windowIsActive) { if library.windowIsActive { refresh() } }
            .onChange(of: visible) {
                if visible { refresh() } else { refreshTask?.cancel() }
            }
            .onDisappear { refreshTask?.cancel() }
    }
    private var displayed: [SpatialProject] {
        var values = library.portfolio.ordered(projects)
        if store.home.section == .recents {
            values = store.recentProjects(values)
        }
        if store.home.section == .search, !store.home.query.isEmpty { values = values.filter { $0.name.localizedCaseInsensitiveContains(store.home.query) } }
        return values
    }
    private var projectLibrary: some View {
        @Bindable var state = store
        return ScrollView {
            LazyVGrid(columns: state.home.list ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                ForEach(displayed) { project in
                    PortfolioProjectTile(project: project, usage: library.portfolio.usage(project.id), paused: library.paused,
                        animate: false, loading: library.isScanning, viewportHeight: 1000, compact: state.home.list, select: route).id(project.id)
                }
                if displayed.isEmpty { Text(state.home.section == .recents ? "Projects you open will appear here." : "No matching projects").foregroundStyle(.secondary).padding(30) }
            }.scrollTargetLayout().padding(.horizontal, 24).padding(.bottom, 24)
        }.coordinateSpace(name: "portfolio-scroll").scrollPosition(id: $state.home.scrollID, anchor: .top)
    }
    private func refresh() {
        guard visible, library.windowIsActive || projects.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            // Coalesce discovery notifications and let navigation paint its cached content first.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let next = await library.homeProjectSummaries() else { return }
            if projects != next { projects = next }
        }
    }
    private func route(_ focus: SpatialFocus) {
        guard let project = focus.projectID else { return }
        library.selectProjectTab(project)
        if let conversation = focus.conversationID { library.navigate(.project(project, conversation)); library.spatial.focus = focus; library.spatial.conversationPanelVisible = true }
    }
}
