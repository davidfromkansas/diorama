import Foundation
import Testing
@testable import DioramaCore

struct ContinuousTranscriptTests {
    func entry(_ id: String, _ text: String, turn: String, item: String) -> Entry {
        Entry(id: id, kind: "Assistant", text: text, timestamp: nil, turnID: turn, providerItemID: item)
    }
    @Test func localCodexFallbackUsesProviderItemsWithoutDuplicateMessages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        var rows: [[String: Any]] = []
        for turn in ["one", "two"] {
            rows += [
                ["type": "event_msg", "payload": ["type": "task_started", "turn_id": turn]],
                ["type": "response_item", "payload": ["type": "message", "id": "model-user-" + turn, "role": "user", "content": [["type": "input_text", "text": "hello"]]]],
                ["type": "event_msg", "payload": ["type": "item_completed", "turn_id": turn, "item": ["type": "UserMessage", "id": "ui-user-" + turn, "content": [["type": "text", "text": "hello"]]]]],
                ["type": "event_msg", "payload": ["type": "item_completed", "turn_id": turn, "item": ["type": "AgentMessage", "id": "assistant-" + turn, "content": [["type": "Text", "text": "ready"]]]]],
                ["type": "response_item", "payload": ["type": "message", "id": "assistant-" + turn, "role": "assistant", "content": [["type": "output_text", "text": "ready"]]]]
            ]
        }
        let data = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try Data(data.utf8).write(to: url)
        let saved = SessionLibrary.readTranscript(url: url, provider: .codex)
        #expect(saved.entries.filter { $0.kind == "You" }.count == 2)
        #expect(saved.entries.filter { $0.kind == "Assistant" }.count == 2)
        var live = Transcript()
        live.entries = [Entry(id: "live-user", kind: "You", text: "hello", timestamp: nil, turnID: "two", providerItemID: "ui-user-two"), entry("live-assistant", "ready", turn: "two", item: "assistant-two")]
        let merged = saved.mergingLive(live)
        #expect(merged.entries.filter { $0.kind == "You" }.count == 2)
        #expect(merged.entries.filter { $0.kind == "Assistant" }.count == 2)
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
