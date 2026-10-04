import Foundation
import DioramaCore

/// Keep typing synchronous in memory; serialize preferences on a serial utility
/// queue after a short pause. A normal close flushes the latest snapshot.
@MainActor final class ConversationDraftPersistence {
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "Diorama.conversation-drafts", qos: .utility)
    private var pending: DispatchWorkItem?
    private var latest: [String: ConversationDraft]?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [String: ConversationDraft] {
        defaults.data(forKey: "conversationDrafts")
            .flatMap { try? JSONDecoder().decode([String: ConversationDraft].self, from: $0) } ?? [:]
    }

    func schedule(_ drafts: [String: ConversationDraft]) {
        pending?.cancel()
        latest = drafts
        let defaults = defaults
        let work = Self.writeWork(drafts, defaults: defaults)
        pending = work
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }

    func flush() {
        pending?.cancel(); pending = nil
        guard let drafts = latest else { return }
        latest = nil
        let defaults = defaults
        queue.sync(execute: Self.writeWork(drafts, defaults: defaults))
    }

    // Construct outside MainActor isolation as well as executing outside it.
    // DispatchWorkItem's legacy closure otherwise inherits the caller's actor.
    private nonisolated static func writeWork(_ drafts: [String: ConversationDraft], defaults: UserDefaults) -> DispatchWorkItem {
        DispatchWorkItem {
            if let data = try? JSONEncoder().encode(drafts) { defaults.set(data, forKey: "conversationDrafts") }
        }
    }
}
