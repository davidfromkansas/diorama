import DioramaCore
import SwiftUI

/// Dark, see-through cards that float over the kitchen (the agents list, the pantry), in the
/// spirit of a game editor's HUD: rounded, a hairline edge, a soft shadow.
struct FloatingCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.09, green: 0.11, blue: 0.13).opacity(0.72)))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            .environment(\.colorScheme, .dark)
    }
}
extension View {
    func floatingCard() -> some View { modifier(FloatingCard()) }
    /// The agent sidebar's light, warm card floating over the kitchen.
    func lightFloatingCard() -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }
}

/// The pantry: everything agents can fetch, as jars (skills), crates (plugins and apps) and
/// appliances (MCP servers). With a chef selected, skills can be armed for its next message.
struct PantryCard: View {
    enum Shelf: String, CaseIterable, Identifiable {
        case skills = "Jars", plugins = "Crates", servers = "Appliances"
        var id: String { rawValue }
        var detail: String { switch self { case .skills: "Skills"; case .plugins: "Plugins"; case .servers: "MCP" } }
        var icon: String { switch self { case .skills: "flask"; case .plugins: "shippingbox"; case .servers: "powerplug" } }
        func contains(_ item: CapabilityLibraryItem) -> Bool {
            switch self {
            case .skills: item.kind == .skill
            case .plugins: item.kind == .plugin || item.kind == .app
            case .servers: item.kind == .tool && item.source == "MCP server"
            }
        }
    }
    @Bindable var library: LibraryModel
    let folder: String
    /// The newest conversation per provider in this project, for runtime-backed listings.
    let sessions: [Provider: String]
    /// The selected chef's conversation, when skills can be armed for it.
    var armFor: (conversation: String, name: String)?
    let close: () -> Void
    @State private var provider: Provider
    @State private var shelf: Shelf = .skills
    @State private var search = ""
    @State private var model = CapabilityLibraryModel()

    init(library: LibraryModel, folder: String, sessions: [Provider: String], preferred: Provider, armFor: (conversation: String, name: String)?, close: @escaping () -> Void) {
        self.library = library; self.folder = folder; self.sessions = sessions; self.armFor = armFor; self.close = close
        _provider = State(initialValue: preferred)
    }
    private var context: CapabilityLibraryContext { CapabilityLibraryContext(provider: provider, folder: folder, sessionID: sessions[provider]) }
    private var items: [CapabilityLibraryItem] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (model.snapshot?.items ?? []).filter { shelf.contains($0) && (query.isEmpty || $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cabinet").foregroundStyle(Color(red: 0.85, green: 0.66, blue: 0.33))
                Text("Pantry").font(.headline)
                Spacer()
                Picker("Provider", selection: $provider) {
                    Text("Codex").tag(Provider.codex); Text("Claude").tag(Provider.claude)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.mini).frame(width: 110)
                Button(action: close) { Image(systemName: "minus").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).pointingHand().help("Close pantry").accessibilityLabel("Close pantry")
            }
            HStack(spacing: 4) {
                ForEach(Shelf.allCases) { value in
                    Button { shelf = value } label: {
                        Label(value.rawValue, systemImage: value.icon).font(.caption.weight(.semibold)).labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(shelf == value ? Color.white.opacity(0.16) : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).pointingHand().help(value.detail)
                }
            }
            TextField("Search the pantry", text: $search).textFieldStyle(.roundedBorder).controlSize(.small)
            if items.isEmpty {
                VStack(spacing: 4) {
                    Text(model.loading ? "Stocking the shelves…" : "Nothing on this shelf.").font(.caption)
                    if !model.loading, let error = model.snapshot?.errors.values.first { Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(3) }
                }
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { item in
                            PantryRow(item: item, armFor: shelf == .skills ? armFor : nil, armed: armed.contains(item.source)) { arm(item) }
                        }
                    }
                }
            }
            Text("\(items.count) on this shelf" + (armFor.map { " · arming for \($0.name)" } ?? "")).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .floatingCard()
        .task(id: context) { await model.load(context) { await library.execution.capabilityLibrary($0) } }
    }
    /// Skills already armed for the selected chef's next message.
    private var armed: Set<String> { Set(armFor.map { library.armedCapabilities[$0.conversation] ?? [] }?.map(\.path) ?? []) }
    private func arm(_ item: CapabilityLibraryItem) {
        guard let armFor else { return }
        library.arm(CapabilityInput(name: item.name, path: item.source, kind: "skill"), for: armFor.conversation)
    }
}

private struct PantryRow: View {
    let item: CapabilityLibraryItem
    let armFor: (conversation: String, name: String)?
    var armed = false
    let arm: () -> Void
    @State private var hovered = false
    private static let covers: [Color] = [
        Color(red: 0.86, green: 0.36, blue: 0.24), Color(red: 0.22, green: 0.55, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 0.75),
        Color(red: 0.78, green: 0.6, blue: 0.2), Color(red: 0.32, green: 0.6, blue: 0.36),
    ]
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.emblem).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Self.covers[item.coverIndex % Self.covers.count].gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.caption.weight(.medium)).lineLimit(1)
                if !item.description.isEmpty { Text(item.description).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if armed {
                Label("Armed", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.35, green: 1, blue: 0.62)).help("Armed for \(armFor?.name ?? "the chef")'s next message")
            } else if let armFor, hovered {
                Button("Arm", action: arm).buttonStyle(.borderedProminent).controlSize(.mini).pointingHand().help("Arm for \(armFor.name)'s next message")
            } else {
                Circle().fill(dot).frame(width: 6, height: 6).help(item.availability.rawValue)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovered ? Color.white.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .help(item.description.isEmpty ? item.name : item.description)
        .draggable(ArmedSkill(name: item.name, path: item.source))
    }
    private var dot: Color {
        switch item.availability {
        case .available: Color(red: 0.35, green: 1, blue: 0.62)
        case .connectionNeeded: .orange
        default: .gray
        }
    }
}
