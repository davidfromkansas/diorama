import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationHistoryTests {
    private func command(_ id: String, status: String = "completed", turn: String = "turn") -> Entry {
        var entry = Entry(id: id, kind: "Tool call", text: "", timestamp: nil)
        entry.turnID = turn
        entry.tool = ToolResult(item: .object(["type": .string("commandExecution"), "command": .string("swift test"), "status": .string(status)]))
        return entry
    }
    @Test func conversationGroupsConsecutiveToolsWithoutSwallowingMessagesOrFailures() {
        let message = Entry(id: "message", kind: "Assistant", text: "Checking the result.", timestamp: nil)
        let entries = [command("a"), command("b"), message, command("failed", status: "failed"), command("c")]
        let rows = ConversationHistory.rows(entries, mode: .conversation)
        #expect(rows.map(\.id) == ["a", "message", "failed", "c"])
        #expect(rows[0].entries.count == 2)
        #expect(!rows[2].grouped)
        #expect(ConversationHistory.rows(entries, mode: .detailed).flatMap(\.entries) == entries)
    }
    @Test func metadataRemainsAvailableWithoutPollutingConversation() {
        var usage = Entry(id: "usage", kind: "Usage", text: "", timestamp: nil)
        usage.codex = CodexPresentation(category: "usageRecord", title: "Usage")
        let context = Entry(id: "context", kind: "System context", text: "Context", timestamp: nil)
        let entries = [command("a"), usage, context]
        let rows = ConversationHistory.rows(entries, mode: .conversation)
        #expect(rows.count == 1)
        #expect(ConversationHistory.isUsage(usage))
        #expect(ConversationHistory.rows(entries, mode: .detailed).count == 3)
        #expect(ConversationHistory.anchor("usage", in: rows, original: entries) == "a")
    }
    @Test func groupsRetainIdentityAsActivityArrivesAndRespectTurnBoundaries() {
        let initial = ConversationHistory.rows([command("a")], mode: .conversation)
        let updated = ConversationHistory.rows([command("a"), command("b"), command("c", turn: "next")], mode: .conversation)
        #expect(initial[0].id == updated[0].id)
        #expect(updated.count == 2)
        #expect(ConversationHistory.anchor("b", in: updated) == "a")
    }
    @Test func questionsPlansArtifactsAndNonzeroExitsStayVisible() {
        var question = command("question")
        question.tool = ToolResult(item: .object(["type": .string("functionCall"), "name": .string("functions.request_user_input_async"), "status": .string("completed")]))
        #expect(!ConversationHistory.canGroup(question))
        let plan = Entry(id: "plan", kind: "Proposed plan", text: "A plan", timestamp: nil)
        #expect(!ConversationHistory.canGroup(plan))
        var failure = command("exit")
        failure.tool = ToolResult(item: .object(["type": .string("commandExecution"), "status": .string("completed"), "exitCode": .number(1)]))
        #expect(!ConversationHistory.canGroup(failure))
        var claude = command("claude")
        claude.tool = nil
        claude.claude = ClaudePresentation(title: "Question", status: "Awaiting approval", callID: "q")
        #expect(!ConversationHistory.canGroup(claude))
        claude.claude?.status = "Completed"
        claude.claude?.outputs = [ClaudeOutput(id: "file", name: "Result", kind: "html")]
        #expect(!ConversationHistory.canGroup(claude))
    }
}
