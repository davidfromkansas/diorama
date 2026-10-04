import Foundation
import DioramaCore

/// One snapshot per cached conversation. Scrolling must not parse timestamps or merge history.
/// Value equality also catches edits to existing messages, not just appended rows.
@MainActor final class ConversationTranscriptCache {
    private struct Input: Equatable {
        var saved: Transcript
        var live: Transcript?
        var cutoff: Date?
    }
    private var input: Input?
    private var output = Transcript()
    private(set) var revision = 0

    func merged(saved: Transcript, live: Transcript?, claudeCutoff: Date?) -> Transcript {
        let next = Input(saved: saved, live: live, cutoff: claudeCutoff)
        guard next != input else { return output }
        var value = saved
        if let live {
            if let cutoff = claudeCutoff {
                value.entries.removeAll { entry in
                    guard let date = AvatarMessagePresentation.date(entry.timestamp) else { return false }
                    return date >= cutoff
                }
            }
            value = value.mergingLive(live)
        }
        input = next
        output = value
        revision += 1
        return value
    }
}
