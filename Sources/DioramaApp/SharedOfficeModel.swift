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
    let occupants: [OfficeOccupant]
    let conversationCount: Int

    init(teams: [SpatialTeam], now: Date, including selected: String? = nil, conversation: String? = nil) {
        var seen = Set<String>()
        occupants = teams.flatMap { team in
            team.agents.compactMap { agent in
                guard seen.insert(agent.id).inserted else { return nil }
                return OfficeOccupant(agent: agent, assignment: team.title)
            }
        }
        conversationCount = teams.count
    }
}

/// Stable slots, physical desk locations, and avatar position are intentionally separate.
/// Two compact desk rows occupy the work area; +Z is lower-right in the default camera.
struct OfficeDeskAssignment: Equatable {
    let slot: Int
    let x: Double
    let z: Double
    let yaw: Double
    var cluster: Int { slot / 4 }
}

/// Selects avatars only; the complete sidebar roster and execution remain untouched.
struct OfficeVisibilityResolver {
    private var recency: AgentRosterReducer
    init(times: [String: Date] = [:], checkpoints: [String: AgentRosterRecency] = [:]) { recency = AgentRosterReducer(initialTimes: times, restored: checkpoints) }
    var times: [String: Date] { recency.activityTimes }
    var checkpoints: [String: AgentRosterRecency] { recency.checkpoints }

    mutating func observe(_ occupants: [OfficeOccupant], now: Date) -> [OfficeOccupant] {
        let agents = occupants.map { occupant -> SpatialAgent in
            let agent = occupant.agent
            // Observation failures and stale replays must not displace placed avatars.
            if !agent.fresh || agent.value.status == .unknown, let previous = recency.rows[agent.id] { return previous.agent }
            return agent
        }
        recency.ingest(agents, received: now)
        return occupants.map { .init(agent: recency.rows[$0.id]?.agent ?? $0.agent, assignment: $0.assignment) }
    }

    func resolve(idle: Set<String>) -> (desk: [String], leisure: [String]) {
        func priority(_ row: AgentRosterRow) -> Int {
            if row.agent.needsAttention || row.agent.value.status == .failed { return 0 }
            return row.agent.value.isWorking ? 1 : 2
        }
        let rows = recency.rows.values.sorted {
            if $0.updated != $1.updated { return $0.updated > $1.updated }
            return $0.id < $1.id
        }
        let desks = rows.filter { !idle.contains($0.id) }.sorted {
            if priority($0) != priority($1) { return priority($0) < priority($1) }
            if $0.updated != $1.updated { return $0.updated > $1.updated }
            return $0.id < $1.id
        }
        return (Array(desks.prefix(16).map(\.id)), Array(rows.filter { idle.contains($0.id) }.prefix(18).map(\.id)))
    }
}

struct SharedOfficeLayout {
    static let minimumDeskCount = 16
    static let leisureCapacity = 18
    var deskCount: Int { Self.minimumDeskCount }
    var desks: [OfficeDeskAssignment] { (0..<deskCount).map(Self.desk) }
    private(set) var standingSlots: [String: Int] = [:]
    private(set) var standing: Set<String> = []
    private(set) var centralRadius = 0.0
    private(set) var leisureSlots: [String: Int] = [:]
    private var knownPlacements: Set<String> = []
    private var previousDesks: [String: Int] = [:]
    private var visibility = OfficeVisibilityResolver()
    var visibleIDs: Set<String> { Set(assignments.keys).union(leisureSlots.keys) }

    struct Saved: Codable, Equatable {
        var order: [String]
        var standingSlots: [String: Int]
        var standing: Set<String>
        var knownPlacements: Set<String>
        var leisureSlots: [String: Int]? = nil
        var centralRadius: Double
        var deskSlots: [String: Int]? = nil
        var previousDesks: [String: Int]? = nil
        var activityTimes: [String: Date]? = nil
        var recency: [String: AgentRosterRecency]? = nil
    }
    var saved: Saved {
        .init(order: order, standingSlots: standingSlots, standing: standing, knownPlacements: knownPlacements,
              leisureSlots: leisureSlots, centralRadius: centralRadius, deskSlots: assignments.mapValues(\.slot),
              previousDesks: previousDesks, activityTimes: visibility.times, recency: visibility.checkpoints)
    }
    init(saved: Saved? = nil) {
        guard let saved else { return }
        standing = saved.standing; knownPlacements = saved.knownPlacements
        visibility = OfficeVisibilityResolver(times: saved.activityTimes ?? [:], checkpoints: saved.recency ?? [:])
        previousDesks = (saved.previousDesks ?? [:]).filter { (0..<16).contains($0.value) }
        let oldDesks = saved.deskSlots ?? Dictionary(saved.order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var used = Set<Int>()
        for id in oldDesks.keys.sorted() {
            guard let slot = oldDesks[id], (0..<16).contains(slot) else { continue }
            previousDesks[id] = slot
            if !standing.contains(id), used.insert(slot).inserted { assignments[id] = Self.desk(slot: slot) }
        }
        used = []
        for id in (saved.leisureSlots ?? [:]).keys.sorted() {
            guard standing.contains(id), let slot = saved.leisureSlots?[id], (0..<18).contains(slot), used.insert(slot).inserted else { continue }
            leisureSlots[id] = slot
        }
        standingSlots = leisureSlots
        order = assignments.keys.sorted { assignments[$0]!.slot < assignments[$1]!.slot }
    }
    private(set) var assignments: [String: OfficeDeskAssignment] = [:]
    private(set) var order: [String] = []
    var halfWidth: Double { 10 }
    var halfDepth: Double { 23.1 }

    mutating func register(_ identities: [String]) {
        var used = Set(assignments.values.map(\.slot))
        for id in identities.sorted() where assignments[id] == nil {
            guard let slot = (0..<16).first(where: { !used.contains($0) }) else { break }
            assignments[id] = Self.desk(slot: slot); previousDesks[id] = slot; used.insert(slot)
        }
        order = assignments.keys.sorted { assignments[$0]!.slot < assignments[$1]!.slot }
    }

    mutating func place(_ occupants: [OfficeOccupant], now: Date = Date()) {
        let present = Set(occupants.map(\.id))
        standing.formIntersection(present); knownPlacements.formIntersection(present)
        previousDesks = previousDesks.filter { present.contains($0.key) }
        let observed = visibility.observe(occupants, now: now)
        for occupant in observed {
            let value = occupant.agent.value
            let known = knownPlacements.contains(occupant.id)
            if value.status == .unknown || value.freshness == .unavailable || value.freshness == .unverified { continue }
            if value.freshness == .lastKnown && known { continue }
            knownPlacements.insert(occupant.id)
            if value.status == .done || value.status == .stopped { standing.insert(occupant.id) }
            else { standing.remove(occupant.id) }
        }
        let visible = visibility.resolve(idle: standing)
        let deskIDs = Set(visible.desk), leisureIDs = Set(visible.leisure)
        assignments = assignments.filter { deskIDs.contains($0.key) }
        var used = Set(assignments.values.map(\.slot))
        for id in visible.desk where assignments[id] == nil {
            let previous = previousDesks[id].flatMap { used.contains($0) ? nil : $0 }
            guard let slot = previous ?? (0..<16).first(where: { !used.contains($0) }) else { continue }
            assignments[id] = Self.desk(slot: slot); previousDesks[id] = slot; used.insert(slot)
        }
        leisureSlots = leisureSlots.filter { leisureIDs.contains($0.key) }
        used = Set(leisureSlots.values)
        for id in visible.leisure where leisureSlots[id] == nil {
            guard let slot = (0..<18).first(where: { !used.contains($0) }) else { continue }
            leisureSlots[id] = slot; used.insert(slot)
        }
        standingSlots = leisureSlots
        order = assignments.keys.sorted { assignments[$0]!.slot < assignments[$1]!.slot }
    }

    mutating func reserveLeisure(_ slot: Int, for id: String) {
        guard (0..<18).contains(slot), leisureSlots[id] != nil,
              !leisureSlots.contains(where: { $0.key != id && $0.value == slot }) else { return }
        leisureSlots[id] = slot; standingSlots[id] = slot
    }

    var floorMinX: Double { -10 }
    var floorMaxX: Double { 10 }
    var floorMinZ: Double { -5.4 }
    var floorMaxZ: Double { 23.1 }

    func standingPosition(_ id: String) -> OfficeDeskAssignment? {
        guard let slot = leisureSlots[id] else { return nil }
        // Transitional initial pose only; furniture anchors set the actual destination.
        return .init(slot: slot, x: -3, z: 8, yaw: 0)
    }

    static func desk(slot: Int) -> OfficeDeskAssignment {
        if let baked = OfficeBakedLayout.transforms["desk:\(slot)"] {
            return .init(slot: slot, x: baked.x, z: baked.z, yaw: baked.rotationRadians)
        }
        // The fixed office renders only the first two rows.
        let row = slot / 8
        let x = (Double(slot % 8) - 3.5) * 1.9
        let z = row == 1 ? 1.4 : -1.4 - Double(max(0, row - 1)) * 2.8
        return OfficeDeskAssignment(slot: slot, x: x, z: z, yaw: 0)
    }
}
