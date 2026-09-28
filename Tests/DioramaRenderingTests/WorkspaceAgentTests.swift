import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct WorkspaceAgentTests {
    private func record(_ id: String, provider: Provider = .codex, source: String = "root",
                        kind: String = "agent", status: String = "running", parent: String? = "root",
                        detail: String = "Inspect the project") -> SessionActivityRecord {
        SessionActivityRecord(id: provider.rawValue + ":" + source + ":" + kind + ":" + id,
            provider: provider.rawValue, sessionID: source, turnID: "turn", nativeID: id, parentID: parent,
            kind: kind, title: id, status: status, detail: detail, source: "Fixture",
            recordedAt: nil, observedAt: Date(timeIntervalSince1970: 100), data: .null)
    }
    private func source(_ records: [SessionActivityRecord], provider: Provider = .codex,
                        id: String = "root", phase: ExecutionPhase = .working,
                        attached: Bool = true, lastKnown: Bool = false) -> WorkspaceActivitySource {
        var snapshot = SessionActivitySnapshot()
        records.forEach { snapshot.apply($0) }
        snapshot.lastKnown = lastKnown
        var task = ExecutedTask(id: id, title: "Build the feature", folder: "/tmp", turnID: "turn", attached: attached)
        task.provider = provider; task.phase = phase
        task.requiresReconciliation = phase.active
        return WorkspaceActivitySource(provider: provider, sessionID: id, snapshot: snapshot, task: task)
    }

    @Test func draftAndExecutionPhases() {
        #expect(WorkspaceAgentPresentation.agents(title: "", sources: []) == [.ready])
        let phases: [(ExecutionPhase, WorkspaceAgentStatus)] = [
            (.ready, .ready), (.submitting, .working), (.working, .working), (.approval, .waiting),
            (.input, .waiting), (.finished, .done), (.interrupted, .stopped), (.failed, .failed),
            (.disconnected, .unknown)
        ]
        for (phase, status) in phases {
            let agent = WorkspaceAgentPresentation.agents(title: "Task", sources: [source([], phase: phase)])[0]
            #expect(agent.status == status)
            #expect(agent.isWorking == (phase == .working || phase == .submitting))
        }
    }

    @Test func freshnessAndUnknownStatusesNeverInventLiveWork() {
        for provider in [Provider.codex, .claude] {
            let child = record("child", provider: provider)
            for stale in [source([child], provider: provider, attached: false),
                          source([child], provider: provider, phase: .disconnected)] {
                let agents = WorkspaceAgentPresentation.agents(title: "Task", sources: [stale])
                #expect(agents.allSatisfy { !$0.isWorking })
                #expect(agents[1].freshness == .lastKnown)
            }
        }
        let unknown = WorkspaceAgentPresentation.agents(title: "Task", sources: [
            source([record("child", status: "provider_specific_state")])
        ])[1]
        #expect(unknown.status == .unknown && unknown.reportedStatus == "provider_specific_state")
    }

    @Test func resumedMainCanWorkWithoutAnimatingOldSubagentHistory() {
        let saved = source([record("old")], lastKnown: true)
        let savedAgents = WorkspaceAgentPresentation.agents(title: "Task", sources: [saved])
        #expect(savedAgents[0].isWorking)
        #expect(!savedAgents[1].isWorking)
        var task = saved.task!
        task.liveStartedAt = Date(timeIntervalSince1970: 1000)
        var recent = record("new")
        recent.observedAt = Date(timeIntervalSince1970: 2000)
        var snapshot = SessionActivitySnapshot()
        snapshot.apply(record("old")); snapshot.apply(recent)
        let resumed = WorkspaceActivitySource(provider: .codex, sessionID: "root", snapshot: snapshot, task: task)
        let agents = WorkspaceAgentPresentation.agents(title: "Task", sources: [resumed])
        #expect(!agents[1].isWorking)
        #expect(agents[2].isWorking)
    }

    @Test func ownershipProviderSegmentsAndBrokenParentage() {
        let first = source([record("shared", provider: .claude, source: "old")],
                           provider: .claude, id: "old", attached: false)
        let current = source([
            record("shared"), record("grandchild", parent: "shared"),
            record("cycle-a", parent: "cycle-b"), record("cycle-b", parent: "cycle-a"),
            record("orphan", parent: "missing"), record("shell", kind: "job"),
            record("Read", kind: "tool", parent: "shared"),
            record("fileChange", kind: "tool", parent: nil)
        ])
        let agents = WorkspaceAgentPresentation.agents(title: "Task", sources: [first, current])
        #expect(agents.count == 7)
        #expect(Set(agents.map(\.id)).count == agents.count)
        #expect(agents.filter(\.isMain).count == 1)
        #expect(agents[0].provider == Provider.codex.rawValue)
        #expect(agents[0].action == "Editing files")
        #expect(agents[1].freshness == .lastKnown)
        #expect(agents[2].action == "Reading project files")
        #expect(agents[3].parentID == agents[2].id)
        #expect(agents.last?.parentName == "Unresolved parent")
        #expect(!agents.contains { $0.name == "shell" })
    }

    @Test func rosterRetainsCompletedAgentsAndStopsMissingLiveOnes() {
        var roster = WorkspaceAgentRoster()
        let initial = WorkspaceAgentPresentation.agents(title: "Task", sources: [
            source([record("done", status: "completed"), record("working")])
        ])
        roster.update(initial)
        let ids = roster.agents.map(\.id)
        roster.update([initial[0], initial[2], initial[1]])
        #expect(roster.agents.map(\.id) == ids)
        roster.update([.ready])
        #expect(roster.agents.count == 3)
        #expect(roster.agents[1].status == .done)
        #expect(!roster.agents[2].isWorking)
        #expect(roster.agents[2].freshness == .lastKnown)
    }

    @Test func providerEventsCreateUpdateAndFinishOneAgent() throws {
        func wire(_ text: String) throws -> WireValue { try JSONDecoder().decode(WireValue.self, from: Data(text.utf8)) }
        for provider in [Provider.codex, .claude] {
            var snapshot = SessionActivitySnapshot()
            let events: [String] = provider == .claude ? [
                #"{"method":"diorama/claudeActivity","params":{"event":{"type":"system","subtype":"task_started","task_id":"child","task_type":"local_agent","description":"Review","tool_use_id":"call"}}}"#,
                #"{"method":"diorama/claudeActivity","params":{"event":{"type":"system","subtype":"task_notification","task_id":"child","status":"completed","summary":"Finished review"}}}"#
            ] : [
                #"{"method":"item/started","params":{"item":{"type":"subAgentActivity","agentId":"child","agentNickname":"Review","status":"running"}}}"#,
                #"{"method":"item/completed","params":{"item":{"type":"subAgentActivity","agentId":"child","agentNickname":"Review","status":"completed"}}}"#
            ]
            for (index, json) in events.enumerated() {
                let event = try wire(json)
                SessionActivityReducer.ingest(event, provider: provider, sessionID: "root", into: &snapshot)
                SessionActivityReducer.ingest(event, provider: provider, sessionID: "root", into: &snapshot)
                let agents = WorkspaceAgentPresentation.agents(title: "Task", sources: [source(snapshot.records, provider: provider)])
                #expect(agents.count == 2)
                #expect(agents[1].status == (index == 0 ? .working : .done))
                #expect(agents[1].activityRecordID == snapshot.agents[0].id)
            }
        }
    }

    @Test func conversationEventsDriveWorkspaceWithoutStartingWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = WorkspaceAvatarTransport()
        let execution = ExecutionController(transport: transport)
        execution.tasks["root"] = ExecutedTask(id: "root", title: "Conversation", folder: root.path, attached: true)
        let session = try #require(execution.tasks["root"]?.session)
        let model = LibraryModel(execution: execution, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")),
            conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")))
        #expect(model.workspaceAgents(session)[0].status == .ready)
        await execution.receive(.object(["method": .string("turn/started"),
            "params": .object(["threadId": .string("root"), "turn": .object(["id": .string("turn")])])]))
        #expect(execution.tasks["root"]?.requiresReconciliation == true)
        #expect(model.workspaceAgents(session)[0].isWorking)
        await execution.receive(.object(["method": .string("item/started"), "params": .object([
            "threadId": .string("root"), "turnId": .string("turn"), "item": .object([
                "type": .string("subAgentActivity"), "id": .string("agent-event"),
                "agentId": .string("child"), "agentNickname": .string("Research"), "status": .string("running")
            ])])]))
        #expect(model.workspaceAgents(session).count == 2)
        #expect(model.workspaceAgents(session)[1].isWorking)
        await execution.receive(.object(["method": .string("turn/completed"), "params": .object([
            "threadId": .string("root"), "turn": .object(["id": .string("turn"), "status": .string("completed")])])]))
        #expect(model.workspaceAgents(session)[0].status == .done)
        #expect(await transport.methods.isEmpty)
    }

    @Test func selectionDetailsRenderAndUpdatesKeepTheNativeScene() async throws {
        _ = NSApplication.shared
        let agents = WorkspaceAgentPresentation.agents(title: "Build avatars", sources: [
            source([record("Research"), record("Tests", status: "completed")])
        ])
        let host = NSHostingView(rootView: WorkspaceSceneView(agents: agents).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 650)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.orderOut(nil) }
        func scene(_ view: NSView) -> WorkspaceSceneNSView? {
            if let scene = view as? WorkspaceSceneNSView { return scene }
            return view.subviews.compactMap(scene).first
        }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let native = try #require(scene(host))
        #expect(native.workstations.count == agents.count)
        native.selectAgent?(agents[1].id)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        #expect(scene(host) === native)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/diorama-avatar-details.png"))
        var updated = agents
        updated[1].status = .done
        host.rootView = WorkspaceSceneView(agents: updated).environment(\.colorScheme, .dark)
        try await Task.sleep(for: .milliseconds(100))
        #expect(scene(host) === native)
        #expect(native.workstations[agents[1].id]!.avatar.workingAnchors.allSatisfy { $0.action(forKey: "typing") == nil })
    }

    @Test func nodesStayStableAndMotionStopsForFinishedHiddenAndReducedMotion() throws {
        let view = WorkspaceSceneNSView()
        let working = WorkspaceAgentPresentation.agents(title: "Task", sources: [source([record("child")])])
        view.apply(agents: working, selectedID: nil, reduceMotion: false, active: true)
        let child = try #require(view.workstations[working[1].id])
        let root = child.root
        #expect(child.animating && view.isPlaying)
        let done = WorkspaceAgentPresentation.agents(title: "Task", sources: [source([record("child", status: "completed")])])
        view.apply(agents: done, selectedID: working[1].id, reduceMotion: false, active: true)
        #expect(view.workstations[working[1].id]?.root === root)
        #expect(child.motion.gesture == .celebration)
        #expect(child.avatar.workingAnchors.allSatisfy { $0.action(forKey: "typing") == nil })
        view.apply(agents: working, selectedID: nil, reduceMotion: true, active: true)
        #expect(!view.isPlaying && !view.rendersContinuously)
        view.apply(agents: working, selectedID: nil, reduceMotion: false, active: false)
        #expect(!view.isPlaying)
        view.apply(agents: working, selectedID: nil, reduceMotion: false, active: true)
        view.stopRendering()
        #expect(!view.isPlaying && !child.animating)
    }

    @Test func growingTeamPreservesDesksAndCameraUntilResetAndCanHitTest() throws {
        let view = WorkspaceSceneNSView()
        view.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
        let initial = WorkspaceAgentPresentation.agents(title: "Task", sources: [source([record("child")])])
        view.apply(agents: initial, selectedID: nil, reduceMotion: true, active: true)
        let root = try #require(view.workstations[initial[1].id]?.root)
        let position = root.simdPosition
        let camera = try #require(view.pointOfView)
        let before = camera.simdTransform
        let many = WorkspaceAgentPresentation.agents(title: "Task", sources: [
            source([record("child")] + (0..<15).map { record("worker-\($0)") })
        ])
        view.apply(agents: many, selectedID: nil, reduceMotion: true, active: true)
        #expect(root.simdPosition == position)
        #expect(camera.simdTransform == before)
        let ground = try #require(view.scene?.rootNode.childNode(withName: "ground", recursively: false)?.geometry as? SCNBox)
        #expect(ground.length > 20)
        view.resetCamera()
        #expect(view.distance > 38)
        _ = view.snapshot()
        let projected = view.projectPoint(SCNVector3(0, 2.1, 3.1))
        #expect(view.agentID(at: NSPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))) == "main")
        let other = WorkspaceSceneNSView()
        other.apply(agents: [.ready], selectedID: nil, reduceMotion: true, active: true)
        #expect(other.workstations.count == 1)
    }

    @Test func renderAvatarFixtures() throws {
        for (name, count, width) in [("draft", 0, 760), ("team", 5, 1100), ("narrow", 3, 380), ("expanded", 16, 1100)] {
            let view = WorkspaceSceneNSView()
            view.frame = NSRect(x: 0, y: 0, width: width, height: 760)
            let agents: [WorkspaceAgent] = count == 0 ? [.ready] : WorkspaceAgentPresentation.agents(title: "Build the scene", sources: [
                source((0..<count).map { record(["Research", "Implementation", "Tests"][$0 % 3] + "-\($0)",
                    status: ["running", "completed", "failed", "pending"][$0 % 4]) })
            ])
            view.apply(agents: agents, selectedID: nil, reduceMotion: true, active: true)
            view.resetCamera()
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/diorama-avatars-\(name).png"))
        }
    }
}


private actor WorkspaceAvatarTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    var methods: [String] = []
    func connect() {}
    func request(_ method: String, _ params: WireValue) -> WireValue {
        methods.append(method)
        return .object(["data": .array([])])
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}
