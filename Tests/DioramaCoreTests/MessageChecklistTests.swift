import Foundation
import Testing
@testable import DioramaCore

struct MessageChecklistTests {
    @Test func readsTheLastMarkdownChecklistInAMessage() throws {
        let text = """
        Plan first:
        - [ ] Read files
        - [ ] Add tests

        Progress so far:
        - [x] Read files.
        * [X] Add tests.
        1. [ ] Run `npm test`
        Done for now.
        """
        let plan = try #require(MessageChecklist.plan(text))
        #expect(plan.array.map { $0["step"].string } == ["Read files.", "Add tests.", "Run `npm test`"])
        #expect(plan.array.map { $0["status"].string } == ["completed", "completed", "pending"])
        // A single checkbox or plain bullets are not a checklist.
        #expect(MessageChecklist.plan("- [x] Done") == nil)
        #expect(MessageChecklist.plan("- one\n- two") == nil)
    }

    @Test func codexMessagesReportProgressLikeThePlanTool() {
        var snapshot = SessionActivitySnapshot()
        SessionActivityReducer.ingest(.object(["method": .string("turn/started"), "params": .object(["turn": .object(["id": .string("t")])])]), provider: .codex, sessionID: "s", into: &snapshot)
        SessionActivityReducer.ingest(.object(["method": .string("item/completed"), "params": .object(["turnId": .string("t"),
            "item": .object(["id": .string("m"), "type": .string("agentMessage"), "text": .string("- [x] Read\n- [ ] Build\n- [ ] Test")])])]),
            provider: .codex, sessionID: "s", into: &snapshot)
        let plan = AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", currentTurn: "t")
        #expect(plan.taskProgress == "1/3" && !plan.tasksPreviousTurn)
    }
}
