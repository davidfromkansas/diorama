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

