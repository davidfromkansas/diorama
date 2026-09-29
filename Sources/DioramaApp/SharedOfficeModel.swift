import Foundation

/// Desk proximity is a visual arrangement only. Conversation and provider addresses stay intact.
struct OfficeOccupant: Identifiable, Equatable {
    let agent: SpatialAgent
    let assignment: String
    var id: String { agent.id }
    var destination: SpatialFocus {
        .agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true)
    }
}

struct OfficeRoster: Equatable {
    static let finishedRetention: TimeInterval = 30 * 60
    let occupants: [OfficeOccupant]
    let conversationCount: Int

    init(teams: [SpatialTeam], now: Date, including selected: String? = nil, conversation: String? = nil) {
        var seen = Set<String>()
        occupants = teams.flatMap { team in
            team.agents.compactMap { agent in
                guard seen.insert(agent.id).inserted else { return nil }
                if agent.id != selected, agent.conversationID != conversation, [.done, .stopped].contains(agent.value.status) {
                    // An old completion discovered on launch is not a newly completed turn.
                    guard let observed = agent.value.observedAt,
                          now.timeIntervalSince(observed) >= -2,
                          now.timeIntervalSince(observed) < Self.finishedRetention else { return nil }
                }
                return OfficeOccupant(agent: agent, assignment: team.title)
            }
        }
        conversationCount = teams.count
    }
}

/// Stable slots, physical desk locations, and avatar position are intentionally separate.
/// Coordinates are metres; the central cross is circulation space, never a task/feature boundary.
struct OfficeDeskAssignment: Equatable {
    let slot: Int
    let x: Double
    let z: Double
    let yaw: Double
    var cluster: Int { slot / 4 }
}

struct SharedOfficeLayout {
    static let minimumDeskCount = 16
    var deskCount: Int { max(Self.minimumDeskCount, order.count) }
    var desks: [OfficeDeskAssignment] { (0..<deskCount).map(Self.desk) }
    private(set) var assignments: [String: OfficeDeskAssignment] = [:]
    private(set) var order: [String] = []
    private(set) var halfWidth = 3.5
    private(set) var halfDepth = 3.5

    mutating func register(_ identities: [String]) {
        for id in identities where assignments[id] == nil {
            let desk = Self.desk(slot: order.count)
            order.append(id); assignments[id] = desk
            halfWidth = max(halfWidth, abs(desk.x) + 1.3)
            halfDepth = max(halfDepth, abs(desk.z) + 1.5)
        }
    }

    static func desk(slot: Int) -> OfficeDeskAssignment {
        let cluster = slot / 4, quadrant = cluster % 4, shellIndex = cluster / 4
        // Grow each quadrant outwards in square shells, retaining every previous coordinate.
        let shell = Int(Double(shellIndex).squareRoot())
        let offset = shellIndex - shell * shell
        let column = offset <= shell ? shell : 2 * shell - offset
        let row = offset <= shell ? offset : shell
        let signX = quadrant % 2 == 0 ? -1.0 : 1.0
        let signZ = quadrant < 2 ? -1.0 : 1.0
        let local = slot % 4
        let x = signX * (2.3 + Double(column) * 4.7 + Double(local % 2) * 1.9)
        let z = signZ * (2.5 + Double(row) * 5.4 + Double(local / 2) * 2.4)
        return OfficeDeskAssignment(slot: slot, x: x, z: z, yaw: 0)
    }
}
