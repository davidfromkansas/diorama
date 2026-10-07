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
        let selected = item.conversationID == selectedConversation
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let row = AgentSidebarRow(item: item, selected: selected, card: true,
                                  select: { select(item) },
                                  action: { item.group == .done ? reviewChanges(item) : reviewRequest(item) })
        return row
            .background(selected ? Color.clear : Color.white)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            // A task that moves column is a new card there.
            .id(item.id + "\u{1F}" + String(item.group.rawValue))
    }

    static func summary(_ items: [AgentSidebarItem]) -> String {
        let count = { (group: AgentSidebarGroup) in items.filter { $0.group == group }.count }
        let needs = count(.needsYou)
        return "\(count(.inProgress)) active · \(needs) \(needs == 1 ? "needs" : "need") you · \(count(.done)) done · \(count(.idle)) idle"
    }
}
