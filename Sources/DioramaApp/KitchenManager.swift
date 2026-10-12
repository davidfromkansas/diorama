import Foundation

/// The manager's rounds: whom the head chef talks with. A chef that struck the gong and is
/// waiting behind it gets a visit; the manager stays until that chef stops waiting (you answered),
/// then moves on to whoever has waited longest, and leaves when nobody is waiting.
nonisolated enum KitchenManager {
    struct Waiting: Equatable {
        let id: String
        /// When it got to its spot behind the gong.
        let since: Double
    }
    /// Whom to be with next: the current chef while it still waits, else the longest waiting;
    /// nil sends the manager back out.
    static func next(current: String?, waiting: [Waiting]) -> String? {
        if let current, waiting.contains(where: { $0.id == current }) { return current }
        return waiting.min { ($0.since, $0.id) < ($1.since, $1.id) }?.id
    }
}
