import AppKit
import DioramaCore
import SwiftUI

/// A service's icon: its company mark on its brand colour, else a lettered tile in a colour
/// picked from its name.
struct BrandIcon: View {
    let name: String
    var mark: BrandMark.Mark? = nil
    var size: CGFloat = 30
    var body: some View {
        let mark = mark ?? BrandMark.match(name)
        let background = mark.map { Color(hex: $0.hex) } ?? Self.tile(name)
        let light = mark.map { Self.isLight($0.hex) } ?? false
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(background)
            .overlay {
                if let mark, let image = BrandMarkImage.image(mark, white: !light) {
                    Image(nsImage: image).resizable().scaledToFit().padding(size * 0.22)
                } else {
                    Text(String(name.prefix(2))).font(.system(size: size * 0.37, weight: .bold)).foregroundStyle(.white)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .frame(width: size, height: size)
    }
    private static let tiles: [Color] = [Color(red: 0.36, green: 0.42, blue: 0.82), Color(red: 0.2, green: 0.55, blue: 0.5), Color(red: 0.7, green: 0.4, blue: 0.25),
                                         Color(red: 0.55, green: 0.35, blue: 0.7), Color(red: 0.3, green: 0.45, blue: 0.6)]
    static func tile(_ name: String) -> Color { tiles[Int(name.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }) % tiles.count] }
    static func isLight(_ hex: String) -> Bool {
        let value = Int(hex, radix: 16) ?? 0
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.72
    }
}

/// Renders each mark once per colour.
@MainActor enum BrandMarkImage {
    private static var cache: [String: NSImage] = [:]
    static func image(_ mark: BrandMark.Mark, white: Bool) -> NSImage? {
        let key = mark.slug + (white ? ":w" : ":d")
        if let image = cache[key] { return image }
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"\(white ? "#FFFFFF" : "#1C1C1E")\"><path d=\"\(mark.path)\"/></svg>"
        let image = NSImage(data: Data(svg.utf8))
        cache[key] = image
        return image
    }
}

extension Color {
    /// "RRGGBB".
    init(hex: String) {
        let value = Int(hex, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// The kitchen's top-centre bar: what the chefs are reaching for, live. Servers and apps as
/// company icons (ringed while in use, a crate badge when a plugin brought them), the latest
/// skill in a slot that flips, a caption naming who picked up what, and All for everything.
struct LiveToolsBar: View {
    let agents: [SpatialAgent]
    /// How many resources All lists, when known.
    let total: Int?
    let openAll: () -> Void
    /// Where a chef's head is, in the "kitchenTools" coordinate space, for the spark it sends.
    var chefPoint: ((String) -> CGPoint?)? = nil
    @State private var model = LiveToolsModel()
    /// The bar, its first icon slot and its skill slot, in the "kitchenTools" space.
    @State private var barFrame: CGRect = .zero
    @State private var iconsFrame: CGRect = .zero
    @State private var skillFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(SidebarStyle.tint(.done).dot).frame(width: 7, height: 7)
                    .background(Circle().fill(SidebarStyle.tint(.done).dot.opacity(0.22)).frame(width: 13, height: 13))
                Text("LIVE").font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(SidebarStyle.secondary)
            }
            if model.slots.isEmpty && model.skill == nil {
                Text("Tools show up here as chefs use them").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            } else {
                HStack(spacing: 14) {
                    ForEach(model.slots) { slot in
                        LiveToolIcon(slot: slot)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(x: -24)),
                                                                              removal: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(x: 24))))
                    }
                }
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.62), value: model.slots.map(\.id))
                .background(GeometryReader { proxy in Color.clear.onAppear { iconsFrame = proxy.frame(in: .named("kitchenTools")) }.onChange(of: proxy.frame(in: .named("kitchenTools"))) { _, frame in iconsFrame = frame } })
                Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1, height: 22)
                skillSlot
            }
            Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1, height: 22)
            Button(action: openAll) {
                HStack(spacing: 6) {
                    Text(total.map { "All \($0)" } ?? "All").font(.system(size: 12.5, weight: .semibold))
                    Text("⇧⌘K").font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 4).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
                }
                .foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35))
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.05)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointingHand()
            .help("Every MCP server, app, plugin and skill (⇧⌘K)").accessibilityLabel("All tools")
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 5)
        .background(SidebarStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .overlay(alignment: .bottom) {
            if let caption = model.caption {
                HStack(spacing: 6) {
                    Circle().fill(SidebarStyle.accent).frame(width: 8, height: 8)
                    (Text(caption.chef).bold() + Text(" " + caption.text)).font(.system(size: 12)).foregroundStyle(.white).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.88)))
                .fixedSize()
                .offset(y: 38)
                .transition(.opacity.combined(with: .offset(y: -6)))
                .id(caption.id)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.caption)
        .background(GeometryReader { proxy in Color.clear.onAppear { barFrame = proxy.frame(in: .named("kitchenTools")) }.onChange(of: proxy.frame(in: .named("kitchenTools"))) { _, frame in barFrame = frame } })
        // Sparks fly from the chef up to the slot the tool lands in.
        .overlay(alignment: .topLeading) {
            if !reduceMotion, let chefPoint {
                ForEach(model.sparks) { spark in
                    if let from = chefPoint(spark.agentID) {
                        let target = spark.skill ? skillFrame : iconsFrame
                        let to = target == .zero ? CGPoint(x: barFrame.midX, y: barFrame.midY) : CGPoint(x: spark.skill ? target.minX + 16 : target.minX + 15, y: target.midY)
                        ChefSpark(from: CGPoint(x: from.x - barFrame.minX, y: from.y - barFrame.minY), to: CGPoint(x: to.x - barFrame.minX, y: to.y - barFrame.minY),
                                  color: spark.skill ? SidebarStyle.tint(.done).dot : SidebarStyle.accent) { model.landed(spark) }
                    }
                }
            }
        }
        .environment(\.colorScheme, .light)
        .onHover { model.frozen = $0 }
        .onAppear { model.observe(agents) }
        .onChange(of: signature) { model.observe(agents) }
        .task {
            // Plays held picks once the calm window passes, and clears old captions.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                model.flush(); model.expireCaption()
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Live tools")
    }

    /// What changes when a chef reaches for something new.
    private var signature: [String] {
        agents.map { "\($0.id)|\($0.value.latestTool)|\($0.value.latestToolDetail)|\($0.value.lastToolAt?.timeIntervalSince1970 ?? 0)|\($0.value.isWorking)" }
    }

    @ViewBuilder private var skillSlot: some View {
        ZStack(alignment: .leading) {
            if let pick = model.skill {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(SidebarStyle.tint(.done).dot)
                    Text(pick.resource.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(SidebarStyle.tint(.done).text).lineLimit(1).truncationMode(.tail)
                }
                .padding(.horizontal, 9).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SidebarStyle.tint(.done).band))
                .help(pick.chef.isEmpty ? "Skill: \(pick.resource.name)" : "\(pick.chef) used the \(pick.resource.name) skill")
                .id(pick.resource.id + pick.chef + String(pick.at.timeIntervalSince1970))
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0)),
                                                                  removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))))
            } else {
                Text("No skills yet").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).padding(.horizontal, 6)
            }
        }
        .frame(width: 160, height: 30, alignment: .leading)
        .background(GeometryReader { proxy in Color.clear.onAppear { skillFrame = proxy.frame(in: .named("kitchenTools")) }.onChange(of: proxy.frame(in: .named("kitchenTools"))) { _, frame in skillFrame = frame } })
        .animation(.easeInOut(duration: 0.35), value: model.skill)
        .accessibilityLabel(model.skill.map { "Latest skill: \($0.resource.name)" } ?? "No skills used yet")
    }
}

/// The split-flap turn of the skill slot.
private struct FlipModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5).opacity(abs(angle) > 80 ? 0 : 1)
    }
}

/// One server on the bar: its company icon, a ring and the chef's initial while in use, a crate
/// badge when a plugin brought it, and a pulse when it's used again in place.
private struct LiveToolIcon: View {
    let slot: LiveToolsModel.Slot
    @State private var pulse = false
    var body: some View {
        let busy = !slot.users.isEmpty
        BrandIcon(name: slot.resource.name, mark: slot.resource.brand)
            .overlay {
                // A ring with a gap of the bar's colour, so it reads on blue marks too.
                if busy {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(SidebarStyle.background, lineWidth: 2).padding(-2)
                    RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(SidebarStyle.accent, lineWidth: 2).padding(-4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let chef = slot.users.first {
                    Text(String(chef.prefix(1)).uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Circle().fill(SidebarStyle.accent))
                        .overlay(Circle().strokeBorder(SidebarStyle.background, lineWidth: 1.5))
                        .offset(x: 5, y: 5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if slot.resource.plugin != nil {
                    Image(systemName: "shippingbox").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35))
                        .frame(width: 15, height: 15)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
                        .offset(x: -5, y: 5)
                }
            }
            .scaleEffect(pulse ? 1.18 : 1)
            .onChange(of: slot.pulses) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pulse = true }
                Task { try? await Task.sleep(for: .milliseconds(220)); withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pulse = false } }
            }
            .help(help)
            .accessibilityLabel(help)
    }
    private var help: String {
        let from = slot.resource.plugin.map { " (\($0) plugin)" } ?? ""
        if slot.users.isEmpty { return slot.resource.name + from + " · used " + slot.lastUsed.formatted(.relative(presentation: .named)) }
        return slot.resource.name + from + " · in use by " + slot.users.joined(separator: ", ")
    }
}

/// Every resource the agents can use, grouped like the pantry: MCP servers and apps
/// (appliances, crates), plugins with what they bring, and skills (jars). Enter on a skill arms
/// it for the selected chef.
struct AllResourcesPalette: View {
    @Bindable var library: LibraryModel
    let folder: String
    let sessions: [Provider: String]
    var armFor: (conversation: String, name: String)?
    let close: () -> Void
    enum Filter: String, CaseIterable { case all = "All", claude = "Claude", codex = "Codex" }
    @State private var filter = Filter.all
    @State private var query = ""
    @State private var claude = CapabilityLibraryModel()
    @State private var codex = CapabilityLibraryModel()
    @State private var expanded: Set<String> = []
    @FocusState private var searchFocused: Bool

    private var items: [CapabilityLibraryItem] {
        let all = (filter != .codex ? claude.snapshot?.items ?? [] : []) + (filter != .claude ? codex.snapshot?.items ?? [] : [])
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }
    static func isServer(_ item: CapabilityLibraryItem) -> Bool { item.kind == .tool && item.source == "MCP server" }

    var body: some View {
        let items = self.items
        let servers = Self.merged(items.filter { Self.isServer($0) || $0.kind == .app })
        let plugins = Self.merged(items.filter { $0.kind == .plugin })
        let skills = Self.merged(items.filter { $0.kind == .skill })
        let toConnect = items.filter { $0.availability == .connectionNeeded }.count
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(SidebarStyle.secondary)
                    TextField("Search servers, apps, plugins and skills…", text: $query).textFieldStyle(.plain).font(.system(size: 14))
                        .focused($searchFocused).accessibilityLabel("Search tools")
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SidebarStyle.accent.opacity(searchFocused ? 0.6 : 0.25), lineWidth: 2))
                UtilitySegmentedPicker(options: Filter.allCases, selection: $filter) { $0.rawValue }
                if toConnect > 0 {
                    HStack(spacing: 6) { Circle().fill(SidebarStyle.tint(.needsYou).dot).frame(width: 7, height: 7); Text("\(toConnect) to connect") }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(SidebarStyle.tint(.needsYou).text)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SidebarStyle.tint(.needsYou).band))
                }
                UtilityIconButton(symbol: "xmark", help: "Close", action: close)
            }
            .padding(12)
            Rectangle().fill(SidebarStyle.divider).frame(height: 1)
            if items.isEmpty {
                Text(claude.loading || codex.loading ? "Stocking the shelves…" : "Nothing matches").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    column("MCP servers and apps", servers.count, "appliances") { ForEach(servers) { serverRow($0) } }
                    column("Plugins", plugins.count, "crates") { ForEach(plugins) { pluginRow($0) } }
                    column("Skills", skills.count, "jars") { ForEach(skills) { skillRow($0) } }
                }
                .padding(.horizontal, 10).padding(.vertical, 12)
            }
            HStack(spacing: 16) {
                Text(armFor.map { "Click a skill to arm it for \($0.name)" } ?? "Select a chef to arm skills for it")
                Text("Plugins open to show what they bring")
                Spacer(minLength: 8)
                Text("Built-in tools (shell, edits, search) are the kitchen's stations")
            }
            .font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(red: 0.969, green: 0.957, blue: 0.937))
            .overlay(alignment: .top) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        }
        .background(SidebarStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .environment(\.colorScheme, .light)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: close)
        .task(id: folder + (sessions[.claude] ?? "")) {
            await claude.load(CapabilityLibraryContext(provider: .claude, folder: folder, sessionID: sessions[.claude])) { await library.execution.capabilityLibrary($0) }
        }
        .task(id: folder + (sessions[.codex] ?? "")) {
            await codex.load(CapabilityLibraryContext(provider: .codex, folder: folder, sessionID: sessions[.codex])) { await library.execution.capabilityLibrary($0) }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("All tools").accessibilityAddTraits(.isModal)
    }

    /// One row per name: the same server or skill under both providers shows once, with both.
    struct Entry: Identifiable {
        let item: CapabilityLibraryItem
        var providers: [Provider]
        var id: String { item.kind.rawValue + ":" + item.name.lowercased() }
    }
    static func merged(_ items: [CapabilityLibraryItem]) -> [Entry] {
        var order: [String] = [], entries: [String: Entry] = [:]
        for item in items {
            let key = item.kind.rawValue + ":" + item.name.lowercased()
            if var entry = entries[key] {
                if !entry.providers.contains(item.provider) { entry.providers.append(item.provider) }
                if entry.item.availability != .available && item.availability == .available { entry = Entry(item: item, providers: entry.providers) }
                entries[key] = entry
            } else { order.append(key); entries[key] = Entry(item: item, providers: [item.provider]) }
        }
        return order.compactMap { entries[$0] }
    }

    private func column<Content: View>(_ title: String, _ count: Int, _ shelf: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .bold)).foregroundStyle(SidebarStyle.title)
                Text("\(count) · pantry \(shelf)").font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary)
            }
            .padding(.horizontal, 10)
            ScrollView(.vertical) { LazyVStack(alignment: .leading, spacing: 2) { content() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private func providers(_ entry: Entry) -> String {
        entry.providers.map { $0 == .claude ? "Claude" : "Codex" }.sorted().joined(separator: " · ")
    }
    private func status(_ item: CapabilityLibraryItem) -> some View {
        let (text, color): (String, Color) = switch item.availability {
        case .available: ("Ready", SidebarStyle.secondary)
        case .connectionNeeded: ("Connect", SidebarStyle.tint(.needsYou).text)
        case .disabled: ("Disabled", Color(red: 0.56, green: 0.56, blue: 0.58))
        case .unverified: ("Installed", SidebarStyle.secondary)
        }
        return Text(text).font(.system(size: 11.5)).foregroundStyle(color)
    }
    private func serverRow(_ entry: Entry) -> some View {
        HStack(spacing: 10) {
            BrandIcon(name: entry.item.name, size: 26).opacity(entry.item.availability == .disabled ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.item.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(SidebarStyle.title).lineLimit(1)
                Text((entry.item.kind == .app ? "App" : "MCP server") + " · " + providers(entry)).font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            status(entry.item)
        }
        .padding(.horizontal, 10).frame(height: 40)
        .help(entry.item.description.isEmpty ? entry.item.name : entry.item.description)
    }
    private func pluginRow(_ entry: Entry) -> some View {
        let open = expanded.contains(entry.id)
        let kids = items.filter { $0.pluginID == entry.item.id && $0.kind != .plugin }
        let summary = [kids.filter { $0.kind == .skill }.count, kids.filter { Self.isServer($0) }.count]
        let text = [summary[0] > 0 ? "\(summary[0]) skill" + (summary[0] == 1 ? "" : "s") : nil, summary[1] > 0 ? "\(summary[1]) MCP server" + (summary[1] == 1 ? "" : "s") : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            Button { if open { expanded.remove(entry.id) } else { expanded.insert(entry.id) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(SidebarStyle.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 8)
                    BrandIcon(name: entry.item.name, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.item.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(SidebarStyle.title).lineLimit(1)
                        Text("Plugin" + (text.isEmpty ? "" : " · " + text) + " · " + providers(entry)).font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    status(entry.item)
                }
                .padding(.horizontal, 10).frame(height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointingHand()
            .accessibilityValue(open ? "expanded" : "collapsed")
            if open {
                ForEach(kids) { kid in
                    HStack(spacing: 8) {
                        Image(systemName: kid.kind == .skill ? "sparkle" : "server.rack").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(kid.kind == .skill ? SidebarStyle.tint(.done).dot : SidebarStyle.accent)
                        Text(kid.name).font(.system(size: 12)).foregroundStyle(SidebarStyle.title).lineLimit(1)
                        Text(kid.kind == .skill ? "Skill" : "MCP server").font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary)
                    }
                    .padding(.leading, 52).frame(height: 26)
                }
                if kids.isEmpty { Text("Nothing listed inside").font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).padding(.leading, 52).frame(height: 26) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(open ? Color(red: 0.98, green: 0.973, blue: 0.96) : .clear))
    }
    private func skillRow(_ entry: Entry) -> some View {
        let armed = armFor.map { (library.armedCapabilities[$0.conversation] ?? []).contains { $0.path == entry.item.source } } ?? false
        return Button {
            if let armFor { library.arm(CapabilityInput(name: entry.item.name, path: entry.item.source, kind: "skill"), for: armFor.conversation) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").font(.system(size: 12, weight: .bold)).foregroundStyle(SidebarStyle.tint(.done).dot)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SidebarStyle.tint(.done).band))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.item.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(SidebarStyle.title).lineLimit(1)
                    Text([entry.item.description, providers(entry)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if armed { Label("Armed", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(SidebarStyle.tint(.done).text) }
                else if armFor != nil { Text("Arm").font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary) }
            }
            .padding(.horizontal, 10).frame(height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand().disabled(armFor == nil)
        .help(armFor.map { "Arm \(entry.item.name) for \($0.name)'s next message" } ?? entry.item.description)
    }
}

/// A glowing dot that arcs from a chef to the bar and fades as it lands.
private struct ChefSpark: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let done: () -> Void
    @State private var t: Double = 0
    var body: some View {
        Circle().fill(color).frame(width: 13, height: 13)
            .shadow(color: color, radius: 6)
            .modifier(SparkPath(t: t, from: from, to: to))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeIn(duration: 0.55)) { t = 1 }
                Task { try? await Task.sleep(for: .milliseconds(620)); done() }
            }
    }
}
/// Position along an arc above the straight line, shrinking toward the end.
private struct SparkPath: ViewModifier, Animatable {
    var t: Double
    let from: CGPoint
    let to: CGPoint
    var animatableData: Double { get { t } set { t = newValue } }
    func body(content: Content) -> some View {
        let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 60)
        let u = 1 - t
        let x = u * u * from.x + 2 * u * t * control.x + t * t * to.x
        let y = u * u * from.y + 2 * u * t * control.y + t * t * to.y
        content.scaleEffect(1 - 0.45 * t).opacity(t > 0.92 ? (1 - t) / 0.08 : 1).position(x: x, y: y)
    }
}

/// Finds a chef's head on screen, from the kitchen view that shows it.
@MainActor enum ChefLocator {
    /// The head of the chef for `agentID`, in the kitchen view's top-left coordinates.
    static func head(_ agentID: String) -> CGPoint? {
        for window in NSApp.windows where window.isVisible {
            guard let view = find(window.contentView, agentID) else { continue }
            view.chefLock.lock()
            let position = view.chefs[agentID]?.root.simdPosition
            view.chefLock.unlock()
            guard let position, let point = view.projectWithoutLock(position + SIMD3(0, 2.05 * KitchenLayout.chefScale, 0)) else { return nil }
            return CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
        }
        return nil
    }
    private static func find(_ root: NSView?, _ agentID: String) -> KitchenSceneView? {
        guard let root, !root.isHidden else { return nil }
        if let kitchen = root as? KitchenSceneView {
            kitchen.chefLock.lock(); defer { kitchen.chefLock.unlock() }
            return kitchen.chefs[agentID] != nil ? kitchen : nil
        }
        for child in root.subviews { if let found = find(child, agentID) { return found } }
        return nil
    }
}
