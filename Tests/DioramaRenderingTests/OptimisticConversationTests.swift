import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct OptimisticConversationTests {
    @Test func pendingMessageIsVisibleWithoutConnectionOrLoadedHistory() {
        let model = LibraryModel()
        model.outgoing = [:]
        model.execution.tasks["optimistic-test"] = ExecutedTask(id: "optimistic-test", title: "Test", folder: "/tmp", attached: false)
        model.selectOwned("optimistic-test")
        let message = OutgoingMessage(sessionID: "optimistic-test", text: "Instant hello", attachmentPaths: [], baselineIDs: [])
        model.outgoing[message.id] = message
        #expect(model.displayedTranscript.entries.last?.text == "Instant hello")
        #expect(!model.execution.connected)
        #expect(!model.showingLiveTurn)
        model.outgoing[message.id]?.state = .failed
        #expect(model.displayedTranscript.entries.last?.id == message.id)
    }
    @Test func echoReplacesLocalBubbleAndAssistantStaysAfterIt() {
        let model = LibraryModel()
        model.outgoing = [:]
        model.execution.tasks["optimistic-test"] = ExecutedTask(id: "optimistic-test", title: "Test", folder: "/tmp", attached: true)
        model.selectOwned("optimistic-test")
        let message = OutgoingMessage(sessionID: "optimistic-test", text: "Instant hello", attachmentPaths: [], baselineIDs: [])
        model.outgoing[message.id] = message
        model.execution.tasks["optimistic-test"]?.transcript.entries = [Entry(id: "response", kind: "Assistant", text: "Hello back", timestamp: nil)]
        #expect(model.displayedTranscript.entries.map(\.kind) == ["You", "Assistant"])
        model.execution.tasks["optimistic-test"]?.transcript.entries.insert(Entry(id: "echo", kind: "You", text: "Instant hello", timestamp: nil), at: 0)
        #expect(model.displayedTranscript.entries.filter { $0.kind == "You" }.count == 1)
        #expect(model.displayedTranscript.entries.first?.id == "echo")
    }
}
