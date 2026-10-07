import SwiftUI

/// The light pill docked top right of the kitchen (servers, inbox): the agents pill's twin.
struct UtilityPill<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 2) { content }
            .padding(4)
            .background(SidebarStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
            .environment(\.colorScheme, .light)
    }
}

/// A hairline between two pill segments.
struct UtilityPillDivider: View {
    var body: some View { Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1, height: 18).padding(.horizontal, 2) }
}

/// One pill segment: icon, an optional bold count, a label, then an optional trailing mark
/// (status dot or unread badge). Pale blue while its card is open.
struct UtilitySegment<Trailing: View>: View {
    let symbol: String
    var count: Int? = nil
    let label: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var trailing: Trailing
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35))
                if let count { Text("\(count)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(SidebarStyle.title) }
                Text(label).font(.system(size: 12)).foregroundStyle(count == nil ? SidebarStyle.title : SidebarStyle.secondary)
                trailing
            }
            .lineLimit(1)
            .padding(.horizontal, 9).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? SidebarStyle.selected : hovered ? Color.black.opacity(0.05) : .clear))
            .overlay { if focused { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SidebarStyle.accent.opacity(0.7), lineWidth: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand().focused($focused)
        .onHover { hovered = $0 }
    }
}

/// The blue unread badge on the inbox segment.
struct UtilityBadge: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(SidebarStyle.accent))
    }
}

/// The servers segment's status dot: green with a soft halo while listening, grey when stale.
struct UtilityStatusDot: View {
    let live: Bool
    var body: some View {
        Circle().fill(live ? SidebarStyle.tint(.done).dot : Color(red: 0.56, green: 0.56, blue: 0.58)).frame(width: 7, height: 7)
            .background(Circle().fill(live ? SidebarStyle.tint(.done).dot.opacity(0.22) : .clear).frame(width: 11, height: 11))
    }
}

extension View {
    /// The servers and inbox cards: the agent card's light surface, fading in when open.
    func utilityCard(open: Bool) -> some View {
        self.background(SidebarStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(open ? 0.09 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(open ? 0.22 : 0), radius: 16, y: 6)
    }
}

/// A tinted band inside a utility card ("Listening 2", "Unread 3"), like the agent card's groups.
struct UtilityCardBand: View {
    let title: String
    var count: Int? = nil
    let tint: SidebarStyle.Tint
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint.dot).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let count {
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 17)
                    .background(Capsule().fill(tint.dot.opacity(0.18)))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint.text)
        .padding(.horizontal, SidebarStyle.horizontal).frame(height: SidebarStyle.bandHeight)
        .background(tint.band)
        .overlay(alignment: .top) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

/// A 28 pt borderless icon button for card headers (refresh, more…).
struct UtilityIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovered ? Color.black.opacity(0.06) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand().onHover { hovered = $0 }
        .help(help).accessibilityLabel(help)
    }
}

/// A small segmented switch in the card's header (the inbox filter).
struct UtilitySegmentedPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let chosen = option == selection
                Button { selection = option } label: {
                    Text(title(option)).font(.system(size: 12, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? SidebarStyle.title : Color(red: 0.33, green: 0.33, blue: 0.35))
                        .lineLimit(1).padding(.horizontal, 8).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(chosen ? Color.white : .clear)
                            .shadow(color: .black.opacity(chosen ? 0.12 : 0), radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointingHand()
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.06)))
    }
}
