import SwiftUI

/// Three columns in a rounded frame: the task board's icon.
struct AgentBoardGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect.insetBy(dx: 0.7, dy: 0.7), cornerRadius: rect.height * 0.17)
        for third in [1.0 / 3, 2.0 / 3] {
            let x = rect.minX + rect.width * third
            path.move(to: CGPoint(x: x, y: rect.minY + 0.7)); path.addLine(to: CGPoint(x: x, y: rect.maxY - 0.7))
        }
        return path
    }
}

/// The agents at their largest: a board over the middle of the kitchen, one column per group
/// (Needs you → In progress → Done → Idle) and one card per task. Same items, actions and
/// selection as the side panel; the columns follow each task's real state, so cards don't drag.
struct AgentTaskBoard: View {
    let items: [AgentSidebarItem]
    let selectedConversation: String?
    let select: (AgentSidebarItem) -> Void
    let reviewRequest: (AgentSidebarItem) -> Void
    let reviewChanges: (AgentSidebarItem) -> Void
    let create: (() -> Void)?
    /// Back to the side panel.
    let dock: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let shown = items.filter { $0.matches(query) }
        VStack(spacing: 0) {
            header
            Rectangle().fill(SidebarStyle.divider).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                ForEach(AgentSidebarGroup.allCases) { group in
                    column(group, shown.filter { $0.group == group })
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 14) {
                Text("Click a card to select its chef and open the conversation")
                Text("·")
                Text("Esc or Side panel returns to the panel")
                Spacer(minLength: 8)
                Text("The kitchen keeps running behind the board")
            }
            .font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color(red: 0.969, green: 0.957, blue: 0.937))
            .overlay(alignment: .top) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        }
        .background(SidebarStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain).accessibilityLabel("Task board")
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentBoardGlyph().stroke(SidebarStyle.title, lineWidth: 1.5).frame(width: 18, height: 15)
            Text("Task board").font(.system(size: 16, weight: .semibold)).foregroundStyle(SidebarStyle.title)
            Text(Self.summary(items)).font(.system(size: 13)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                TextField("Search agents…", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                    .focused($searchFocused).accessibilityLabel("Search agents")
            }
            .padding(.horizontal, 9).frame(width: 240, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(searchFocused ? SidebarStyle.accent.opacity(0.7) : Color.black.opacity(0.12), lineWidth: searchFocused ? 2 : 1))
            if let create {
                Button("Create", action: create).buttonStyle(ModalPrimaryButtonStyle()).accessibilityLabel("Create agent")
            }
            Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1, height: 20)
            Button(action: dock) {
                Label { Text("Side panel") } icon: { Image(systemName: "sidebar.left") }
            }
            .buttonStyle(ModalSecondaryButtonStyle()).help("Back to the side panel (⇧⌘B)")
            UtilityIconButton(symbol: "xmark", help: "Close task board", action: dock)
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
    }

    private func column(_ group: AgentSidebarGroup, _ rows: [AgentSidebarItem]) -> some View {
        let tint = SidebarStyle.tint(group)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(tint.dot).frame(width: 8, height: 8)
                Text(group.title).font(.system(size: 13, weight: .semibold))
                Text("\(rows.count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 17)
                    .background(Capsule().fill(tint.dot.opacity(0.18)))
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint.text)
            .padding(.horizontal, 12).frame(height: 34)
            .background(tint.band)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1) }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    if rows.isEmpty {
                        Text("Nothing here").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).padding(.top, 18)
                    }
                    ForEach(rows) { item in card(item) }
                }
                .padding(10)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.025)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .contain).accessibilityLabel("\(group.title), \(rows.count)")
    }

    private func card(_ item: AgentSidebarItem) -> some View {
        AgentBoardCard(item: item, selected: item.conversationID == selectedConversation,
                       select: { select(item) },
                       action: { item.group == .done ? reviewChanges(item) : reviewRequest(item) })
            // A task that moves column is a new card there.
            .id(item.id + "\u{1F}" + String(item.group.rawValue))
    }

    static func summary(_ items: [AgentSidebarItem]) -> String {
        let count = { (group: AgentSidebarGroup) in items.filter { $0.group == group }.count }
        let needs = count(.needsYou)
        return "\(count(.inProgress)) active · \(needs) \(needs == 1 ? "needs" : "need") you · \(count(.done)) done · \(count(.idle)) idle"
    }
}

/// A task on the board: more than the side panel's row, since there's room. The title over up
/// to two lines (longer ones scroll), the question it waits on, its progress, a meta line
/// (branch, files, model and provider) and a status footer with its action.
struct AgentBoardCard: View {
    let item: AgentSidebarItem
    let selected: Bool
    let select: () -> Void
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        let tint = SidebarStyle.tint(item.group)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            BoardCardTitle(text: item.title, scrolls: !reduceMotion)
            if let question = item.question, !question.isEmpty {
                Text(question).font(.system(size: 12)).foregroundStyle(tint.text).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.band))
                    .help(question)
            }
            if let progress = item.progress {
                AgentSidebarStatusBar(progress: progress, paused: item.group == .needsYou)
            }
            meta
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
            HStack(spacing: 6) {
                AgentSidebarIcon(group: item.group).frame(width: 24, height: 24).scaleEffect(14 / 24).frame(width: 14, height: 14)
                Text(footer).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint.text)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if item.hasAction { ReviewActionButton(title: actionTitle, action: action) }
            }
            .frame(minHeight: 24)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(selected ? SidebarStyle.selected.opacity(0.6) : hovered ? Color(white: 0.99) : Color.white)
        .clipShape(shape)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(SidebarStyle.accent).frame(width: 3) } }
        .clipShape(shape)
        .overlay(shape.strokeBorder(focused ? SidebarStyle.accent.opacity(0.8) : Color.black.opacity(0.08), lineWidth: focused ? 2 : 1))
        .shadow(color: .black.opacity(hovered ? 0.14 : 0.08), radius: hovered ? 4 : 1, y: 1)
        .contentShape(shape)
        .onTapGesture(perform: select)
        .onHover { hovered = $0 }
        .focusable().focused($focused)
        .onKeyPress(.return) { select(); return .handled }
        .onKeyPress(.space) { select(); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([item.title, item.status, item.question ?? "", metaText, item.model].filter { !$0.isEmpty }.joined(separator: ". "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: actionTitle) { if item.hasAction { action() } }
    }

    private var meta: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if item.branch != nil { Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .medium)) }
                Text(metaText).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(SidebarStyle.secondary)
            Spacer(minLength: 4)
            // The model always shows in full; a long branch gives way first.
            Text(shortModel).font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(1).fixedSize()
            ProviderAvatar(provider: item.provider)
        }
    }
    /// "settings-page · 4 files" (after a branch mark), or what there is of it.
    private var metaText: String {
        var parts: [String] = []
        if let branch = item.branch { parts.append(branch) }
        if item.files > 0 { parts.append("\(item.files) file" + (item.files == 1 ? "" : "s")) }
        return parts.isEmpty ? "no branch" : parts.joined(separator: " · ")
    }
    /// The model without its provider's name ("Opus 5.5"), since the avatar says who.
    private var shortModel: String {
        for prefix in ["Claude ", "Codex "] where item.model.hasPrefix(prefix) { return String(item.model.dropFirst(prefix.count)) }
        return item.model
    }
    /// What it's doing now: its activity while it works, the wait while it needs you, when it finished.
    private var footer: String {
        switch item.group {
        case .inProgress:
            let activity = item.activity.trimmingCharacters(in: CharacterSet(charactersIn: "…. "))
            return activity.isEmpty ? item.status : activity
        case .needsYou: return item.status
        case .done: return item.finishedAt.map { "Finished " + $0.formatted(date: .omitted, time: .shortened) } ?? item.status
        case .idle: return item.activity.isEmpty ? item.status : item.activity
        }
    }
    private var actionTitle: String {
        if item.group == .done { return "Review" }
        return item.status == "Needs an answer" ? "Answer" : "Review"
    }
}

/// A small round mark for who runs the task: Claude's spark on its orange, Codex on black.
struct ProviderAvatar: View {
    let provider: String
    var body: some View {
        let claude = provider.lowercased().contains("claude")
        Image(systemName: claude ? "asterisk" : "chevron.left.forwardslash.chevron.right")
            .font(.system(size: claude ? 11 : 8, weight: .bold)).foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(red: 0.11, green: 0.11, blue: 0.12)))
            .help(claude ? "Claude" : "Codex")
            .accessibilityLabel(claude ? "Claude" : "Codex")
    }
}

/// A card title on up to two lines; a longer one glides up to show the rest, pauses, and
/// glides back (the side panel's one-line titles scroll sideways the same way).
struct BoardCardTitle: View {
    let text: String
    let scrolls: Bool
    @State private var height: CGFloat = 0
    /// The height of exactly two lines in this font, measured.
    @State private var limit: CGFloat = 36
    private static let font = Font.system(size: 13, weight: .semibold)
    var body: some View {
        let overflow = max(0, height - limit)
        let title = Text(text).font(Self.font).foregroundStyle(SidebarStyle.title)
            .lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if overflow > 1 && scrolls {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    title.offset(y: -overflow * Self.phase(context.date, overflow: overflow))
                }
            } else {
                title
            }
        }
        .background(GeometryReader { proxy in Color.clear.onAppear { height = proxy.size.height }.onChange(of: proxy.size.height) { _, value in height = value } })
        .background(alignment: .topLeading) {
            Text("A\nA").font(Self.font).lineSpacing(1).fixedSize().hidden()
                .background(GeometryReader { proxy in Color.clear.onAppear { limit = proxy.size.height } })
        }
        .frame(height: height == 0 ? nil : min(height, limit), alignment: .top)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            // Without scrolling (Reduce Motion), a long title ends in a fade.
            if overflow > 1 && !scrolls {
                LinearGradient(colors: [.white.opacity(0), .white], startPoint: .leading, endPoint: .trailing).frame(width: 40, height: limit / 2)
            }
        }
        .help(text)
        .accessibilityLabel(text)
    }
    /// 0 at the top, 1 at the end: two seconds still, glide, two seconds still, glide back.
    static func phase(_ date: Date, overflow: CGFloat) -> CGFloat {
        let travel = max(1.2, Double(overflow) / 14), cycle = 4 + 2 * travel
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        switch t {
        case ..<2: return 0
        case ..<(2 + travel): return CGFloat(ease((t - 2) / travel))
        case ..<(4 + travel): return 1
        default: return CGFloat(1 - ease((t - 4 - travel) / travel))
        }
    }
}
