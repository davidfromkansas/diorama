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
    @Test func completedPlanButtonSurvivesReconciliationAndDoesNotNavigate() throws {
        let session = Session(id: "s", provider: .codex, url: nil, sessionID: "s", title: "Inspect agent plans", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let agents = (0..<64).map { SpatialAgent(projectID: "p", conversationID: "s", value: agent("a\($0)")) }
        var world = SpatialWorld(projects: [.init(id: "p", name: "Plans", teams: [.init(projectID: "p", session: session, agents: agents)])])
        let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
        defer { view.tearDown() }
        view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        #expect(view.officeWorkstations.count == 64)
        let first = try #require(agents.first)
        let station = try #require(view.officeWorkstations[first.id])
        let button = try #require(station.root.childNode(withName: "proposal:" + first.id, recursively: true))
        #expect(!button.isHidden)
        let tasks = try #require(station.root.childNode(withName: "tasks:" + first.id, recursively: true))
        #expect(!tasks.isHidden)
        #expect(tasks.parent === button.parent)
        #expect(tasks.position.x > button.position.x)
        let pose = view.pose
        var selected: AgentInspectionDestination?
        view.openInspection = { selected = $0 }
        #expect(view.activatePlan(named: button.name!))
        #expect(selected == AgentInspectionDestination(agentID: first.id, kind: .proposal)); #expect(view.pose == pose)
        #expect(view.activatePlan(named: tasks.name!))
        #expect(selected == AgentInspectionDestination(agentID: first.id, kind: .tasks))
        #expect(view.pose == pose)
        for status in [WorkspaceAgentStatus.failed, .stopped, .done] {
            var value = first.value; value.status = status
            world.projects[0].teams[0].agents[0] = SpatialAgent(projectID: "p", conversationID: "s", value: value)
            view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
            #expect(!button.isHidden); #expect(!tasks.isHidden); #expect(view.officeWorkstations[first.id] === station)
        }
        var empty = first.value; empty.plan = nil
        world.projects[0].teams[0].agents[0] = SpatialAgent(projectID: "p", conversationID: "s", value: empty)
        view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        #expect(button.isHidden); #expect(tasks.isHidden)
    }
    @Test func modalLayoutsAndScenePreview() throws {
        let directory = URL(fileURLWithPath: "/tmp/diorama-plan-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for kind in AgentInspectionKind.allCases {
        for width in [320, 440] {
            let host = NSHostingView(rootView: AgentPlanModal(agent: agent(), kind: kind, paused: false, close: {}).frame(width: CGFloat(width), height: 530))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 530)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("modal-\(kind.rawValue)-\(width).png"))
            window.contentView = nil
        }
        }
        let session = Session(id: "s", provider: .codex, url: nil, sessionID: "s", title: "Completed plan", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let spatial = SpatialAgent(projectID: "p", conversationID: "s", value: agent())
        let world = SpatialWorld(projects: [.init(id: "p", name: "Plans", teams: [.init(projectID: "p", session: session, agents: [spatial])])])
        let scene = SpatialSceneView(); scene.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
        defer { scene.tearDown() }
        scene.apply(world: world, focus: spatial.focus, active: false, reducedMotion: true, reset: 0)
        let tiff = try #require(scene.snapshot().tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("scene.png"))
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
