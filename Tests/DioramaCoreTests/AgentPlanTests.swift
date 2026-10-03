import Foundation
import Testing
@testable import DioramaCore

struct AgentPlanTests {
    func ingest(_ json: String, _ snapshot: inout SessionActivitySnapshot, provider: Provider = .codex, session: String = "s") throws {
        var event = try JSONDecoder().decode(WireValue.self, from: Data(json.utf8))
        if provider == .claude { event = .object(["method": .string("diorama/claudeActivity"), "params": .object(["event": event])]) }
        SessionActivityReducer.ingest(event, provider: provider, sessionID: session, into: &snapshot)
    }
    @Test func completionAndFailureRetainPlan() throws {
        for status in ["completed", "failed", "interrupted"] {
            var snapshot = SessionActivitySnapshot()
            try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[{"step":"Ship","status":"completed"}]}}"#, &snapshot)
            try ingest("{\"method\":\"turn/completed\",\"params\":{\"turn\":{\"id\":\"t\",\"status\":\"\(status)\"}}}", &snapshot)
            let plan = AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s")
            #expect(plan.hasContent)
            #expect(plan.checklist.first?.status == "completed")
            #expect(!plan.previousTurn)
            #expect(AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", currentTurn: "next").previousTurn)
        }
    }
    @Test func checklistRevisionsAreScopedAndClearable() throws {
        var snapshot = SessionActivitySnapshot()
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[{"step":"Parent","status":"pending"}]}}"#, &snapshot)
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"t","parentID":"child","plan":[{"step":"Child","status":"completed"}]}}"#, &snapshot)
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[]}}"#, &snapshot)
        #expect(!AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s").hasContent)
        #expect(AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", owners: ["child"]).checklist.first?.title == "Child")
        #expect(!AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s", owners: ["child"]).hasContent)
        #expect(!AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "another", owners: ["child"]).hasContent)
    }
    @Test func claudeTaskOwnershipAndFailedUpdates() throws {
        var snapshot = SessionActivitySnapshot()
        try ingest(#"{"type":"assistant","parent_tool_use_id":"child","message":{"content":[{"type":"tool_use","id":"create","name":"TaskCreate","input":{"subject":"Child task"}}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"user","uuid":"created","tool_use_result":{"task":{"id":"1"}},"message":{"content":[{"type":"tool_result","tool_use_id":"create"}]}}"#, &snapshot, provider: .claude)
        #expect(!AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s").hasContent)
        #expect(AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s", owners: ["child"]).checklist.first?.title == "Child task")
        try ingest(#"{"type":"assistant","parent_tool_use_id":"child","message":{"content":[{"type":"tool_use","id":"update","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"user","tool_use_result":{"taskId":"1","statusChange":{"to":"completed"}},"message":{"content":[{"type":"tool_result","tool_use_id":"update","is_error":true}]}}"#, &snapshot, provider: .claude)
        #expect(snapshot.steps.first?.status == "pending")
        try ingest(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"update"}]}}"#, &snapshot, provider: .claude)
        #expect(snapshot.steps.first?.status == "completed")
    }
    @Test func todoWriteKeepsParentSeparateAndExitPlanResult() throws {
        var snapshot = SessionActivitySnapshot()
        try ingest(#"{"type":"assistant","parent_tool_use_id":"child","message":{"content":[{"type":"tool_use","id":"todo","name":"TodoWrite","input":{"todos":[{"content":"Review","status":"completed"}]}},{"type":"tool_use","id":"exit","name":"ExitPlanMode","input":{}}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"todo"}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"user","tool_use_result":{"plan":"Actual proposal"},"message":{"content":[{"type":"tool_result","tool_use_id":"exit"}]}}"#, &snapshot, provider: .claude)
        let child = AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s", owners: ["child"])
        #expect(child.checklist.first?.title == "Review")
        #expect(child.proposal?.detail == "Actual proposal")
        #expect(!AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s").hasContent)
    }
    @Test func finalReplacesDraftAndRejectsLateDelta() throws {
        var snapshot = SessionActivitySnapshot()
        try ingest(#"{"method":"item/plan/delta","params":{"itemId":"p","delta":"Draft"}}"#, &snapshot)
        try ingest(#"{"method":"item/completed","params":{"item":{"id":"p","type":"plan","text":"Final"}}}"#, &snapshot)
        try ingest(#"{"method":"item/plan/delta","params":{"itemId":"p","delta":" late"}}"#, &snapshot)
        #expect(snapshot.plans.first?.detail == "Final")
        try ingest(#"{"method":"item/completed","params":{"item":{"id":"p","type":"plan","text":""}}}"#, &snapshot)
        #expect(!AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s").hasContent)
    }
    @Test func cachedExternalReadTracksUpdatesAndMissingFiles() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let line = #"{"timestamp":"2026-09-30T12:00:00Z","payload":{"type":"function_call","turn_id":"t","name":"update_plan","arguments":"{\"plan\":[{\"step\":\"Saved\",\"status\":\"pending\"}]}"}}"# + "\n"
        try Data(line.utf8).write(to: url)
        let session = Session(id: "s", provider: .codex, url: url, sessionID: "s", title: "Fixture", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let reader = AgentPlanHistory()
        let first = await reader.read(session)
        let plan = AgentPlan.reported(in: first.snapshot, provider: "Codex", sessionID: "s")
        #expect(plan.checklist.first?.title == "Saved"); #expect(plan.updatedAt != nil)
        #expect(plan.checklist.first?.turnID == "t")
        let cached = await reader.read(session)
        #expect(cached.snapshot == first.snapshot)
        try Data(line.replacingOccurrences(of: "pending", with: "completed").utf8).write(to: url)
        let updated = await reader.read(session)
        #expect(updated.snapshot.steps.first?.status == "completed")
        try Data().write(to: url)
        let truncated = await reader.read(session)
        #expect(truncated.snapshot.truncated)
        #expect(truncated.snapshot.steps.first?.status == "completed")
        try FileManager.default.removeItem(at: url)
        let missing = await reader.read(session)
        #expect(missing.unavailable); #expect(missing.snapshot.steps.first?.status == "completed")
    }
}

extension AgentPlanTests {
    @Test func newerChecklistWinsAcrossSeveralTurnsAndExplicitClear() throws {
        var saved = SessionActivitySnapshot(), observed = SessionActivitySnapshot()
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"old","timestamp":"2026-09-29T12:00:00Z","plan":[{"step":"Old","status":"pending"}]}}"#, &observed)
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"new","timestamp":"2026-09-30T12:00:00Z","plan":[{"step":"New","status":"completed"}]}}"#, &saved)
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"new","timestamp":"2026-09-30T12:00:00Z","plan":[{"step":"New","status":"completed"}]}}"#, &observed)
        #expect(AgentPlan.merging(saved, observed).steps.map(\.title) == ["New"])
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"new","timestamp":"2026-09-30T12:01:00Z","plan":[]}}"#, &observed)
        #expect(AgentPlan.merging(saved, observed).steps.isEmpty)
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"old","timestamp":"2026-09-29T12:00:00Z","plan":[{"step":"Old","status":"pending"}]}}"#, &observed)
        #expect(observed.steps.isEmpty)
    }
    @Test func claudeDeletionAndPreviousTurnDoNotInventProgress() throws {
        var snapshot = SessionActivitySnapshot()
        try ingest(#"{"type":"user","uuid":"turn-one","message":{"content":[{"type":"text","text":"Make a plan"}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p","name":"ExitPlanMode","input":{"plan":"Keep the proposal"}}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"user","uuid":"turn-two","message":{"content":[{"type":"text","text":"Continue"}]}}"#, &snapshot, provider: .claude)
        #expect(AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s").previousTurn)
        snapshot.truncated = true
        #expect(AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s").truncated)
        try ingest(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"c","name":"TaskCreate","input":{"subject":"Remove me"}}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"user","tool_use_result":{"task":{"id":"1"}},"message":{"content":[{"type":"tool_result","tool_use_id":"c"}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"d","name":"TaskUpdate","input":{"taskId":"1","status":"deleted"}}]}}"#, &snapshot, provider: .claude)
        try ingest(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"d"}]}}"#, &snapshot, provider: .claude)
        #expect(snapshot.steps.isEmpty)
        #expect(AgentPlan.reported(in: snapshot, provider: "Claude Code", sessionID: "s").hasContent)
    }
}


extension AgentPlanTests {
    @Test func artifactsHaveIndependentAvailabilityAndMetadata() throws {
        var snapshot = SessionActivitySnapshot()
        func projected() -> AgentPlan { AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", currentTurn: "new") }
        #expect(!projected().hasProposal && !projected().hasTasks)
        try ingest(#"{"method":"item/completed","params":{"turnId":"old","timestamp":"2026-09-29T12:00:00Z","item":{"id":"p","type":"plan","text":"Approach"}}}"#, &snapshot)
        #expect(projected().hasProposal && !projected().hasTasks)
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"new","timestamp":"2026-09-30T12:00:00Z","plan":[{"step":"Done","status":"completed"},{"step":"Unknown","status":"custom"}]}}"#, &snapshot)
        let both = projected()
        #expect(both.hasProposal && both.hasTasks)
        #expect(both.taskProgress == "1/2")
        #expect(both.proposalPreviousTurn && !both.tasksPreviousTurn)
        #expect(both.proposalUpdatedAt != both.taskUpdatedAt)
        try ingest(#"{"method":"item/completed","params":{"turnId":"new","item":{"id":"p","type":"plan","text":""}}}"#, &snapshot)
        #expect(!projected().hasProposal && projected().hasTasks)
        try ingest(#"{"method":"turn/plan/updated","params":{"turnId":"new","plan":[]}}"#, &snapshot)
        #expect(!projected().hasContent)
    }
}
