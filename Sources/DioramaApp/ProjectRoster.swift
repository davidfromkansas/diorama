import Foundation

/// One agent in a project's roster. Conversation and provider addresses stay intact.
struct RosterOccupant: Identifiable, Equatable {
    let agent: SpatialAgent
    let assignment: String
    var id: String { agent.id }
    var destination: SpatialFocus {
        .agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true)
    }
}

struct ProjectRoster: Equatable {
    let occupants: [RosterOccupant]
    let conversationCount: Int

    init(teams: [SpatialTeam], now: Date, including selected: String? = nil, conversation: String? = nil) {
        var seen = Set<String>()
        occupants = teams.flatMap { team in
            team.agents.compactMap { agent in
                guard seen.insert(agent.id).inserted else { return nil }
                return RosterOccupant(agent: agent, assignment: team.title)
            }
        }
        conversationCount = teams.count
    }
}
