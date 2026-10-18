import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct AgentPlanRenderingTests {
    func evidence(_ status: String = "completed") -> SessionActivitySnapshot {
        var snapshot = SessionActivitySnapshot()
        SessionActivityReducer.ingest(.object(["method": .string("turn/plan/updated"), "params": .object(["turnId": .string("t"), "plan": .array([.object(["step": .string("Inspect provider-reported plans without starting a new turn"), "status": .string(status)])])])]), provider: .codex, sessionID: "s", into: &snapshot)
        SessionActivityReducer.ingest(.object(["method": .string("item/completed"), "params": .object(["item": .object(["id": .string("p"), "type": .string("plan"), "text": .string("## Plan inspection\n\n1. Read the reported checklist.\n2. Inspect the current proposal.\n3. Keep the plan available after completion.\n\nThis is provider-reported content.")])])]), provider: .codex, sessionID: "s", into: &snapshot)
        return snapshot
    }
    func agent(_ id: String = "main") -> WorkspaceAgent {
        var agent = WorkspaceAgent(id: id, name: "Main agent", provider: "Codex", task: "Plan inspection", action: "Finished", status: .done, reportedStatus: "completed", freshness: .lastKnown, observedAt: Date())
        agent.plan = AgentPlan.reported(in: evidence(), provider: "Codex", sessionID: "s")
        return agent
    }
    @Test func externalPlanDiscoveryRequiresNoSelectionOrExecution() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("claude.jsonl")
        let lines = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p","name":"ExitPlanMode","input":{"plan":"Saved Claude proposal"}}]}}"# + "\n"
        try Data(lines.utf8).write(to: url)
        let session = Session(id: "claude:s", provider: .claude, url: url, sessionID: "s", title: "Plan", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        let library = LibraryModel(execution: ExecutionController(), projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")))
        library.sessions = [session]; library.portfolio.register([session])
        await library.planDiscovery.refresh(library.planSources(session))
        let agent = try #require(library.workspaceAgents(session).first)
        #expect(agent.plan?.proposal?.detail == "Saved Claude proposal")
        #expect(library.selectedID == nil); #expect(library.execution.tasks.isEmpty)
    }
}

extension AgentPlanRenderingTests {
    @Test func liveChildAndMergedProviderPlansStaySeparate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = Session(id: "Codex:s", provider: .codex, url: nil, sessionID: "s", title: "Parent", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        let child = Session(id: "Codex:child", provider: .codex, url: nil, sessionID: "child", title: "Child", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: "s", classification: .subagent)
        var snapshot = evidence()
        snapshot.apply(SessionActivityRecord(id: "agent-record", provider: "Codex", sessionID: "s", turnID: nil, nativeID: "child", parentID: "s", kind: "agent", title: "Child", status: "completed", detail: "Inspect", source: "Fixture", recordedAt: Date(), observedAt: Date(), data: .null))
        let execution = ExecutionController()
        execution.observeActivity(parent, snapshot: snapshot)
        let conversations = DioramaConversationModel(file: root.appendingPathComponent("conversations.json"))
        let library = LibraryModel(execution: execution, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), conversations: conversations)
        #expect(library.workspaceAgents(parent).first(where: { !$0.isMain })?.plan?.hasContent == false)
        var own = SessionActivitySnapshot()
        SessionActivityReducer.ingest(.object(["method": .string("turn/plan/updated"), "params": .object(["plan": .array([.object(["step": .string("Child only"), "status": .string("completed")])])])]), provider: .codex, sessionID: "child", into: &own)
        execution.observeActivity(child, snapshot: own)
        #expect(library.workspaceAgents(parent).first(where: { !$0.isMain })?.plan?.checklist.first?.title == "Child only")
        var merged = DioramaConversation(session: parent, model: "")
        merged.segments.append(ConversationSegment(nativeID: "s", provider: .claude, model: ""))
        conversations.records = [merged]
        let projected = library.workspaceAgents(parent)
        #expect(projected.first?.provider == "Claude Code")
        #expect(projected.first?.plan?.hasContent == false)
        #expect(projected.first(where: { !$0.isMain })?.plan?.checklist.first?.title == "Child only")
        #expect(execution.tasks.isEmpty)
    }
}
