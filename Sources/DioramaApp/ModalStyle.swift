import DioramaCore
import SwiftUI

/// Pieces shared by the review modals (a request to answer, finished work to review) and the
/// agent sidebar: the same warm surface, tinted bands, hairlines and buttons.
enum ModalStyle {
    static let width: CGFloat = 560
    static let footer = Color(red: 0.969, green: 0.957, blue: 0.937)
    static let field = Color.white
    static let border = Color.black.opacity(0.12)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let red = Color(red: 0.70, green: 0.15, blue: 0.12)
}

/// Solid blue: the one main action.
struct ModalPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, height: height) }
    private struct Styled: View {
        let configuration: Configuration
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 14).frame(height: height)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SidebarStyle.accent.opacity(enabled ? 1 : 0.4)).brightness(configuration.isPressed ? -0.12 : hovered && enabled ? 0.06 : 0))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }.pointingHand()
        }
    }
}

/// White with a hairline border: every other action.
struct ModalSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, height: height) }
    private struct Styled: View {
        let configuration: Configuration
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium)).foregroundStyle(SidebarStyle.title.opacity(enabled ? 1 : 0.4)).lineLimit(1)
                .padding(.horizontal, 12).frame(height: height)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovered && enabled ? Color(white: 0.96) : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.black.opacity(0.16), lineWidth: 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .onHover { hovered = $0 }.pointingHand()
        }
    }
}

/// Icon, title, "Status · Model · detail", and a close button.
struct ModalHeader: View {
    let group: AgentSidebarGroup
    let title: String
    let status: String
    let model: String
    var detail: String? = nil
    /// A question mark instead of the group's icon (a question waiting for your answer).
    var question = false
    let close: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if question {
                    Image(systemName: "questionmark.circle.fill").resizable().foregroundStyle(.white, SidebarStyle.tint(group).dot).frame(width: 28, height: 28)
                } else {
                    AgentSidebarIcon(group: group).scaleEffect(28 / 24).frame(width: 28, height: 28)
                }
            }
            .padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(SidebarStyle.title).lineLimit(2)
                (Text(status).foregroundColor(SidebarStyle.tint(group).text)
                 + Text(" · " + model + (detail.map { " · " + $0 } ?? "")).foregroundColor(SidebarStyle.secondary))
                    .font(.system(size: 12)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(SidebarStyle.secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointingHand().keyboardShortcut(.cancelAction).accessibilityLabel("Close")
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
    }
}

/// A tinted band like the sidebar's group headers: what this is, and whether work waits.
struct ModalBand: View {
    let group: AgentSidebarGroup
    let title: String
    var detail: String? = nil
    var trailing: String? = nil
    var body: some View {
        let tint = SidebarStyle.tint(group)
        HStack(spacing: 8) {
            Circle().fill(tint.dot).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let detail { Text("· " + detail).font(.system(size: 12)) }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(tint.dot.opacity(0.18)))
            }
        }
        .foregroundStyle(tint.text).lineLimit(1)
        .padding(.horizontal, 16).frame(height: SidebarStyle.bandHeight).frame(maxWidth: .infinity)
        .background(tint.band)
        .overlay(alignment: .top) { ModalDivider() }.overlay(alignment: .bottom) { ModalDivider() }
        .accessibilityElement(children: .combine)
    }
}

/// A neutral section heading band ("Changes", "What was done").
struct ModalSectionBand<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 6)
            trailing.font(.system(size: 12))
        }
        .foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35)).lineLimit(1)
        .padding(.horizontal, 16).frame(height: SidebarStyle.bandHeight).frame(maxWidth: .infinity)
        .background(SidebarStyle.tint(.idle).band)
        .overlay(alignment: .bottom) { ModalDivider() }
        .accessibilityAddTraits(.isHeader)
    }
}

struct ModalDivider: View {
    var body: some View { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
}

/// The footer strip: a quiet link on the left, actions on the right.
struct ModalFooter<Leading: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(ModalStyle.footer)
        .overlay(alignment: .top) { ModalDivider() }
    }
}

extension View {
    /// The modal surface: warm, light, rounded, at the review width.
    func reviewModalSurface(width: CGFloat = ModalStyle.width) -> some View {
        self.frame(width: width)
            .background(SidebarStyle.background)
            .environment(\.colorScheme, .light).tint(SidebarStyle.accent)
            .presentationBackground(SidebarStyle.background)
            .preferredColorScheme(.light)
    }
}
