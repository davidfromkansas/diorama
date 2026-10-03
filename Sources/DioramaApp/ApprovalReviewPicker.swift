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
    @State private var showing = false
    @FocusState private var popoverFocused: Bool
    @State private var proposedBoundaryChange: ApprovalReviewChoice?
    private var effective: ApprovalReviewChoice? {
        if claude { return .claude(policy.string) }
        if sandbox["type"].string == "workspaceWrite", policy.string == "on-request" {
            return reviewer == "auto_review" ? .autoReview : reviewer == "user" ? .user : nil
        }
        return .reported(reviewer: reviewer, policy: policy, sandbox: sandbox)
    }
    private var displayed: ApprovalReviewChoice? { selection != .inherit ? selection : effective ?? (isNew ? .autoReview : nil) }
    private var label: String {
        if unconfirmed && selection == .inherit { return "Permissions unconfirmed" }
        let title = displayed.map { claude && $0 == .fullAccess ? "Bypass permissions" : $0.title }
            ?? (claude && policy.string == "dontAsk" ? "Deny requests that need approval" : claude && policy.string == "plan" ? "Plan Mode" : policy == .null ? "Permissions unconfirmed" : "Custom provider settings")
        return title + (selection != .inherit ? " · Next message" : isNew && effective == nil ? " · Default" : stale ? " · Last reported" : "")
    }
    var body: some View {
        Button { showing.toggle() } label: {
            ViewThatFits(in: .horizontal) {
                Label(label, systemImage: "hand.raised").font(.caption).lineLimit(1).fixedSize()
                Image(systemName: "hand.raised").font(.system(size: 17)).frame(width: 30, height: 30)
            }
        }.pointingHand().buttonStyle(.borderless).accessibilityLabel("Permissions: \(label)").help(label)

            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 8) {
                    PermissionsMenu(selected: displayed, pending: selection != .inherit, claude: claude, supportsAutoMode: supportsAutoMode, unavailable: unavailable) { choice in
                        if !claude && !isNew && choice != .inherit && (choice == .fullAccess || sandbox["type"].string == "dangerFullAccess" || effective == nil) {
                            proposedBoundaryChange = choice
                        } else { selection = choice; showing = false }
                    }
                    if let notice { Text(notice).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                    if let choice = proposedBoundaryChange {
                        Text(choice == .fullAccess ? "This removes Codex’s filesystem and network sandbox boundaries." : "This selects workspace write access. Existing managed restrictions still apply; custom boundaries may differ.").font(.caption)
                        HStack { Button("Cancel") { proposedBoundaryChange = nil }.pointingHand(); Button("Use \(choice.title)") { selection = choice; proposedBoundaryChange = nil; showing = false }.pointingHand() }
                    }
                    if policy != .null {
                        Text(claude ? "Claude mode: \(policy.string ?? policy.pretty)" : "Reviewer: \(reviewer ?? "unconfirmed") · Network: \(sandbox["networkAccess"] == .bool(true) ? "enabled" : sandbox["networkAccess"] == .bool(false) ? "restricted" : "provider settings")")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                }.padding(.bottom, 8)
                    .focusable().focused($popoverFocused).onAppear { popoverFocused = true }
                    .avatarPopoverDismissal(isPresented: $showing)
            }
    }
}

struct PermissionsMenu: View {
    let selected: ApprovalReviewChoice?
    let pending: Bool
    var claude = false
    var supportsAutoMode: Bool? = nil
    var unavailable: [ApprovalReviewChoice: String] = [:]
    let choose: (ApprovalReviewChoice) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(claude ? "Claude permissions" : "Codex permissions").font(.headline).padding(12)
            row(.autoReview, subtitle: claude ? "Claude reviews eligible actions automatically" : "Codex reviews eligible requests automatically", unavailable: supportsAutoMode == false ? "Automatic review is unavailable for this model" : nil)
            row(.user, subtitle: "Show requests requiring your approval")
            if claude { row(.acceptEdits, subtitle: "Accept supported file operations; commands may still ask") }
            row(.fullAccess, subtitle: claude ? "Bypass normal checks; provider rules still apply" : "Remove filesystem and network sandbox restrictions")
            if selected == nil { Text("Using provider settings · preset not confirmed").font(.caption).foregroundStyle(.secondary).padding(12) }
            if pending { HStack { Text("Applies with your next message"); Spacer(); Button("Undo choice") { choose(.inherit) }.pointingHand() }.font(.caption).padding(12) }
        }.padding(8).frame(width: 440)
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
