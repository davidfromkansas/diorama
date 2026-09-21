import Foundation
import Testing
@testable import DioramaCore

struct LiveHookEvidenceTests {
    let evidence = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("evidence")
    @Test func realClaudeToolFailuresAndWorkerIdentityRemainExplicit() throws {
        let hooks = try JSONDecoder().decode([ActivityEvent].self, from: Data(contentsOf: evidence.appendingPathComponent("claude-funded-turn-hooks.json")))
        let failure = try #require(hooks.first { $0.kind == "toolFailed" })
        #expect(failure.detail == "Exit code 1")
        #expect(failure.durationMS != nil)
        #expect(hooks.contains { $0.kind == "toolStarted" && $0.callID == failure.callID })
        #expect(ActivitySummary.merged(hooks).attention.isEmpty)
        #expect(!hooks.contains { $0.state == .blocked || $0.state == .finished })
        let workers = try JSONDecoder().decode([ActivityEvent].self, from: Data(contentsOf: evidence.appendingPathComponent("claude-resume-hooks.json")))
        let start = try #require(workers.first { $0.kind == "agentStarted" })
        let stop = try #require(workers.first { $0.kind == "agentStopped" })
        #expect(start.agentID != nil)
        #expect(start.agentID == stop.agentID)
        #expect(start.sessionID == stop.sessionID)
        #expect(start.role == "general-purpose")
        #expect(stop.state == nil)
    }
    @Test func realClaudePermissionCannotBeResolvedWithoutCorrelation() throws {
        let hooks = try JSONDecoder().decode([ActivityEvent].self, from: Data(contentsOf: evidence.appendingPathComponent("claude-permission-hooks.json")))
        let approval = try #require(hooks.first { $0.kind == "approval" })
        #expect(approval.callID == nil)
        #expect(approval.turnID == nil)
        // The CLI denied the request, but these hooks don't identify its resolution.
        #expect(ActivitySummary.merged(hooks).attention.count == 1)
    }
    @Test func observedQuestionMetadataAndIdleNotificationAreRecognized() throws {
        let captured = try JSONDecoder().decode([ActivityEvent].self, from: Data(contentsOf: evidence.appendingPathComponent("claude-interactive-hooks.json")))
        let question = try #require(captured.first { $0.tool == "AskUserQuestion" && $0.kind == "toolStarted" })
        let callID = try #require(question.callID)
        // Reconstruct only the allowlisted fields observed in the live PreToolUse event.
        let parsed = try #require(ActivityParser.hook(["hook_event_name": "PreToolUse", "session_id": question.sessionID,
                                                      "tool_name": "AskUserQuestion", "tool_use_id": callID], provider: .claude, now: question.observedAt))
        #expect(parsed.state == .input)
        #expect(parsed.source.contains("PreToolUse"))
        let answered = try #require(captured.first { $0.kind == "toolFinished" && $0.callID == question.callID })
        #expect(ActivitySummary.merged([parsed, answered]).attention.isEmpty)
        #expect(captured.contains { $0.kind == "idle" && $0.state == .idle })
        #expect(!captured.contains { $0.kind == "interrupted" })
    }
    @Test func realCodexApprovalResolvesOnlyWithRecordedTurnCompletion() throws {
        let pending = try JSONDecoder().decode(ActivityEvent.self, from: Data(contentsOf: evidence.appendingPathComponent("codex-approval-pending.json")))
        let hooks = try JSONDecoder().decode([ActivityEvent].self, from: Data(contentsOf: evidence.appendingPathComponent("codex-approved-turn-hooks.json")))
        #expect(pending.state == .approval)
        #expect(ActivitySummary.merged(hooks).attention.count == 1)
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: evidence.appendingPathComponent("codex-approved-turn-lifecycle.json"))) as? [[String: Any]])
        let session = Session(id: pending.sessionID, provider: .codex, url: URL(fileURLWithPath: "/fixture"), sessionID: pending.sessionID,
                              title: "Probe", project: "/fixture", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let transcript = raw.enumerated().flatMap { ActivityParser.transcript($0.element, session: session, id: "fixture-\($0.offset)", now: Date()) }
        let result = ActivitySummary.merged(hooks + transcript)
        #expect(result.state == .finished)
        #expect(result.attention.isEmpty)
    }
}
