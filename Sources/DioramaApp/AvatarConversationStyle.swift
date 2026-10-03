import SwiftUI
import DioramaCore

private struct OpaqueMessagesPopoversKey: EnvironmentKey { static let defaultValue = false }
private struct AvatarMessagesKey: EnvironmentKey { static let defaultValue = false }
private struct AvatarConversationToolsKey: EnvironmentKey { static var defaultValue: AnyView { AnyView(EmptyView()) } }
private struct AvatarOutgoingKey: EnvironmentKey { static let defaultValue = false }
private struct AvatarBubbleTailKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var opaqueMessagesPopovers: Bool {
        get { self[OpaqueMessagesPopoversKey.self] }
        set { self[OpaqueMessagesPopoversKey.self] = newValue }
    }
    var avatarOutgoing: Bool {
        get { self[AvatarOutgoingKey.self] }
        set { self[AvatarOutgoingKey.self] = newValue }
    }
    var avatarMessages: Bool {
        get { self[AvatarMessagesKey.self] }
        set { self[AvatarMessagesKey.self] = newValue }
    }
    var avatarConversationTools: AnyView {
        get { self[AvatarConversationToolsKey.self] }
        set { self[AvatarConversationToolsKey.self] = newValue }
    }
    var avatarBubbleTail: Bool {
        get { self[AvatarBubbleTailKey.self] }
        set { self[AvatarBubbleTailKey.self] = newValue }
    }
}

enum AvatarMessagePresentation {
    private static let fractionalDates: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    private static let wholeDates = ISO8601DateFormatter()
    static func date(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return fractionalDates.date(from: timestamp) ?? wholeDates.date(from: timestamp)
    }
    static func separator(before index: Int, entries: [Entry], calendar: Calendar = .current) -> Date? {
        guard entries.indices.contains(index), let current = date(entries[index].timestamp) else { return nil }
        let previous = entries[..<index].reversed().lazy.compactMap { date($0.timestamp) }.first
        guard let previous else { return current }
        return !calendar.isDate(previous, inSameDayAs: current) || current.timeIntervalSince(previous) >= 300 ? current : nil
    }
    static func tail(after index: Int, entries: [Entry]) -> Bool {
        guard entries.indices.contains(index), entries.indices.contains(index + 1) else { return true }
        return entries[index].category != entries[index + 1].category || separator(before: index + 1, entries: entries) != nil
    }
    static func branch(session: Session, workspaces: [ProjectWorkspace]) -> String {
        let workspace = workspaces.first { $0.threadID == session.sessionID }
        return workspace.flatMap { $0.branch.isEmpty ? nil : $0.branch } ?? "Branch unavailable"
    }
}

struct AvatarMessageBubble: View {
    let entry: Entry
    @Environment(\.avatarBubbleTail) private var tail
    private var outgoing: Bool { entry.category == .user }
    private var fill: Color { outgoing ? Color(red: 0, green: 0.47, blue: 1) : Color(white: 0.91) }
    var body: some View {
        HStack(spacing: 0) {
            if outgoing { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) {
                if let image = entry.image { ToolImagePreview(reference: image) }
                TranscriptContent(text: entry.text)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(outgoing ? .white : Color(white: 0.12))
            .environment(\.avatarOutgoing, outgoing)
            .background(fill, in: AvatarBubbleShape(outgoing: outgoing, tail: tail))
            .containerRelativeFrame(.horizontal, alignment: outgoing ? .trailing : .leading) { width, _ in width * 0.75 }
            .fixedSize(horizontal: false, vertical: true)
            if !outgoing { Spacer(minLength: 0) }
        }
        .help(entry.timestamp ?? entry.kind)
        .accessibilityValue(entry.timestamp ?? "")
        .contextMenu {
            Button("Copy message") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string) }.pointingHand()
            if let timestamp = entry.timestamp { Text(timestamp) }
        }
    }
}

struct AvatarBubbleShape: Shape {
    var outgoing: Bool
    var tail: Bool
    func path(in rect: CGRect) -> Path {
        guard tail else { return Path(roundedRect: rect, cornerRadius: min(20, rect.height / 2)) }
        // Extend the shared bubble silhouette, rather than overlaying a detached spike.
        let path = UserMessageBubble().path(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width + 7, height: rect.height))
        return outgoing ? path : path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }
}

struct AvatarReadOnlyTools: View {
    @Environment(\.avatarConversationTools) private var tools
    @State private var showing = false
    @FocusState private var optionsFocused: Bool
    var body: some View {
        Button { showing.toggle() } label: { Image(systemName: "plus").font(.title3) }.pointingHand()
            .accessibilityLabel("Conversation options")
            .popover(isPresented: $showing) { ScrollView { tools.padding(18).frame(width: 310) }.frame(maxHeight: 480).environment(\.colorScheme, .light)
                    .focusable().focused($optionsFocused).onAppear { optionsFocused = true }
                    .avatarPopoverDismissal(isPresented: $showing)
            }
    }
}

/// Retain a dismissal target through the end of the event so Escape cannot
/// dismiss both a native popover and the spatial surface underneath it.
@MainActor final class AvatarPopoverDismissals {
    private var targets: [(UUID, () -> Void)] = []
    func register(_ id: UUID, dismiss: @escaping () -> Void) {
        remove(id)
        targets.append((id, dismiss))
    }
    func remove(_ id: UUID) { targets.removeAll { $0.0 == id } }
    @discardableResult func dismissTop() -> Bool {
        guard let target = targets.last else { return false }
        target.1()
        return true
    }
}
private struct AvatarPopoverDismissalsKey: EnvironmentKey {
    static let defaultValue: AvatarPopoverDismissals? = nil
}
extension EnvironmentValues {
    var avatarPopoverDismissals: AvatarPopoverDismissals? {
        get { self[AvatarPopoverDismissalsKey.self] }
        set { self[AvatarPopoverDismissalsKey.self] = newValue }
    }
}
private struct AvatarPopoverDismissal: ViewModifier {
    @Environment(\.avatarPopoverDismissals) private var targets
    @Binding var isPresented: Bool
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content.modifier(MessagesPopoverSurface()).onAppear { targets?.register(id) { isPresented = false } }
            .onExitCommand {
                if targets?.dismissTop() != true { isPresented = false }
            }
            .onDisappear {
                let target = targets, identity = id
                DispatchQueue.main.async { target?.remove(identity) }
            }
    }
}
extension View {
    func avatarPopoverDismissal(isPresented: Binding<Bool>) -> some View {
        modifier(AvatarPopoverDismissal(isPresented: isPresented))
    }
}

/// Set the native presentation surface as well as SwiftUI's content appearance.
/// A color-scheme environment alone leaves AppKit's translucent popover material intact.
private struct MessagesPopoverSurface: ViewModifier {
    @Environment(\.opaqueMessagesPopovers) private var opaque
    func body(content: Content) -> some View {
        if opaque {
            content.background(Color.white)
                .presentationBackground(Color.white)
                .preferredColorScheme(.light)
                .environment(\.colorScheme, .light)
                .tint(.blue)
        } else { content }
    }
}
