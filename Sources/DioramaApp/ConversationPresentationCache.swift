import Foundation
import DioramaCore
/// Window-owned, disposable presentation data. No views, observers, or agent tasks
/// are retained when a conversation leaves the screen.
@MainActor final class ConversationPresentationCache {
    private final class Snapshot {
        let transcript: Transcript
        init(_ transcript: Transcript) { self.transcript = transcript }
    }
    private let snapshots = NSCache<NSString, Snapshot>()
    private let prepared = NSCache<NSString, ConversationRowCache>()
    private let merges = NSCache<NSString, ConversationTranscriptCache>()

    init() {
        snapshots.countLimit = 12
        snapshots.totalCostLimit = 24 * 1024 * 1024
        prepared.countLimit = 12
        merges.countLimit = 12
    }

    func save(_ transcript: Transcript, for id: String) {
        // Text cost is a budget estimate; underlying values remain copy-on-write.
        let cost = transcript.entries.reduce(0) { $0 + $1.text.utf8.count + 512 }
        snapshots.setObject(Snapshot(transcript), forKey: id as NSString, cost: cost)
    }

    func transcript(for id: String) -> Transcript? {
        snapshots.object(forKey: id as NSString)?.transcript
    }

    func rows(for id: String) -> ConversationRowCache {
        if let cached = prepared.object(forKey: id as NSString) { return cached }
        let value = ConversationRowCache()
        prepared.setObject(value, forKey: id as NSString)
        return value
    }

    func merger(for id: String) -> ConversationTranscriptCache {
        if let cached = merges.object(forKey: id as NSString) { return cached }
        let value = ConversationTranscriptCache()
        merges.setObject(value, forKey: id as NSString)
        return value
    }
}
