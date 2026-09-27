import SwiftUI
import SceneKit
import DioramaCore

@MainActor @Observable final class CapabilityLibraryModel {
    private(set) var snapshot: CapabilityLibrarySnapshot?
    private(set) var loading = false
    private var cache: [CapabilityLibraryContext: CapabilityLibrarySnapshot] = [:]
    private var generation = UUID()
    init(snapshot: CapabilityLibrarySnapshot? = nil) {
        self.snapshot = snapshot
        if let snapshot { cache[snapshot.context] = snapshot }
    }
    func load(_ context: CapabilityLibraryContext, force: Bool = false,
              fetch: (CapabilityLibraryContext) async -> CapabilityLibrarySnapshot) async {
        let token = UUID(); generation = token
        if !force, let saved = cache[context], saved.isFresh { snapshot = saved; loading = false; return }
        if snapshot?.context != context { snapshot = cache[context] }
        loading = true
        let value = await fetch(context)
        guard generation == token, !Task.isCancelled else { return }
        cache[context] = value; snapshot = value; loading = false
    }
    func cancel() { generation = UUID(); loading = false }
}

struct CapabilityLibraryView: View {
    let controller: ExecutionController
    let context: CapabilityLibraryContext
    var compact = false
    @Binding var selected: CapabilityLibraryItem?
    var close: () -> Void
    @State private var provider: Provider
    @Bindable var model: CapabilityLibraryModel
    @State private var query = ""
    @State private var kind: CapabilityLibraryKind?
    @FocusState private var searchFocused: Bool
    private let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let ink = Color(red: 0.27, green: 0.24, blue: 0.21)

    init(controller: ExecutionController, context: CapabilityLibraryContext, compact: Bool = false,
         selected: Binding<CapabilityLibraryItem?>, model: CapabilityLibraryModel = CapabilityLibraryModel(), close: @escaping () -> Void) {
        self.controller = controller; self.context = context; self.compact = compact; self._selected = selected; self.model = model; self.close = close
        _provider = State(initialValue: context.provider)
    }
    private var effectiveContext: CapabilityLibraryContext {
        .init(provider: provider, folder: context.folder, sessionID: provider == context.provider ? context.sessionID : nil)
    }
    private var rows: [CapabilityLibraryItem] {
        (model.snapshot?.items ?? []).filter { item in
            (kind == nil || item.kind == kind) && (query.isEmpty || (item.name + " " + item.description).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            if compact && selected == nil {
                Image(nsImage: WorkspaceLibraryArtwork.previewImage).resizable().scaledToFit().frame(height: 125).accessibilityHidden(true)
            }
            if let selected {
                detail(selected)
            } else {
                catalogue
            }
            footer
        }
        .background(paper).foregroundStyle(ink).tint(Color(red: 0.38, green: 0.50, blue: 0.40))
        .environment(\.colorScheme, .light)
        .task(id: effectiveContext) { selected = nil; await reload() }
        .onDisappear { model.cancel() }
        .onExitCommand { if selected != nil { self.selected = nil } else { close() } }
        .defaultFocus($searchFocused, true)
        .onAppear { searchFocused = true }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THE WORKSPACE COLLECTION").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.secondary)
                    Text("Little Library").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Big ideas. Little books.").font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 26, height: 26) }
                    .buttonStyle(.plain).accessibilityLabel("Close library").help("Close library (Escape)")
            }
            HStack {
                Picker("Provider", selection: $provider) {
                    Text("Codex").tag(Provider.codex); Text("Claude").tag(Provider.claude)
                }.pickerStyle(.segmented).frame(maxWidth: 230)
                Spacer()
                if model.loading { ProgressView().controlSize(.small).accessibilityLabel("Loading capabilities") }
            }
        }.padding(20)
    }
    private var catalogue: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a book…", text: $query).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search capabilities")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
            }.padding(10).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    filter("All", value: nil)
                    ForEach(CapabilityLibraryKind.allCases, id: \.self) { filter($0.rawValue, value: $0) }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
            ScrollView {
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text(model.loading ? "Gathering your books…" : !query.isEmpty ? "No matching books" : model.snapshot?.errors.isEmpty == false ? "Some shelves couldn’t be loaded" : "No capabilities discovered")
                            .font(.headline)
                        Text(provider == .claude ? "Local books are unverified until an attached Claude session reports them." : "Capabilities belong to this project and provider.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(30).frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 115, maximum: 155), spacing: 14)], alignment: .leading, spacing: 22) {
                        ForEach(rows) { item in
                            Button { selected = item } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    LibraryBookCover(item: item).frame(height: 123)
                                    Text(item.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(2).frame(height: 32, alignment: .topLeading)
                                    Text(item.availability.rawValue).font(.system(size: 9)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("\(item.name), \(item.kind.rawValue), \(item.availability.rawValue)").help(item.description)
                        }
                    }.padding(20)
                }
            }
        }
    }
    private func filter(_ label: String, value: CapabilityLibraryKind?) -> some View {
        Button { kind = value } label: {
            Text(label).font(.system(size: 11, weight: kind == value ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(kind == value ? Color(red: 0.85, green: 0.89, blue: 0.81) : .white.opacity(0.5), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(kind == value ? .isSelected : [])
    }
    private func detail(_ item: CapabilityLibraryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { selected = nil; searchFocused = true } label: { Label("All books", systemImage: "chevron.left") }.buttonStyle(.plain)
                LibraryBookCover(item: item).frame(width: 160, height: 185).frame(maxWidth: .infinity)
                Text(item.name).font(.system(size: 23, weight: .bold, design: .rounded)).textSelection(.enabled)
                HStack { Text(item.kind.rawValue); Text("·"); Text(item.availability.rawValue) }.font(.caption).foregroundStyle(.secondary)
                Text(item.description.isEmpty ? "This capability does not include a description." : item.description).font(.system(size: 14)).textSelection(.enabled)
                Divider()
                Text(item.provider.rawValue).font(.caption.bold())
                Text(item.source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if item.kind == .plugin {
                    Text("In this collection").font(.headline)
                    let children = (model.snapshot?.items ?? []).filter { $0.pluginID == item.id }
                    if children.isEmpty { Text("No included capabilities have been discovered yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(children) { child in
                        Button { selected = child } label: {
                            HStack { Image(systemName: child.emblem); Text(child.name); Spacer(); Image(systemName: "chevron.right") }
                                .font(.callout).padding(10).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Text("Workspace availability may differ for individual agents. Using tools can still require approval.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = model.snapshot, !snapshot.errors.isEmpty {
                DisclosureGroup("\(snapshot.errors.count) discovery issue(s)") {
                    ForEach(snapshot.errors.keys.sorted(), id: \.self) { key in
                        Text(key + ": " + (snapshot.errors[key] ?? "")).font(.caption).textSelection(.enabled)
                    }
                }.font(.caption)
            }
            HStack {
                Text("\(model.snapshot?.items.count ?? 0) books · Read-only").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await reload(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .font(.caption).buttonStyle(.plain).disabled(model.loading)
            }
        }.padding(16).background(Color(red: 0.93, green: 0.90, blue: 0.83))
    }
    private func reload(force: Bool = false) async {
        await model.load(effectiveContext, force: force) { await controller.capabilityLibrary($0) }
        if let selected { self.selected = model.snapshot?.items.first { $0.id == selected.id } }
    }
}

struct LibraryBookCover: View {
    let item: CapabilityLibraryItem
    private var color: Color { Color(nsColor: WorkspaceLibraryArtwork.colors[item.coverIndex]) }
    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.4)).offset(x: item.kind == .plugin ? 7 : 3, y: 4)
                RoundedRectangle(cornerRadius: 9).fill(Color(red: 0.99, green: 0.95, blue: 0.84)).padding(.leading, 5).offset(y: 3)
                RoundedRectangle(cornerRadius: 9).fill(color.gradient).padding(.bottom, 5)
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.10)).frame(width: 13)
                    Rectangle().fill(.white.opacity(0.20)).frame(width: 2)
                    Spacer()
                }.clipShape(RoundedRectangle(cornerRadius: 9)).padding(.bottom, 5)
                RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.36), lineWidth: 1).padding(17)
                VStack(spacing: 10) {
                    Image(systemName: item.emblem).font(.system(size: min(30, g.size.height * 0.22), weight: .regular))
                    Capsule().fill(.white.opacity(0.6)).frame(width: 25, height: 2)
                }.foregroundStyle(Color(red: 1, green: 0.96, blue: 0.84)).padding(.leading, 6)
                VStack { HStack { Spacer(); Rectangle().fill(Color(red: 0.91, green: 0.74, blue: 0.43)).frame(width: 9, height: 22).padding(.trailing, 22) }; Spacer() }
            }.shadow(color: .brown.opacity(0.15), radius: 3, x: 1, y: 3)
        }.accessibilityHidden(true)
    }
}
