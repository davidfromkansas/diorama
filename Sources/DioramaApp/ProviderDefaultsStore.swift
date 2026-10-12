import SwiftUI
import DioramaCore

/// Your Codex and Claude default permission modes, read from their own settings files, so
/// Diorama shows what the Codex and Claude apps start new chats in, and can change it.
@Observable @MainActor final class ProviderDefaultsStore {
    static let shared = ProviderDefaultsStore()
    private(set) var codex: ApprovalReviewChoice?
    private(set) var claude: ApprovalReviewChoice?
    /// Why the last change didn't save, if it didn't.
    var error: String?
    private let files: ProviderPermissionDefaults
    init(files: ProviderPermissionDefaults = ProviderPermissionDefaults()) { self.files = files; reload() }

    func choice(_ provider: Provider) -> ApprovalReviewChoice? { provider == .claude ? claude : codex }
    /// Re-read the files: the Codex or Claude tools may have changed them.
    func reload() {
        let codex = files.choice(for: .codex), claude = files.choice(for: .claude)
        if self.codex != codex { self.codex = codex }
        if self.claude != claude { self.claude = claude }
    }
    func set(_ choice: ApprovalReviewChoice, for provider: Provider) {
        do { try files.set(choice, for: provider); error = nil } catch { self.error = error.localizedDescription }
        reload()
    }
    /// "Approve for me" for a preset, else "Codex default" / "Claude default".
    func label(_ provider: Provider) -> String {
        guard let choice = choice(provider) else { return Self.providerDefault(provider) }
        return provider == .claude && choice == .fullAccess ? "Bypass permissions" : choice.title
    }
    static func providerDefault(_ provider: Provider) -> String { provider == .claude ? "Claude default" : "Codex default" }
    /// The modes each provider can start in by default.
    static func choices(_ provider: Provider) -> [ApprovalReviewChoice] {
        provider == .claude ? [.autoReview, .user, .acceptEdits, .fullAccess] : [.autoReview, .user, .fullAccess]
    }
}
