import DioramaCore
import SwiftUI

/// Two corner brackets: pointing in (shrink) on the open card, pointing out (grow) on the pill.
struct ShrinkGrowIcon: Shape {
    let grow: Bool
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        if grow {
            path.move(to: p(6.5, 2.5)); path.addLine(to: p(2.5, 2.5)); path.addLine(to: p(2.5, 6.5))
            path.move(to: p(9.5, 13.5)); path.addLine(to: p(13.5, 13.5)); path.addLine(to: p(13.5, 9.5))
        } else {
            path.move(to: p(2.5, 6.5)); path.addLine(to: p(6.5, 6.5)); path.addLine(to: p(6.5, 2.5))
            path.move(to: p(13.5, 9.5)); path.addLine(to: p(9.5, 9.5)); path.addLine(to: p(9.5, 13.5))
        }
        return path
    }
}

/// The round button sitting on the agent card's top-right corner (and on the collapsed pill's):
/// quiet at rest, white with a stronger shadow on hover or keyboard focus. 22 pt, 28 pt hit area.
struct SidebarCornerButton: View {
    let grow: Bool
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        let lit = hovered || focused
        Button(action: action) {
            ShrinkGrowIcon(grow: grow)
                .stroke(lit ? SidebarStyle.title : Color(red: 0.56, green: 0.56, blue: 0.58), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .background(Circle().fill(lit ? Color.white : Color(red: 0.969, green: 0.957, blue: 0.937)))
                .overlay(Circle().strokeBorder(Color.black.opacity(lit ? 0.16 : 0.12), lineWidth: 1))
                .shadow(color: .black.opacity(lit ? 0.28 : 0.18), radius: lit ? 4 : 1.5, y: lit ? 3 : 1)
                .overlay { if focused { Circle().strokeBorder(SidebarStyle.accent.opacity(0.7), lineWidth: 2).padding(-3) } }
                .frame(width: 28, height: 28).contentShape(Circle())
        }
        .buttonStyle(.plain).pointingHand().focused($focused)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: lit)
        .help(grow ? "Show agents (⌘B)" : "Collapse (⌘B)")
        .accessibilityLabel(grow ? "Show agents" : "Collapse agents")
        .accessibilityHint("Command B")
    }
}

/// The collapsed agent card, top left of the kitchen: how many work, need you and are done.
/// A count opens the card at its group; the corner button opens it as it was.
struct AgentSidebarPill: View {
    let summary: AgentSidebar.Summary
    let open: (AgentSidebarGroup?) -> Void
    var body: some View {
        HStack(spacing: 2) {
            count(summary.active, "working", .inProgress, highlight: false)
            count(summary.needsYou, summary.needsYou == 1 ? "needs input" : "need input", .needsYou, highlight: summary.needsYou > 0)
            count(summary.done, "done", .done, highlight: false)
        }
        .padding(4)
        .background(SidebarStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        // Room for the corner button, which sits half off the pill's top-right corner.
        .padding(.trailing, 4)
        .overlay(alignment: .topTrailing) { SidebarCornerButton(grow: true) { open(nil) }.offset(x: 10, y: -14) }
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain).accessibilityLabel("Agents summary")
    }
    private func count(_ value: Int, _ label: String, _ group: AgentSidebarGroup, highlight: Bool) -> some View {
        let tint = SidebarStyle.tint(group)
        return Button { open(group) } label: {
            HStack(spacing: 5) {
                Circle().fill(tint.dot).frame(width: 8, height: 8)
                Text("\(value)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(value > 0 ? tint.text : SidebarStyle.secondary)
                Text(label).font(.system(size: 12)).foregroundStyle(highlight ? tint.text : SidebarStyle.secondary)
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(highlight ? tint.band : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand()
        .help("Show \(group.title)")
        .accessibilityLabel("\(value) \(label). Show \(group.title)")
    }
}
