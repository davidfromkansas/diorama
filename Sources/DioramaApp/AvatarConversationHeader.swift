import SwiftUI
import DioramaCore

/// Who a conversation is with, for its header: the agent, the task it's on (the same short title
/// as its tag in the kitchen and its row in the agent panel), its branch, and how to close it.
struct AvatarHeaderInfo {
    var name: String
    var task: String
    /// The whole task, for the tooltip and accessibility.
    var taskDetail: String
    var branch: String
    var close: () -> Void
}
private struct AvatarHeaderKey: EnvironmentKey { static let defaultValue: AvatarHeaderInfo? = nil }
extension EnvironmentValues {
    /// Set by the conversation panel: the conversation draws its iMessage header from it.
    var avatarHeader: AvatarHeaderInfo? {
        get { self[AvatarHeaderKey.self] }
        set { self[AvatarHeaderKey.self] = newValue }
    }
}

/// The iMessage-style header: avatar, name and task centred, with the branch and (for a
/// conversation you can message) the model as small capsules; the conversation's tools behind ⋯
/// and Close at the right.
struct AvatarConversationHeader: View {
    let info: AvatarHeaderInfo
    var model: AnyView? = nil
    var tools: AnyView? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Text(String(info.name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [Color(white: 0.66), Color(white: 0.56)], startPoint: .top, endPoint: .bottom), in: Circle())
                    .accessibilityHidden(true)
                Text(info.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(info.task).font(.system(size: 12.5)).foregroundStyle(Color(white: 0.23))
                    .lineLimit(1).truncationMode(.middle)
                    .help(info.taskDetail).accessibilityLabel(info.taskDetail)
                // Side by side when they fit, stacked in a narrow panel.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { branch; model }
                    VStack(spacing: 4) { branch; model }
                }.padding(.top, 3)
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 72).padding(.top, 12).padding(.bottom, 10)
            HStack(spacing: 6) {
                if let tools { AvatarToolsButton(tools: tools) }
                Button(action: info.close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.06), in: Circle())
                }.pointingHand().buttonStyle(.plain).help("Close conversation").accessibilityLabel("Close conversation")
            }.padding(12)
        }
        .background(Color(white: 0.976))
        .accessibilityElement(children: .contain)
    }

    private var branch: some View {
        Label {
            Text(info.branch).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
        } icon: {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
        }
        .labelStyle(AvatarCapsuleLabelStyle())
        .frame(maxWidth: 230)
        .avatarCapsule()
        .help(info.branch).accessibilityLabel("Branch " + info.branch)
    }
}

/// The small rounded capsule the header's branch and model sit in.
struct AvatarCapsule: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content.foregroundStyle(highlighted ? Color.accentColor : Color(white: 0.23))
            .padding(.horizontal, 9).frame(height: 22)
            .background(highlighted ? Color.accentColor.opacity(0.12) : Color(white: 0.95), in: Capsule())
            .overlay(Capsule().strokeBorder(highlighted ? Color.accentColor : Color.black.opacity(0.08)))
    }
}
extension View {
    func avatarCapsule(highlighted: Bool = false) -> some View { modifier(AvatarCapsule(highlighted: highlighted)) }
}
struct AvatarCapsuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

/// ⋯ in the header: the conversation's tools (history detail, usage, find, activity, plan, tasks,
/// conversation actions, details).
struct AvatarToolsButton: View {
    let tools: AnyView
    @State private var showing = false
    @FocusState private var focused: Bool
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold))
                .foregroundStyle(showing ? Color.accentColor : .secondary).frame(width: 26, height: 26)
                .background(showing ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.06), in: Circle())
        }
        .pointingHand().buttonStyle(.plain).help("Conversation").accessibilityLabel("Conversation tools")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ScrollView { tools.padding(18).frame(width: 300, alignment: .leading) }.frame(maxHeight: 480)
                .environment(\.colorScheme, .light).tint(.blue)
                .focusable().focused($focused).onAppear { focused = true }
                .avatarPopoverDismissal(isPresented: $showing)
        }
    }
}

/// A row of the iMessage + menu: a round coloured icon, the title (and a line of help), and
/// whatever sits at its end (a switch, a chevron).
struct AvatarMenuRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(color, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color(white: 0.08))
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.layoutPriority(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
    }
}
extension AvatarMenuRow where Trailing == EmptyView {
    init(icon: String, color: Color, title: String, detail: String? = nil) {
        self.init(icon: icon, color: color, title: title, detail: detail) { EmptyView() }
    }
}
