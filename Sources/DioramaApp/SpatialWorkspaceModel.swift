import Foundation
import Observation
import DioramaCore

/// UI-only addresses. Provider sessions and project membership remain authoritative.
enum SpatialFocus: Codable, Equatable, Hashable {
    case portfolio
    case project(String)
    case team(project: String?, conversation: String)
    case agent(project: String?, conversation: String, agent: String, expanded: Bool)

    var projectID: String? {
        switch self {
        case .portfolio: nil
        case .project(let id): id
        case .team(let id, _), .agent(let id, _, _, _): id
        }
    }
    var conversationID: String? {
        switch self {
        case .team(_, let id), .agent(_, let id, _, _): id
        default: nil
        }
    }
    var agentID: String? { if case .agent(_, _, let id, _) = self { id } else { nil } }
    var expanded: Bool { if case .agent(_, _, _, let value) = self { value } else { false } }
    var parent: SpatialFocus {
        switch self {
        case .portfolio, .project: .portfolio
        case .team(let project, _): project.map(Self.project) ?? .portfolio
        case .agent(let project, let conversation, let agent, true): .agent(project: project, conversation: conversation, agent: agent, expanded: false)
        case .agent(let project, let conversation, _, false): .team(project: project, conversation: conversation)
        }
    }
    /// A work screen opened from the shared project office returns directly to that office.
    var officeReturn: SpatialFocus {
        if expanded, let projectID { return .project(projectID) }
        return parent
    }
    var layer: String {
        switch self { case .portfolio: "Portfolio · Layer 3"; case .project: "Project · Layer 2"; case .team: "Team · Layer 1"; case .agent: "Agent · Layer 0" }
    }
}

struct SpatialAgent: Identifiable, Equatable {
    let projectID: String?
    let conversationID: String
    var value: WorkspaceAgent
    var id: String { Self.identity(project: projectID, conversation: conversationID, provider: value.provider, agent: value.id) }
    static func identity(project: String?, conversation: String, provider: String, agent: String) -> String {
        // Length prefixes keep arbitrary provider identifiers unambiguous.
        [project ?? "", conversation, provider, agent].map { "\($0.utf8.count):\($0)" }.joined()
    }
    var focus: SpatialFocus { .agent(project: projectID, conversation: conversationID, agent: id, expanded: false) }
    var fresh: Bool { value.freshness == .live || value.freshness == .recentlyObserved }
    var needsAttention: Bool { value.status == .waiting && value.attentionReason != .other }
}

struct SpatialSummary: Equatable {
    var working = 0
    var attention = 0
    var failed = 0
    var stale = 0
    var completed = 0
    init(agents: [SpatialAgent] = []) {
        var seen = Set<String>()
        for agent in agents where seen.insert(agent.id).inserted {
            if !agent.fresh { stale += 1 }
            if agent.value.isWorking { working += 1 }
            if agent.needsAttention { attention += 1 }
            if agent.value.status == .failed { failed += 1 }
            if agent.value.status == .done { completed += 1 }
        }
    }
    var text: String {
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if attention > 0 { parts.append("\(attention) need input") }
        if failed > 0 { parts.append("\(failed) reported failures") }
        if completed > 0 { parts.append("\(completed) turns finished") }
        if parts.isEmpty { parts.append(stale > 0 ? "Activity unknown" : "No active work") }
        if stale > 0 { parts.append("\(stale) last known / unavailable") }
        return parts.joined(separator: " · ")
    }
}

struct SpatialTeam: Identifiable, Equatable {
    let projectID: String?
    let session: Session
    var agents: [SpatialAgent]
    var id: String { SpatialAgent.identity(project: projectID, conversation: session.id, provider: "", agent: "") }
    var title: String { session.displayTitle }
    var focus: SpatialFocus { .team(project: projectID, conversation: session.id) }
    var summary: SpatialSummary { .init(agents: agents) }
}
struct SpatialProject: Identifiable, Equatable {
    let id: String
    let name: String
    var teams: [SpatialTeam]
    var summary: SpatialSummary { .init(agents: teams.flatMap(\.agents)) }
}
struct SpatialWorld: Equatable {
    var projects: [SpatialProject] = []
    var standalone: [SpatialTeam] = []
    var teams: [SpatialTeam] { projects.flatMap(\.teams) + standalone }
    func team(_ focus: SpatialFocus) -> SpatialTeam? {
        teams.first { $0.projectID == focus.projectID && $0.session.id == focus.conversationID }
    }
    func agent(_ focus: SpatialFocus) -> SpatialAgent? { team(focus)?.agents.first { $0.id == focus.agentID } }
    func resolved(_ focus: SpatialFocus) -> SpatialFocus {
        if let project = focus.projectID, !projects.contains(where: { $0.id == project }) { return .portfolio }
        if focus.conversationID != nil, team(focus) == nil { return focus.projectID.map(SpatialFocus.project) ?? .portfolio }
        if focus.agentID != nil, agent(focus) == nil, let team = team(focus) { return team.focus }
        return focus
    }
}

@Observable final class SpatialWorkspaceState {
    var sceneKind: WorkspaceSceneKind = .office
    var focus: SpatialFocus = .portfolio {
        didSet { if focus.expanded { conversationPanelVisible = true } }
    }
    var inboxExpanded = false
    var serversExpanded = false
    var inboxSelection: InboxThread?
    var conversationWidth: Double?
    var conversationPanelVisible = false
    var showArchived = false
    var notice: String?
    var resetGeneration = 0
    var page = 0
    @ObservationIgnored private var rosters: [String: LiveAgentRosterModel] = [:]
    func roster(for key: String) -> LiveAgentRosterModel {
        if let existing = rosters[key] { return existing }
        let model = LiveAgentRosterModel(); rosters[key] = model; return model
    }
}

/// Slots survive status changes, sorting changes, and temporary disappearance.
struct SpatialSlots {
    private(set) var ids: [String] = []
    mutating func index(_ id: String) -> Int {
        if let index = ids.firstIndex(of: id) { return index }
        ids.append(id)
        return ids.count - 1
    }
}

extension LibraryModel {
    private func spatialTeam(_ session: Session, project: String?) -> SpatialTeam {
    var agents = workspaceAgents(session)
    // Summary-only sources can report attention before structured activity arrives.
    let reported = portfolio.observation(for: session.provider, nativeID: session.sessionID)?.activity.state ?? summary(session).state
    if (reported == .approval || reported == .input), let index = agents.firstIndex(where: \.isMain), agents[index].attentionReason == .other {
        agents[index].status = .waiting
        agents[index].attentionReason = reported == .approval ? .approval : .input
    }
    return SpatialTeam(projectID: project, session: session, agents: agents.map {
        SpatialAgent(projectID: project, conversationID: session.id, value: $0)
    })
    }

    /// Home needs the same reported counts, but must not project the entire library in one frame.
    func homeProjectSummaries() async -> [SpatialProject]? {
        let records = projects.projects
        var result: [SpatialProject] = []
        var assigned = Set<String>()
        for project in records {
            var teams: [SpatialTeam] = []
            let sessions = projects.sessions(project, library: self).filter {
                !$0.archived && $0.classification != .subagent && $0.classification != .internalReview
            }.sorted { $0.id < $1.id }
            for session in sessions where assigned.insert(session.id).inserted {
                guard !Task.isCancelled else { return nil }
                teams.append(spatialTeam(session, project: project.id))
                await Task.yield()
            }
            result.append(SpatialProject(id: project.id, name: project.name, teams: teams))
            await Task.yield()
        }
        return Task.isCancelled ? nil : result
    }

    func spatialWorld(showArchived: Bool, projectScope: String? = nil, includeStandalone: Bool = true) -> SpatialWorld {
        let interval = ScenePerformance.begin("Spatial projection")
        defer { ScenePerformance.end("Spatial projection", interval) }
        let known = Set(sessions.map(\.id))
        for id in workspaceProjectionCache.entries.keys where !known.contains(id) { workspaceProjectionCache.entries.removeValue(forKey: id) }
        var assigned = Set<String>()
        var world = SpatialWorld()
        func teams(_ sessions: [Session], project: String?) -> [SpatialTeam] {
            sessions.filter { (showArchived || !$0.archived) && $0.classification != .subagent && $0.classification != .internalReview }
                .sorted { $0.id < $1.id }.compactMap { session in
                    guard assigned.insert(session.id).inserted else { return nil }
                    return spatialTeam(session, project: project)
                }
        }
        for project in projects.projects {
            world.projects.append(SpatialProject(id: project.id, name: project.name,
                teams: projectScope == nil || projectScope == project.id ? teams(projects.sessions(project, library: self), project: project.id) : []))
        }
        if projectScope == nil && includeStandalone { world.standalone = teams(sessions, project: nil) }
        // An explicitly opened orphan subagent remains readable, without inventing a parent.
        if let selected, selected.classification == .subagent, !world.teams.contains(where: { $0.session.id == selected.id }) {
            world.standalone.append(SpatialTeam(projectID: nil, session: selected, agents: workspaceAgents(selected).map {
                SpatialAgent(projectID: nil, conversationID: selected.id, value: $0)
            }))
        }
        return world
    }
}
