import SwiftUI
import DioramaCore

struct ApprovalReviewPicker: View {
    @Binding var selection: ApprovalReviewChoice
    let reviewer: String?
    let policy: WireValue
    var sandbox: WireValue = .null
    var iconOnly = false
    var claude = false
    @State private var showing = false
    private var effective: ApprovalReviewChoice? {
        if claude { return policy.string == "bypassPermissions" ? .fullAccess : policy.string == "auto" ? .autoReview : policy.string == "default" || policy.string == "manual" ? .user : nil }
        return ApprovalReviewChoice.reported(reviewer: reviewer, policy: policy, sandbox: sandbox)
    }
    private var displayed: ApprovalReviewChoice? { selection == .inherit ? effective : selection }
    var body: some View {
        Button { showing.toggle() } label: {
            if iconOnly {
                Image(systemName: displayed == .fullAccess ? "exclamationmark.shield" : displayed == .autoReview ? "checkmark.shield" : "hand.raised")
                    .font(.system(size: 17)).frame(width: 30, height: 30)
                    .foregroundStyle(displayed == .fullAccess ? Color.orange : Color.secondary)
            } else {
                Text(displayed?.title ?? "Agent permissions").font(.caption)
            }
        }.buttonStyle(.borderless)
            .accessibilityLabel("Permissions: \(displayed?.title ?? "Agent settings")")
            .help(selection == .inherit ? (displayed?.title ?? "Agent permissions") : "\(selection.title) · next message")
            .popover(isPresented: $showing) {
                PermissionsMenu(selected: displayed, pending: selection != .inherit, claude: claude) { choice in
                    selection = choice; showing = false
                }
            }
    }
}

struct PermissionsMenu: View {
    let selected: ApprovalReviewChoice?
    let pending: Bool
    var claude = false
    let choose: (ApprovalReviewChoice) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(claude ? "How should Claude actions be approved?" : "How should Codex actions be approved?")
                Spacer()
                Link("Learn more", destination: URL(string: claude ? "https://code.claude.com/docs/en/permissions" : "https://learn.chatgpt.com/docs/sandboxing")!).underline()
            }.font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 10)
            row(.user, icon: "hand.raised", subtitle: claude ? "Use Claude’s normal permission prompts" : "Ask before editing external files or using the internet")
            row(.autoReview, icon: "checkmark.shield", subtitle: claude ? "Use Claude’s automatic approval mode when available" : "Let Codex review eligible requests automatically")
            row(.fullAccess, icon: "exclamationmark.shield", subtitle: "Allow unrestricted file and internet access")
            if selected == nil { Text("Using current agent settings · mode not yet confirmed").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 6) }
            if pending {
                HStack {
                    Text("Applies with your next message").foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo choice") { choose(.inherit) }.buttonStyle(.plain)
                }.font(.caption).padding(.horizontal, 12).padding(.top, 6)
            }
        }.padding(8).frame(width: 480)
    }
    private func row(_ choice: ApprovalReviewChoice, icon: String, subtitle: String) -> some View {
        Button { choose(choice) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19)).frame(width: 23)
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.title).font(.system(size: 15))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(choice == .fullAccess ? Color.orange : Color.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark").opacity(selected == choice ? 1 : 0)
            }.foregroundStyle(choice == .fullAccess ? Color.orange : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected == choice ? [.isSelected] : [])
    }
}
