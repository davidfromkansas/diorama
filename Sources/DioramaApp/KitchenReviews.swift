import Foundation
import Observation

/// Review state of each conversation's finished work, so the chef keeps waiting at the serving
/// window until you decide, even across restarts. Keyed by conversation id; a new finished turn
/// (new completion key) starts a fresh review.
@Observable @MainActor final class KitchenReviews {
    enum State: String, Codable {
        /// Finished; waiting for your decision at the serving window.
        case awaiting
        /// Committed locally; still at the window for push or merge.
        case committed
        /// A pull request is open; still at the window until it merges or you mark it done.
        case shipped
        /// Done or merged: the chef celebrates and goes to the break room.
        case approved
        /// You sent feedback: the chef heads back to work before the new turn is reported, rather
        /// than looking idle in the meantime. The new turn's live activity replaces this.
        case reworking
    }
    struct Entry: Codable, Equatable {
        var state: State
        var completionKey: String
        var note: String? = nil
    }
    static let shared = KitchenReviews()
    private(set) var entries: [String: Entry] = [:]
    private let defaults: UserDefaults
    private static let key = "kitchenReviews.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) { entries = saved }
    }

    func state(_ conversation: String) -> State? { entries[conversation]?.state }
    var states: [String: State] { entries.mapValues(\.state) }

    /// Records newly finished work and clears reviews whose agent went back to work.
    /// How recently finished work, never reviewed, still goes to the serving window.
    static let recentWindow: TimeInterval = 12 * 3600
    func observe(_ agents: [SpatialAgent], now: Date = Date()) {
        var next = entries
        for agent in agents where agent.value.isMain {
            let value = agent.value
            let fresh = value.freshness == .live || value.freshness == .recentlyObserved
            if value.status == .working && fresh {
                // Feedback (or any new turn) sends the chef back to work; the old review is over.
                next[agent.conversationID] = nil
            } else if value.status == .done && fresh {
                let key = value.completionKey ?? value.meaningfulEventID
                if next[agent.conversationID]?.completionKey != key {
                    next[agent.conversationID] = Entry(state: .awaiting, completionKey: key)
                }
            } else if value.status == .done, next[agent.conversationID] == nil,
                      let finished = value.meaningfulUpdatedAt ?? value.observedAt, now.timeIntervalSince(finished) < Self.recentWindow {
                // Finished recently while nobody was watching (the kitchen was paused, the app
                // closed): its dish still waits for review. Older work stays in the break room.
                next[agent.conversationID] = Entry(state: .awaiting, completionKey: value.completionKey ?? value.meaningfulEventID)
            }
        }
        guard next != entries else { return }
        // Recorded outside the current view update.
        DispatchQueue.main.async { [self] in entries = next; save() }
    }

    func set(_ conversation: String, _ state: State, note: String? = nil) {
        guard var entry = entries[conversation] else {
            entries[conversation] = Entry(state: state, completionKey: "manual:" + UUID().uuidString, note: note); save(); return
        }
        entry.state = state; if let note { entry.note = note }
        entries[conversation] = entry; save()
    }
    func clear(_ conversation: String) { entries[conversation] = nil; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}
