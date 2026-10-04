import AppKit
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct SpatialWorkspaceTests {
    private func session(_ id: String = "root", provider: Provider = .codex, folder: String = "/tmp/layers", archived: Bool = false, classification: SessionClassification = .conversation) -> Session {
        Session(id: provider.rawValue + ":" + id, provider: provider, url: nil, sessionID: id, title: "Build offline support", project: folder,
            modified: Date(timeIntervalSince1970: 100), bytes: 0, archived: archived, parentID: nil, classification: classification)
    }
    private func agent(_ id: String = "main", status: WorkspaceAgentStatus = .working, freshness: WorkspaceAgentFreshness = .live, reason: WorkspaceAttentionReason = .other) -> SpatialAgent {
        SpatialAgent(projectID: "p", conversationID: "Codex:root", value: WorkspaceAgent(id: id, name: id == "main" ? "Implementation" : "Verifier", provider: "Codex",
            task: "Make sample projects work offline", action: "Reading project files", status: status, reportedStatus: status.rawValue, freshness: freshness, attentionReason: reason))
    }
    private func world(_ agents: [SpatialAgent]? = nil) -> SpatialWorld {
        SpatialWorld(projects: [SpatialProject(id: "p", name: "Launchpad", teams: [SpatialTeam(projectID: "p", session: session(), agents: agents ?? [agent(), agent("review")])])])
    }

    @Test func hierarchyUsesExistingProjectMembershipAndDoesNotGroupByTitle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        var project = DioramaProject(name: "Local", folder: "/tmp/layers", commonDirectory: "", base: "", remote: nil)
        project.workspaces = [ProjectWorkspace(id: "work", folder: "/tmp/layers-worktree", branch: "feature", baseCommit: "", context: ProjectContext())]
        projects.projects = [project]
        let library = LibraryModel(execution: ExecutionController(), projects: projects, conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")))
        library.sessions = [session(), session("same-title"), session("worktree", folder: "/tmp/layers-worktree"),
                            session("archived", archived: true), session("child", classification: .subagent),
                            session("review", classification: .internalReview), session("outside", folder: "/tmp/elsewhere")]
        let projection = library.spatialWorld(showArchived: false)
        #expect(projection.projects.count == 1)
        #expect(projection.projects[0].teams.count == 3)
        #expect(projection.standalone.map(\.session.sessionID) == ["outside"])
        #expect(library.spatialWorld(showArchived: true).projects[0].teams.count == 4)
        #expect(library.execution.tasks.isEmpty)
    }

    @Test func mergedConversationKeepsProviderScopedChildrenAndNavigationIsReadOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let project = DioramaProject(name: "Local", folder: "/tmp/layers", commonDirectory: "", base: "", remote: nil)
        projects.projects = [project]
        let conversations = DioramaConversationModel(file: root.appendingPathComponent("conversations.json"))
        let old = session("old")
        let current = session("current", provider: .claude)
        var merged = DioramaConversation(session: old, model: "")
        merged.segments.append(ConversationSegment(nativeID: current.sessionID, provider: .claude, model: ""))
        conversations.records = [merged]
        let execution = ExecutionController()
        for source in [old, current] {
            var snapshot = SessionActivitySnapshot()
            snapshot.apply(SessionActivityRecord(id: source.id + ":child", provider: source.provider.rawValue,
                sessionID: source.sessionID, turnID: nil, nativeID: "same-child-id", parentID: source.sessionID,
                kind: "agent", title: "Review", status: "waiting_for_input", detail: "Review changes", source: "Fixture",
                recordedAt: nil, observedAt: Date(), data: .null))
            execution.observeActivity(source, snapshot: snapshot)
        }
        let library = LibraryModel(execution: execution, projects: projects, conversations: conversations)
        library.sessions = conversations.project([old, current])
        let world = library.spatialWorld(showArchived: false)
        let team = try #require(world.projects.first?.teams.first)
        #expect(world.teams.count == 1)
        #expect(team.agents.count == 3)
        #expect(Set(team.agents.map(\.id)).count == 3)
        #expect(team.summary.attention == 2)
        #expect(team.agents.filter { !$0.value.isMain }.allSatisfy { $0.value.freshness == .lastKnown })
        library.navigate(.project(project.id, team.session.id))
        #expect(library.spatial.focus == team.focus)
        library.navigate(.home)
        #expect(library.spatial.focus == .portfolio)
        #expect(execution.tasks.isEmpty)
    }

    @Test func workScreenPreservesOfficeCameraOnOpenAndClose() {
        let view = SpatialSceneView()
        let snapshot = world()
        view.apply(world: snapshot, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        let custom = SpatialCameraPose(x: 3, y: 1, z: 5, scale: 9, yaw: 0.3, elevation: 0.5)
        view.move(to: custom, animated: false)
        let cameraPosition = view.pointOfView!.position
        let selected = agent()
        view.apply(world: snapshot, focus: .agent(project: "p", conversation: selected.conversationID, agent: selected.id, expanded: true), active: false, reducedMotion: true, reset: 0)
        #expect(view.pose == custom)
        #expect(view.pointOfView!.position.x == cameraPosition.x)
        #expect(view.pointOfView!.position.z == cameraPosition.z)
        view.apply(world: snapshot, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        #expect(view.pose == custom)
        view.tearDown()
    }

    @Test func interruptedCameraTravelStartsFromRenderedPose() {
        let view = SpatialSceneView()
        view.move(to: SpatialCameraPose(x: 50, scale: 6), animated: true, at: 100)
        view.frameStep(at: 100.08)
        let current = view.pose
        #expect(current.x > 0 && current.x < 50)
        let end = SpatialCameraPose(x: -10, scale: 20)
        view.move(to: end, animated: true, at: 100.08)
        #expect(view.pose == current)
        view.frameStep(at: 100.58)
        #expect(view.pose == end)
        view.suspend()
    }

    @Test func summariesDeduplicateAndNeverPromoteStaleActivityToLive() {
        let request = agent(status: .waiting, reason: .input)
        let old = agent("old", status: .working, freshness: .lastKnown)
        let done = agent("done", status: .done)
        let summary = SpatialSummary(agents: [request, request, old, done])
        #expect(summary.attention == 1)
        #expect(summary.working == 0)
        #expect(summary.stale == 1)
        #expect(summary.completed == 1)
        #expect(summary.text.contains("turns finished"))
        #expect(!summary.text.contains("verified"))
        #expect(SpatialSummary(agents: [old]).text.contains("Activity unknown"))
        #expect(SpatialSummary().text == "No active work")
    }

    @Test func scopedIDsCannotCollideAndParentsRemainAvailable() {
        let a = agent()
        let b = SpatialAgent(projectID: "other", conversationID: a.conversationID, value: a.value)
        #expect(a.id != b.id)
        #expect(SpatialAgent.identity(project: "a:b", conversation: "c", provider: "", agent: "") != SpatialAgent.identity(project: "a", conversation: "b:c", provider: "", agent: ""))
        let expanded = SpatialFocus.agent(project: "p", conversation: "Codex:root", agent: a.id, expanded: true)
        #expect(expanded.parent == a.focus)
        #expect(expanded.parent.parent == .team(project: "p", conversation: "Codex:root"))
        #expect(world().resolved(expanded) == expanded)
        #expect(world([]).resolved(expanded) == .team(project: "p", conversation: "Codex:root"))
        #expect(SpatialWorld(projects: [.init(id: "p", name: "P", teams: [])]).resolved(expanded) == .project("p"))
        #expect(SpatialWorld().resolved(expanded) == .portfolio)
    }

    @Test func slotsSurviveReorderingAndCameraCanRetargetFromCurrentPose() {
        var slots = SpatialSlots()
        #expect(slots.index("one") == 0)
        #expect(slots.index("two") == 1)
        #expect(slots.index("two") == 1)
        #expect(slots.index("three") == 2)
        #expect(slots.index("one") == 0)
        let start = SpatialCameraPose(scale: 30)
        let destination = SpatialCameraPose(x: 40, scale: 6)
        let current = start.interpolated(to: destination, fraction: 0.5)
        #expect(current.x == 20)
        #expect(current.interpolated(to: start, fraction: 0) == current)
        #expect(current.interpolated(to: start, fraction: 1) == start)
    }

    @Test func liveSceneRetainsIdentityBoundsDetailsAndSuspends() throws {
        let view = SpatialSceneView()
        view.frame = NSRect(x: 0, y: 0, width: 1100, height: 750)
        let agents = (0..<60).map { agent("worker-\($0)") }
        let first = world(agents)
        let focus = SpatialFocus.team(project: "p", conversation: "Codex:root")
        view.apply(world: first, focus: focus, active: true, reducedMotion: true, reset: 0)
        #expect(view.officeWorkstations.count == 16)
        let retained = try #require(view.officeWorkstations[agents[0].id])
        let position = retained.root.position
        var changed = first
        changed.projects[0].teams[0].agents.reverse()
        view.apply(world: changed, focus: agents[0].focus, active: true, reducedMotion: true, reset: 0)
        let updated = try #require(view.officeWorkstations[agents[0].id])
        #expect(updated.root.position.x == position.x && updated.root.position.z == position.z)
        #expect(view.officeWorkstations.count == 16)
        view.apply(world: first, focus: agents[59].focus, active: true, reducedMotion: true, reset: 0)
        #expect(view.officeWorkstations[agents[59].id] == nil) // Selecting a hidden agent must not create an extra avatar.
        #expect(view.officeWorkstations.count == 16)
        view.suspend()
        #expect(!view.isPlaying && !view.rendersContinuously)
    }

    @Test func layerSnapshots() throws {
        let view = SpatialSceneView()
        let data = world([agent(status: .waiting, reason: .input), agent("review", status: .waiting)])
        let focus: [SpatialFocus] = [.portfolio, .project("p"), .team(project: "p", conversation: "Codex:root"), agent().focus]
        for width in [760, 1320] {
            view.frame = NSRect(x: 0, y: 0, width: width, height: 760)
            for (index, layer) in focus.enumerated() {
                view.apply(world: data, focus: layer, active: false, reducedMotion: true, reset: 0)
                let tiff = try #require(view.snapshot().tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: "/tmp/diorama-layer-\(index)-\(width).png"))
            }
        }
    }
}
