import SwiftUI
import DioramaCore

struct ApprovalReviewPicker: View {
    @Binding var selection: ApprovalReviewChoice
    let reviewer: String?
    let policy: WireValue
    var sandbox: WireValue = .null
    var iconOnly = false
    var claude = false
    var isNew = false
    var supportsAutoMode: Bool? = nil
    var unavailable: [ApprovalReviewChoice: String] = [:]
    var stale = false
    var unconfirmed = false
    var notice: String? = nil
    /// iMessage style: a capsule above the message field, amber while unconfirmed.
    var capsule = false
    /// iMessage style while connecting: the mode last set in Diorama, shown until the provider reports.
    var lastKnown: ApprovalReviewChoice? = nil
    /// iMessage + menu: drawn as the menu's Permissions row (tapping opens the modes) …
    var menuRow: (() -> Void)? = nil
    /// … or as the list of modes itself, inside that menu; called once a mode is chosen.
    var inlineDone: (() -> Void)? = nil
    @State private var showing = false
    @State private var defaults = ProviderDefaultsStore.shared
    private var provider: Provider { claude ? .claude : .codex }
    private var providerName: String { claude ? "Claude" : "Codex" }
    @FocusState private var popoverFocused: Bool
    @State private var proposedBoundaryChange: ApprovalReviewChoice?
    private var effective: ApprovalReviewChoice? {
        if claude { return .claude(policy.string) }
        if sandbox["type"].string == "workspaceWrite", policy.string == "on-request" {
            return reviewer == "auto_review" ? .autoReview : reviewer == "user" ? .user : nil
        }
        return .reported(reviewer: reviewer, policy: policy, sandbox: sandbox)
    }
    /// Something to tell you about (a change that didn't apply): shown amber. It never blocks
    /// Send; with nothing chosen, messages go out in your Codex or Claude default.
    var unsettled: Bool { notice != nil }
    private var displayed: ApprovalReviewChoice? { selection != .inherit ? selection : lastKnown ?? effective ?? (isNew ? defaults.choice(provider) : nil) }
    private var label: String {
        if let lastKnown, selection == .inherit { return claude && lastKnown == .fullAccess ? "Bypass permissions" : lastKnown.title }
        // Nothing reported yet: the conversation runs in your provider default.
        if selection == .inherit, policy == .null, !isNew || defaults.choice(provider) == nil { return providerName + " default" }
        let title = displayed.map { claude && $0 == .fullAccess ? "Bypass permissions" : $0.title }
            ?? (claude && policy.string == "dontAsk" ? "Deny requests that need approval" : claude && policy.string == "plan" ? "Plan Mode" : "Custom provider settings")
        return title + (selection != .inherit ? " · Next message" : isNew && effective == nil ? " · Your default" : stale ? " · Last reported" : "")
    }
    var body: some View {
        if let menuRow { row(menuRow) }
        else if let inlineDone { modes(close: inlineDone) }
        else { button }
    }
    /// The + menu's Permissions row: the mode in force, or what to do when Send is blocked.
    private func row(_ open: @escaping () -> Void) -> some View {
        let amber = Color(red: 0.7, green: 0.37, blue: 0)
        let detail = unsettled ? "The last change wasn’t confirmed" : nil
        let value = stale && lastKnown == nil && selection == .inherit && policy == .null ? providerName + " default" : label
        return Button(action: open) {
            AvatarMenuRow(icon: "hand.raised", color: unsettled ? .orange : Color(red: 0.37, green: 0.36, blue: 0.9), title: "Permissions", detail: detail) {
                HStack(spacing: 4) {
                    Text(value).font(.system(size: 13)).foregroundStyle(unsettled ? amber : .secondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
        }.buttonStyle(.plain).pointingHand().accessibilityLabel("Permissions: \(value)")
    }
    private var button: some View {
        Button { showing.toggle() } label: {
            if capsule {
                Label {
                    HStack(spacing: 4) { Text(label).lineLimit(1).truncationMode(.tail); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
                } icon: { Image(systemName: "hand.raised").font(.system(size: 10)) }
                .labelStyle(AvatarCapsuleLabelStyle()).font(.system(size: 11.5, weight: .medium))
                .modifier(PermissionCapsule(open: showing, warning: unsettled))
            } else {
                ViewThatFits(in: .horizontal) {
                    Label(label, systemImage: "hand.raised").font(.caption).lineLimit(1).fixedSize()
                    Image(systemName: "hand.raised").font(.system(size: 17)).frame(width: 30, height: 30)
                }
            }
        }.pointingHand().buttonStyle(capsule ? AnyButtonStyle(.plain) : AnyButtonStyle(.borderless)).accessibilityLabel("Permissions: \(label)").help(label)

            .popover(isPresented: $showing) {
                modes(close: { showing = false }).padding(.bottom, 8)
                    .focusable().focused($popoverFocused).onAppear { popoverFocused = true }
                    .avatarPopoverDismissal(isPresented: $showing)
            }
    }
    /// Every mode, the current one checked, with the notes and confirmations that go with them.
    private func modes(close: @escaping () -> Void) -> some View {
                VStack(alignment: .leading, spacing: 8) {
                    PermissionsMenu(selected: displayed, pending: selection != .inherit, claude: claude, supportsAutoMode: supportsAutoMode, unavailable: unavailable, compact: inlineDone != nil) { choice in
                        if !claude && !isNew && choice != .inherit && (choice == .fullAccess || sandbox["type"].string == "dangerFullAccess" || effective == nil) {
                            proposedBoundaryChange = choice
                        } else { selection = choice; close() }
                    }
                    if let notice { Text(notice).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                    else if capsule && lastKnown != nil && selection == .inherit {
                        Text("Connecting… This is the mode last set in Diorama.")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    if let choice = proposedBoundaryChange {
                        Text(choice == .fullAccess ? "This removes Codex’s filesystem and network sandbox boundaries." : "This selects workspace write access. Existing managed restrictions still apply; custom boundaries may differ.").font(.caption)
                        HStack { Button("Cancel") { proposedBoundaryChange = nil }.pointingHand(); Button("Use \(choice.title)") { selection = choice; proposedBoundaryChange = nil; close() }.pointingHand() }
                    }
                    if policy != .null {
                        Text(claude ? "Claude mode: \(policy.string ?? policy.pretty)" : "Reviewer: \(reviewer ?? "unconfirmed") · Network: \(sandbox["networkAccess"] == .bool(true) ? "enabled" : sandbox["networkAccess"] == .bool(false) ? "restricted" : "provider settings")")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    makeDefault
                }
    }
    /// Your Codex or Claude default: what new chats start in here, in the Codex and Claude apps,
    /// and in the terminal. Offered for the mode shown when it isn't already the default.
    @ViewBuilder private var makeDefault: some View {
        let current = defaults.choice(provider)
        Divider().padding(.horizontal)
        VStack(alignment: .leading, spacing: 6) {
            if let shown = displayed, shown != current, ProviderDefaultsStore.choices(provider).contains(shown) {
                Button {
                    defaults.set(shown, for: provider)
                } label: {
                    Label("Make \u{201C}\(claude && shown == .fullAccess ? "Bypass permissions" : shown.title)\u{201D} my \(providerName) default", systemImage: "star")
                }.buttonStyle(.borderless).pointingHand()
            }
            Text("Your \(providerName) default: \(defaults.label(provider)). New chats start in it here, in the \(providerName) app and in the terminal.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = defaults.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal).padding(.top, 2)
        .onAppear { defaults.reload() }
    }
}

struct PermissionsMenu: View {
    let selected: ApprovalReviewChoice?
    let pending: Bool
    var claude = false
    var supportsAutoMode: Bool? = nil
    var unavailable: [ApprovalReviewChoice: String] = [:]
    /// Inside the iMessage + menu, which supplies its own title and width.
    var compact = false
    let choose: (ApprovalReviewChoice) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !compact { Text(claude ? "Claude permissions" : "Codex permissions").font(.headline).padding(12) }
            row(.autoReview, subtitle: claude ? "Claude reviews eligible actions automatically" : "Codex reviews eligible requests automatically", unavailable: supportsAutoMode == false ? "Automatic review is unavailable for this model" : nil)
            row(.user, subtitle: "Show requests requiring your approval")
            if claude { row(.acceptEdits, subtitle: "Accept supported file operations; commands may still ask") }
            row(.fullAccess, subtitle: claude ? "Bypass normal checks; provider rules still apply" : "Remove filesystem and network sandbox restrictions")
            if selected == nil { Text("Using your \(claude ? "Claude" : "Codex") default").font(.caption).foregroundStyle(.secondary).padding(12) }
            if pending { HStack { Text("Applies with your next message"); Spacer(); Button("Undo choice") { choose(.inherit) }.pointingHand() }.font(.caption).padding(12) }
        }.padding(compact ? 0 : 8).frame(width: compact ? nil : 440)
    }
    private func row(_ choice: ApprovalReviewChoice, subtitle: String, unavailable: String? = nil) -> some View {
        Button { choose(choice) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(claude && choice == .fullAccess ? "Bypass permissions" : choice.title).font(.system(size: 15))
                    Text(self.unavailable[choice] ?? unavailable ?? subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark").opacity(selected == choice ? 1 : 0)
            }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
        }.pointingHand().buttonStyle(.plain).disabled(unavailable != nil || self.unavailable[choice] != nil).help(self.unavailable[choice] ?? unavailable ?? subtitle).accessibilityAddTraits(selected == choice ? [.isSelected] : [])
    }
}

/// The permissions capsule's look: amber while unsettled, blue while its menu is open.
private struct PermissionCapsule: ViewModifier {
    let open: Bool
    let warning: Bool
    func body(content: Content) -> some View {
        let amber = Color(red: 0.7, green: 0.37, blue: 0)
        content.foregroundStyle(open ? Color.accentColor : warning ? amber : Color(white: 0.23))
            .padding(.horizontal, 10).frame(height: 24)
            .background(open ? Color.accentColor.opacity(0.12) : warning ? Color(red: 1, green: 0.96, blue: 0.9) : Color(white: 0.95), in: Capsule())
            .overlay(Capsule().strokeBorder(open ? Color.accentColor : warning ? Color(red: 0.95, green: 0.79, blue: 0.55) : Color.black.opacity(0.06)))
    }
}
/// A button style chosen at run time.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
