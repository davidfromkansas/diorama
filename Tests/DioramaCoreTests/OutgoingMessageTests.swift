import Foundation
import Testing
@testable import DioramaCore

struct OutgoingMessageTests {
    @Test func bubbleAppearsBeforeAcknowledgementAndOnlyNewEchoMatches() {
        let old = Entry(id: "old", kind: "You", text: "Hello", timestamp: nil)
        let message = OutgoingMessage(sessionID: "session", text: "Hello", attachmentPaths: [], baselineIDs: [old.id])
        #expect(message.entry.kind == "You")
        #expect(message.entry.text == "Hello")
        #expect(!message.matchingEcho(in: [old]))
        #expect(message.matchingEcho(in: [old, Entry(id: "new", kind: "You", text: "Hello", timestamp: nil)]))
        #expect(!message.matchingEcho(in: [Entry(id: "assistant", kind: "Assistant", text: "Hello", timestamp: nil)]))
    }
    @Test func contextEnvelopeBoundaryWhitespaceDoesNotDuplicateOptimisticBubble() {
        var message = OutgoingMessage(sessionID: "session", text: "hey", attachmentPaths: [], baselineIDs: ["old"])
        message.turnID = "new-turn"
        let parts = MessageContent.split("hey\n<diorama_html_view>\nMaintain this conversation's live HTML view\n</diorama_html_view>", provider: .codex)
        let user = parts.first { !$0.context }!
        #expect(user.text == "hey\n")
        var echo = Entry(id: "new", kind: "You", text: user.text, timestamp: nil)
        echo.turnID = "new-turn"
        #expect(message.matchingEcho(in: [echo]))
        echo.turnID = "previous-turn"
        #expect(!message.matchingEcho(in: [echo]))
        echo.turnID = "new-turn"
        let repeated = OutgoingMessage(sessionID: "session", text: "hey", attachmentPaths: [], baselineIDs: [echo.id])
        #expect(!repeated.matchingEcho(in: [echo]))
        echo.text = "hey there"
        #expect(!message.matchingEcho(in: [echo]))
    }

    @Test func attachmentsAndDeliveryStateSurvivePersistence() throws {
        var message = OutgoingMessage(sessionID: "session", text: "", attachmentPaths: ["/tmp/reference.png"], baselineIDs: [])
        message.state = .uncertain
        let restored = try JSONDecoder().decode(OutgoingMessage.self, from: JSONEncoder().encode(message))
        #expect(restored.state == .uncertain)
        #expect(restored.attachmentPaths == message.attachmentPaths)
        #expect(restored.entry.text.contains("reference.png"))
        #expect(!restored.matchingEcho(in: [Entry(id: "new", kind: "You", text: "[Image attachment]", timestamp: nil)]))
        message.turnID = "confirmed-turn"
        var echo = Entry(id: "new", kind: "You", text: "[Image attachment]", timestamp: nil)
        echo.turnID = "confirmed-turn"
        #expect(message.matchingEcho(in: [echo]))
        echo.turnID = "different-turn"
        #expect(!message.matchingEcho(in: [echo]))
    }
}
