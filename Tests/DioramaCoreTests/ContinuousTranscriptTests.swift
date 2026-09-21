import Testing
@testable import DioramaCore

struct ContinuousTranscriptTests {
    func entry(_ id: String, _ text: String, turn: String, item: String) -> Entry {
        Entry(id: id, kind: "Assistant", text: text, timestamp: nil, turnID: turn, providerItemID: item)
    }
    @Test func overlaysStreamingWithoutDuplicatingSavedItems() {
        var saved = Transcript(); var live = Transcript()
        saved.entries = [entry("old", "Earlier", turn: "1", item: "a"), entry("saved", "Hel", turn: "2", item: "b")]
        live.entries = [entry("live", "Hello", turn: "2", item: "b"), entry("new", "Next", turn: "2", item: "c")]
        let merged = saved.mergingLive(live)
        #expect(merged.entries.map(\.text) == ["Earlier", "Hello", "Next"])
        #expect(merged.mergingLive(live).entries == merged.entries)
    }
    @Test func splitUserContextAndRepeatedMessagesArePreserved() {
        var saved = Transcript(); var live = Transcript()
        saved.entries = [entry("1", "hello", turn: "1", item: "a"), entry("2", "hello", turn: "2", item: "a")]
        live.entries = [entry("3", "context", turn: "3", item: "b"), entry("4", "hello", turn: "3", item: "b")]
        #expect(saved.mergingLive(live).entries.count == 4)
        saved.entries += [entry("5", "old context", turn: "3", item: "b"), entry("6", "hello", turn: "3", item: "b")]
        #expect(saved.mergingLive(live).entries.map(\.text) == ["hello", "hello", "context", "hello"])
    }
    @Test func delayedEarlierLiveTurnStaysBeforeLaterSavedTurn() {
        var saved = Transcript(); var live = Transcript()
        saved.entries = [entry("1", "first", turn: "1", item: "a"), entry("2", "later", turn: "2", item: "a")]
        live.entries = [entry("3", "end first", turn: "1", item: "b")]
        #expect(saved.mergingLive(live).entries.map(\.text) == ["first", "end first", "later"])
    }
}
