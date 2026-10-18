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

    /// Switching a conversation's model to another provider starts a new native session. When its
    /// file changes it must update the conversation's one chef, not add a second.
    @Test func aSwitchedConversationStaysOneChefAsItsSessionsChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = DioramaConversationModel(file: root.appendingPathComponent("conversations.json"))
        let old = session("old")
        let current = session("current", provider: .claude)
        var merged = DioramaConversation(session: old, model: "")
        merged.segments.append(ConversationSegment(nativeID: current.sessionID, provider: .claude, model: ""))
        conversations.records = [merged]
        let library = LibraryModel(execution: ExecutionController(), projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), conversations: conversations)
        library.sessions = conversations.project([old, current])
        library.mergeChanged([current])
        library.mergeChanged([old])
        #expect(library.sessions.count == 1)
        #expect(library.sessions.first?.id == merged.id && library.sessions.first?.sessionID == current.sessionID)
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



}
