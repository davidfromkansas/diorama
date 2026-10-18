import AppKit
import DioramaCore
import SceneKit
import simd

/// Which scene a project's agents work in. Saved per project (`ProjectPresentationSnapshot.scene`);
/// an unknown saved value reads as the kitchen rather than failing the whole saved state.
enum SceneKind: String, CaseIterable, Codable, Sendable {
    case kitchen, office
    init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .kitchen
    }
    var title: String {
        switch self {
        case .kitchen: "Kitchen"
        case .office: "Office"
        }
    }
}

/// The chef's proportions and pacing, shared by every scene: the clips are authored against them
/// (hands meet a worktop at `worktopHeight`; seats match the lounge chair).
nonisolated enum ChefMetrics {
    /// World units per chef unit. The chef is a mascot (hands at 31% of its height), so worktops
    /// follow the chef: hands meet the counter in every station clip.
    static let chefScale: Float = 1.4
    /// The chef manifest's `stations.counter_top`, in chef units (asserted against the manifest in tests).
    static let chefCounterTop: Float = 0.585
    static let chefCounterFront: Float = 0.43
    static let chefHeight: Float = 1.9
    static let floorTop: CGFloat = 0.112
    /// Stations model a worktop at local y 1.0 under a 1.25 vertical scale; this rescales it to the chef.
    static var worktopHeight: Float { chefScale * chefCounterTop }
    static var heightScale: Float { (worktopHeight - Float(floorTop)) / 1.25 }
    /// How long a chef stays at a station before a non-urgent change of work moves it (seconds).
    /// Agents make many tool calls a minute; this keeps the scene calm.
    static let minimumDwell: Double = 2
    /// How long a newly arrived chef reads its order at the rail.
    static let orderReading: Double = 3
    /// The arrival wave (`arrive_wave`: two jumps waving both hands, 2.4 s) and a beat after it,
    /// before it heads for the rail.
    static let arrivalWave: Double = 2.6
}

/// Which side of a station the chefs work from; fixtures face the room accordingly.
enum StationWall { case back, left, right, front, island, freestanding }
typealias KitchenWall = StationWall

/// A station on a scene's floor. Its `id` is the station's role, the same in every scene
/// (`StationRole`): the agent → station table, tags, emotes and the log all speak in roles.
struct SceneArea: Identifiable {
    let id: String
    let label: String
    let short: String
    let footprint: CGRect // X/Z coordinates on the floor.
    let wall: StationWall
    /// Agreed number of chefs working here at once; more queue behind.
    let spots: Int
    let accent: NSColor
    var center: SCNVector3 { SCNVector3(footprint.midX, 0.6, footprint.midY) }
}
typealias KitchenArea = SceneArea

/// The stations every scene has, by the id its `SceneArea` carries.
enum StationRole: String, CaseIterable {
    case arrive = "elevator", intake = "order", plan = "prep", edit = "cooking", run = "stove",
         test = "tasting", needsYou = "bell", review = "serving", rest = "break", supplies = "pantry"
}

/// Where an agent's chef works, in the kitchen's terms (station role, clip, hand prop); a scene's
/// `SceneDressing` turns it into that scene's clips and props.
struct ChefWork: Equatable {
    var area: String?
    var loop: String
    var hand: ChefProp? = nil
    var oneShot: String? = nil
    /// Moves immediately, without waiting out the minimum dwell.
    var urgent = false
    var deliversPlate = false
    /// A gesture where the chef stands before it sets off (celebrating work you accepted).
    var prelude: String? = nil
}

/// Agent state → station, the same in every scene: prep before the first edit, then the island
/// (editing) and stove (commands); tests at tasting; anything needing you at the bell; finished
/// work at the serving window; stale or stopped sessions rest in the break room.
enum SceneRouting {
    static func route(_ agent: WorkspaceAgent, review: KitchenReviews.State? = nil) -> ChefWork {
        let fresh = agent.freshness == .live || agent.freshness == .recentlyObserved
        // Finished work waits at the serving window until you decide, even after a restart.
        if let review, agent.isMain, ![.working, .waiting, .failed].contains(agent.status) {
            switch review {
            // Committed, merged, or marked done: the dish is accepted, so the chef celebrates and
            // heads to the break room.
            case .approved, .committed, .merged:
                var rest = rest(agent, urgent: true); rest.prelude = "celebrate_done"; return rest
            // CI tastes the pull request; a conflict or failed check rings the bell; a green PR
            // waits at the pass for you to merge.
            case .checking: return .init(area: "tasting", loop: "testing_dish", hand: .spoon, urgent: true)
            // A facepalm, then scratching its head at the bell until you send it back to fix.
            case .needsFix: return .init(area: "bell", loop: "fix_wait", oneShot: "fix_react", urgent: true)
            // A fist pump, then hands on hips at the pass, waiting for you to merge.
            case .shipped: return .init(area: "serving", loop: "merge_ready_wait", oneShot: "merge_ready", urgent: true)
            case .reworking: return .init(area: "prep", loop: "planning_recipe", hand: .card, urgent: true)
            case .awaiting: return .init(area: "serving", loop: "wait_review", oneShot: "present_review", urgent: true, deliversPlate: true)
            }
        }
        switch agent.status {
        case .ready: return .init(area: "order", loop: "idle_available")
        case .waiting where agent.attentionReason == .other: return .init(area: "bell", loop: "blocked_wait", oneShot: "blocked_react", urgent: true)
        case .waiting: return .init(area: "bell", loop: "wait_input", oneShot: "request_input", urgent: true)
        case .failed: return .init(area: "bell", loop: "blocked_wait", oneShot: "error_react", urgent: true)
        case .stopped: return rest(agent, urgent: true)
        case .unknown: return .init(area: nil, loop: "unknown_wait", urgent: true)
        case .done where fresh: return .init(area: "serving", loop: "wait_review", oneShot: "present_review", urgent: true, deliversPlate: true)
        case .working where fresh:
            switch (KitchenActivity.classify(tool: agent.latestTool, detail: agent.latestToolDetail), agent.turnHasEdits) {
            case (.testing, _), (.checking, _): return .init(area: "tasting", loop: "testing_dish", hand: .spoon)
            // Skills and MCP tools come from the pantry, at any point in the turn.
            case (.resources, _): return .init(area: "pantry", loop: "idle_available", oneShot: "pickup")
            case (.planning, false): return .init(area: "prep", loop: "planning_recipe", hand: .card)
            // Installs, builds and scripts cook at the stove, before the first edit too.
            case (.commands, _): return .init(area: "stove", loop: "waiting_tool")
            case (_, false): return .init(area: "prep", loop: "researching_book", hand: .book)
            case (.commands, true): return .init(area: "stove", loop: "waiting_tool")
            case (_, true): return .init(area: "cooking", loop: "working_chop", hand: .knife)
            }
        default: return rest(agent, urgent: true)
        }
    }
    /// Resting chefs sit down in a lounge chair and idle, sip coffee or chat (stable per agent).
    static func rest(_ agent: WorkspaceAgent, urgent: Bool) -> ChefWork {
        let loops = ["sit_idle", "sit_sip", "sit_chat"]
        let pick = loops[Int(agent.id.utf8.reduce(UInt32(7)) { $0 &* 31 &+ UInt32($1) } % UInt32(loops.count))]
        return .init(area: "break", loop: pick, hand: pick == "sit_sip" ? .mug : nil, oneShot: "sit_down", urgent: urgent)
    }
}

/// How a scene dresses the shared routing: the clip and prop a chef uses at each station, what it
/// reads on arrival, and whether it strikes the needs-you fixture or simply rings it on arrival.
struct SceneDressing {
    var dress: (ChefWork) -> ChefWork = { $0 }
    /// What a newcomer holds while reading its order.
    var arrivalHand: ChefProp? = .ticket
    /// A chef that needs you walks over and strikes the gong (`ChefIntent.strike`); otherwise the
    /// fixture rings as it arrives (the office's desk bell).
    var strikesNeedsYou = true
    /// What a chef queued at a full serving window carries while it waits.
    var servingHand: ChefProp? = .plate
    static let kitchen = SceneDressing()
}

/// The lounge's spots (machines, chairs, circles) and what chefs walk around in it.
nonisolated struct LoungeLayout: Sendable {
    let spots: [BreakRoomLayout.Spot]
    let obstacles: [CGRect]
    static let kitchen = LoungeLayout(spots: BreakRoomLayout.spots, obstacles: BreakRoomLayout.obstacles)
}

/// One scene's floor plan and station table: where stations stand, where chefs stand to work at
/// them, the walkable floor, and the intents its agents call for. The engine
/// (`DioramaSceneView`) reads everything layout-shaped from here.
struct SceneLayout {
    let kind: SceneKind
    let floor: CGRect
    let areas: [SceneArea]
    /// Cabinets that close the gaps between wall stations.
    let connectors: [CGRect]
    /// Low partial walls enclosing the lounge, with a doorway toward the floor.
    let partitionWalls: [CGRect]
    /// The elevator car's side and back walls; its interior and doorway stay walkable.
    let arrivalWalls: [CGRect]
    let lounge: LoungeLayout
    /// Where the manager comes in and leaves again.
    let managerDoor: ChefStation
    /// Where the lounge's sign stands (over its rug, not its little side table).
    let restSign: CGRect
    let dressing: SceneDressing
    /// Stand slots per area, in preference order.
    let chefSlots: [String: [ChefStation]]
    /// Walkable floor: fixtures are obstacles, inflated by the chef's half depth.
    let chefNavigation: FloorNavigation

    init(kind: SceneKind, floor: CGRect, areas: [SceneArea], connectors: [CGRect], partitionWalls: [CGRect], arrivalWalls: [CGRect],
         lounge: LoungeLayout, managerDoor: ChefStation, restSign: CGRect, dressing: SceneDressing) {
        self.kind = kind; self.floor = floor; self.areas = areas; self.connectors = connectors
        self.partitionWalls = partitionWalls; self.arrivalWalls = arrivalWalls; self.lounge = lounge
        self.managerDoor = managerDoor; self.restSign = restSign; self.dressing = dressing
        let navigation = Self.navigation(floor: floor, areas: areas, fixtures: connectors + partitionWalls + arrivalWalls + lounge.obstacles)
        chefNavigation = navigation
        chefSlots = Self.slots(areas: areas, lounge: lounge, navigation: navigation, gong: Self.gongCenter(areas))
    }

    // MARK: Fixed spots

    /// The service gong (or desk bell) stands at the bell footprint's centre, its face toward the camera.
    var gongCenter: SIMD2<Float> { Self.gongCenter(areas) }
    private static func gongCenter(_ areas: [SceneArea]) -> SIMD2<Float> {
        let f = areas.first { $0.id == "bell" }?.footprint ?? .init(x: -0.9, y: 4.9, width: 1.8, height: 0.6)
        return SIMD2(Float(f.midX), Float(f.midY))
    }
    /// Where a chef stands to strike the gong: in front of it and to its right, turned 45° toward
    /// it, so its mallet head (1.25 ahead and 0.17 to the right of it at impact, see the
    /// `strike_gong` clip) lands on the gong's face just right of centre.
    var gongStrike: ChefStation {
        let facing = -0.75 * Float.pi, forward = SIMD2(sin(facing), cos(facing)), right = SIMD2(-cos(facing), sin(facing))
        let impact = gongCenter + SIMD2(0.1, 0.1), scale = ChefMetrics.chefScale
        return ChefStation(id: "gong", area: "gong", stand: impact - forward * 0.89 * scale - right * 0.12 * scale, facing: facing)
    }
    /// Where the manager stands to talk with a chef waiting at `stand`: beside it, both in front of
    /// the gong, turned toward each other; the first spot that is free floor and clear of other
    /// waiting chefs (`others`), stepping a little further out from the gong if both sides are taken.
    func managerSpot(talkingTo stand: SIMD2<Float>, others: [SIMD2<Float>]) -> ChefStation {
        var out = stand - gongCenter
        out = simd_length(out) > 0.01 ? simd_normalize(out) : SIMD2(0, 1)
        let side = SIMD2(-out.y, out.x), reach = 1.2 as Float
        let candidates = [side * reach, -side * reach, side * reach + out * 0.7, -side * reach + out * 0.7, out * 1.4].map { stand + $0 }
        let spot = candidates.first { p in chefNavigation.isFree(p) && others.allSatisfy { simd_distance($0, p) > 0.9 } } ?? candidates[0]
        let toward = stand - spot
        return ChefStation(id: "manager", area: "manager", stand: spot, facing: atan2(toward.x, toward.y))
    }
    /// Just outside the elevator doors, facing the camera: a new chef steps out here and waves.
    var elevatorLanding: ChefStation {
        let door = areas.first { $0.id == "elevator" }?.footprint ?? .init(x: -11.6, y: -7.8, width: 2.4, height: 2.0)
        return ChefStation(id: "elevator landing", area: "elevator", stand: SIMD2(Float(door.midX), Float(door.maxY) + 1.2), facing: 0)
    }

    /// The lounge's floor: from its partition walls to the room's edges (the break room's corner).
    var loungeArea: CGRect {
        guard let first = partitionWalls.first else { return .null }
        let walls = partitionWalls.dropFirst().reduce(first) { $0.union($1) }
        return CGRect(x: floor.minX, y: walls.minY, width: walls.maxX - floor.minX, height: floor.maxY - walls.minY)
    }

    // MARK: Station table

    /// Where an agent's chef works here: the shared routing, dressed for this scene.
    func work(for agent: WorkspaceAgent, review: KitchenReviews.State? = nil) -> ChefWork {
        dressing.dress(SceneRouting.route(agent, review: review))
    }
    func intent(for agent: WorkspaceAgent, at slot: ChefStation?, pickup: ChefStation?, restored: Bool, review: KitchenReviews.State? = nil) -> ChefIntent {
        let work = work(for: agent, review: review)
        if let slot, slot.area == "serving", slot.id.contains("~") {
            // The pass is full: wait in line with the dish in hand until a spot frees up.
            return ChefIntent(key: ["serving-line", slot.id, "carry_idle"].joined(separator: "|"), station: slot, loop: "carry_idle",
                              oneShot: nil, hand: dressing.servingHand, pickup: restored ? nil : pickup, urgent: work.urgent)
        }
        // One-shot ids are stable per cause, so re-delivered states never replay a gesture.
        let cause = agent.completionKey ?? agent.meaningfulEventID
        let shot = work.oneShot.map { ChefIntent.OneShot(id: "\($0):\(agent.status.rawValue):\(cause)", clip: $0, restored: restored) }
        let key = [work.area ?? "here", slot?.id ?? "", work.loop, work.hand?.rawValue ?? "", shot?.id ?? ""].joined(separator: "|")
        return ChefIntent(key: key, station: work.area == nil ? nil : slot, loop: work.loop, oneShot: shot, hand: work.hand,
                          pickup: work.deliversPlate && !restored ? pickup : nil, urgent: work.urgent, prelude: restored ? nil : work.prelude,
                          strike: dressing.strikesNeedsYou && work.area == "bell" && shot != nil && !restored ? gongStrike : nil)
    }
    /// A new chef's first steps: out of the elevator, then a wave to the camera.
    func exitIntent(for agent: String) -> ChefIntent {
        ChefIntent(key: "arrival-exit", station: elevatorLanding, loop: "idle_available",
                   oneShot: .init(id: "arrive_wave:" + agent, clip: "arrive_wave", restored: false))
    }
    /// Then to the order rail, to read its ticket.
    func arrivalIntent(at slot: ChefStation) -> ChefIntent {
        ChefIntent(key: "arrival|" + slot.id, station: slot, loop: "read_ticket", hand: dressing.arrivalHand)
    }

    // MARK: Slots and floor

    /// Stand slots per area, in preference order. Chefs face the counter, standing so their
    /// hands reach it (`counter_front_from_root`).
    private static func slots(areas: [SceneArea], lounge: LoungeLayout, navigation: FloorNavigation, gong: SIMD2<Float>) -> [String: [ChefStation]] {
        let s = ChefMetrics.chefScale, reach = ChefMetrics.chefCounterFront * s, spacing = 1.05 * s
        var result: [String: [ChefStation]] = [:]
        func row(_ area: String, from a: SIMD2<Float>, to b: SIMD2<Float>, facing: Float, gap: Float = spacing) -> [ChefStation] {
            let length = simd_distance(a, b), count = max(1, Int(length / gap))
            let points = (0..<count).map { simd_mix(a, b, SIMD2(repeating: (Float($0) + 0.5) / Float(count))) }
            // Corner slots can fall inside a connecting cabinet; keep at least one per row.
            let free = points.filter(navigation.isFree)
            return (free.isEmpty ? points : free).map { ChefStation(id: "", area: area, stand: $0, facing: facing) }
        }
        for area in areas {
            let f = area.footprint
            let minX = Float(f.minX), maxX = Float(f.maxX), minZ = Float(f.minY), maxZ = Float(f.maxY)
            var slots: [ChefStation]
            switch area.id {
            case "elevator":
                slots = [ChefStation(id: "", area: area.id, stand: SIMD2(Float(f.midX), Float(f.midY)), facing: 0)]
            case "bell": // a curve in front of the gong (the camera's side), everyone facing it
                let radius = Float(1.7)
                let order: [Float] = [0, -38, 38, -76, 76, -100] // the middle first, then out to the sides
                slots = order.map { degrees in
                    let angle = degrees * .pi / 180
                    let stand = gong + SIMD2(sin(angle), cos(angle)) * radius
                    let toward = gong - stand
                    return ChefStation(id: "", area: area.id, stand: stand, facing: atan2(toward.x, toward.y))
                }
            case "break": // the machines, the two chairs and the standing circles (see `BreakRoom`)
                slots = lounge.spots.map(\.station)
            case "pantry": // a few roomy spots along the shelves
                slots = row(area.id, from: SIMD2(maxX + reach, minZ), to: SIMD2(maxX + reach, maxZ), facing: -.pi / 2, gap: (maxZ - minZ) / Float(area.spots))
            default:
                switch area.wall {
                case .back: slots = row(area.id, from: SIMD2(minX, maxZ + reach), to: SIMD2(maxX, maxZ + reach), facing: .pi)
                case .left: slots = row(area.id, from: SIMD2(maxX + reach, minZ), to: SIMD2(maxX + reach, maxZ), facing: -.pi / 2)
                case .right: slots = row(area.id, from: SIMD2(minX - reach, minZ), to: SIMD2(minX - reach, maxZ), facing: .pi / 2)
                case .front: slots = row(area.id, from: SIMD2(minX, minZ - reach), to: SIMD2(maxX, minZ - reach), facing: 0)
                case .island, .freestanding: // the far side faces the camera, then the near side
                    slots = row(area.id, from: SIMD2(minX, minZ - reach), to: SIMD2(maxX, minZ - reach), facing: 0)
                        + row(area.id, from: SIMD2(minX, maxZ + reach), to: SIMD2(maxX, maxZ + reach), facing: .pi)
                }
            }
            result[area.id] = slots.enumerated().map { ChefStation(id: "\(area.id)#\($0.offset)", area: area.id, stand: $0.element.stand, facing: $0.element.facing) }
        }
        return result
    }

    /// Fixtures are obstacles, inflated by the chef's half depth. The elevator car stays walkable
    /// (only its walls block) so arrivals can step out.
    private static func navigation(floor: CGRect, areas: [SceneArea], fixtures: [CGRect]) -> FloorNavigation {
        var navigation = FloorNavigation()
        let clearance = 0.35 * ChefMetrics.chefScale
        navigation.min = SIMD2(Float(floor.minX) + clearance, Float(floor.minY) + clearance)
        navigation.max = SIMD2(Float(floor.maxX) - clearance, Float(floor.maxY) - clearance)
        navigation.obstacles = (areas.filter { $0.id != "elevator" }.map(\.footprint) + fixtures).map { r in
            .init(min: SIMD2(Float(r.minX) - clearance, Float(r.minY) - clearance), max: SIMD2(Float(r.maxX) + clearance, Float(r.maxY) + clearance))
        }
        return navigation
    }

    /// Keeps each chef's slot while it stays in one area; otherwise takes the first free slot,
    /// queueing behind a taken slot when an area is full.
    func assignSlots(_ wants: [(id: String, area: String?)], previous: [String: ChefStation]) -> [String: ChefStation] {
        var result: [String: ChefStation] = [:], taken = Set<String>()
        for want in wants {
            if let area = want.area, let kept = previous[want.id], kept.area == area, !taken.contains(kept.id) {
                result[want.id] = kept; taken.insert(kept.id)
            }
        }
        var overflow: [String: Int] = [:]
        for want in wants where result[want.id] == nil {
            guard let area = want.area, let options = chefSlots[area], !options.isEmpty else { continue }
            if let free = options.first(where: { !taken.contains($0.id) }) {
                result[want.id] = free; taken.insert(free.id)
            } else {
                let n = overflow[area, default: 0]; overflow[area] = n + 1
                let base = options[n % options.count], back = Float(n / options.count + 1) * 0.95 * ChefMetrics.chefScale
                let stand = base.stand - SIMD2(sin(base.facing), cos(base.facing)) * back
                result[want.id] = ChefStation(id: "\(base.id)~\(n)", area: area, stand: stand, facing: base.facing)
            }
        }
        return result
    }

    static let kitchen = SceneLayout(kind: .kitchen, floor: KitchenLayout.floor, areas: KitchenLayout.areas, connectors: KitchenLayout.connectors,
                                     partitionWalls: KitchenLayout.breakRoomWalls, arrivalWalls: KitchenLayout.elevatorWalls, lounge: .kitchen,
                                     managerDoor: ChefStation(id: "dining door", area: "door", stand: SIMD2(1.9, Float(KitchenLayout.floor.maxY) - 0.6), facing: .pi),
                                     restSign: KitchenFloor.rug, dressing: .kitchen)
}
