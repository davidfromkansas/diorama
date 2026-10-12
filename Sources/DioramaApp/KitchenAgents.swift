import DioramaCore
import Foundation
import simd

/// Chef scale, station heights, stand slots and the agent → station table. Change stations here.
extension KitchenLayout {
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
    /// Agents make many tool calls a minute; this keeps the kitchen calm.
    static let minimumDwell: Double = 2
    /// How long a newly arrived chef reads its order at the rail.
    static let orderReading: Double = 3
    /// The arrival wave (`arrive_wave`: two jumps waving both hands, 2.4 s) and a beat after it,
    /// before it heads for the rail.
    static let arrivalWave: Double = 2.6
    /// The service gong hangs at the bell footprint's centre, its face toward the camera.
    static var gongCenter: SIMD2<Float> {
        let f = areas.first { $0.id == "bell" }?.footprint ?? .init(x: -0.9, y: 4.9, width: 1.8, height: 0.6)
        return SIMD2(Float(f.midX), Float(f.midY))
    }
    /// Where a chef stands to strike the gong: in front of it and to its right, turned 45° toward
    /// it, so its mallet head (1.25 ahead and 0.17 to the right of it at impact, see the
    /// `strike_gong` clip) lands on the gong's face just right of centre.
    static var gongStrike: ChefStation {
        let facing = -0.75 * Float.pi, forward = SIMD2(sin(facing), cos(facing)), right = SIMD2(-cos(facing), sin(facing))
        let impact = gongCenter + SIMD2(0.1, 0.1)
        return ChefStation(id: "gong", area: "gong", stand: impact - forward * 0.89 * chefScale - right * 0.12 * chefScale, facing: facing)
    }
    /// Where the manager comes in from the dining room and leaves again: the open front of the
    /// kitchen between the break room and the serving window.
    static var diningDoor: ChefStation {
        ChefStation(id: "dining door", area: "door", stand: SIMD2(1.9, Float(floor.maxY) - 0.6), facing: .pi)
    }
    /// Where the manager stands to talk with a chef waiting at `stand`: out from the gong, a step
    /// to one side, facing the chef; the first spot that is free floor and clear of other
    /// waiting chefs (`others`).
    static func managerSpot(talkingTo stand: SIMD2<Float>, others: [SIMD2<Float>]) -> ChefStation {
        let navigation = chefNavigation
        var out = stand - gongCenter
        out = simd_length(out) > 0.01 ? simd_normalize(out) : SIMD2(0, -1)
        let side = SIMD2(-out.y, out.x), reach = 1.6 as Float
        let candidates = [out + side * 0.6, out - side * 0.6, out, side, -side].map { stand + simd_normalize($0) * reach }
        let spot = candidates.first { p in navigation.isFree(p) && others.allSatisfy { simd_distance($0, p) > 0.9 } } ?? candidates[0]
        let toward = stand - spot
        return ChefStation(id: "manager", area: "manager", stand: spot, facing: atan2(toward.x, toward.y))
    }
    /// Just outside the elevator doors, facing the camera: a new chef steps out here and waves.
    static var elevatorLanding: ChefStation {
        let door = areas.first { $0.id == "elevator" }?.footprint ?? .init(x: -11.6, y: -7.8, width: 2.4, height: 2.0)
        return ChefStation(id: "elevator landing", area: "elevator", stand: SIMD2(Float(door.midX), Float(door.maxY) + 1.2), facing: 0)
    }

    /// Where an agent's chef works. Station ids are `KitchenArea.id`s.
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
    /// The lifecycle: prep before the first edit, then the island (editing) and stove (commands);
    /// tests at tasting; anything needing you at the bell; finished work at the serving window;
    /// stale or stopped sessions rest in the break room.
    static func work(for agent: WorkspaceAgent, review: KitchenReviews.State? = nil) -> ChefWork {
        let fresh = agent.freshness == .live || agent.freshness == .recentlyObserved
        // Finished work waits at the serving window until you decide, even after a restart.
        if let review, agent.isMain, ![.working, .waiting, .failed].contains(agent.status) {
            switch review {
            // Committed, merged, or marked done: the dish is accepted, so the chef celebrates and
            // heads to the break room.
            case .approved, .committed, .merged:
                var rest = breakRoom(agent, urgent: true); rest.prelude = "celebrate_done"; return rest
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
        case .stopped: return breakRoom(agent, urgent: true)
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
        default: return breakRoom(agent, urgent: true)
        }
    }
    /// Resting chefs sit down in a lounge chair and idle, sip coffee or chat (stable per agent).
    static func breakRoom(_ agent: WorkspaceAgent, urgent: Bool) -> ChefWork {
        let loops = ["sit_idle", "sit_sip", "sit_chat"]
        let pick = loops[Int(agent.id.utf8.reduce(UInt32(7)) { $0 &* 31 &+ UInt32($1) } % UInt32(loops.count))]
        return .init(area: "break", loop: pick, hand: pick == "sit_sip" ? .mug : nil, oneShot: "sit_down", urgent: urgent)
    }
    static func intent(for agent: WorkspaceAgent, at slot: ChefStation?, pickup: ChefStation?, restored: Bool, review: KitchenReviews.State? = nil) -> ChefIntent {
        let work = work(for: agent, review: review)
        if let slot, slot.area == "serving", slot.id.contains("~") {
            // The pass is full: wait in line with the dish in hand until a spot frees up.
            return ChefIntent(key: ["serving-line", slot.id, "carry_idle"].joined(separator: "|"), station: slot, loop: "carry_idle",
                              oneShot: nil, hand: .plate, pickup: restored ? nil : pickup, urgent: work.urgent)
        }
        // One-shot ids are stable per cause, so re-delivered states never replay a gesture.
        let cause = agent.completionKey ?? agent.meaningfulEventID
        let shot = work.oneShot.map { ChefIntent.OneShot(id: "\($0):\(agent.status.rawValue):\(cause)", clip: $0, restored: restored) }
        let key = [work.area ?? "here", slot?.id ?? "", work.loop, work.hand?.rawValue ?? "", shot?.id ?? ""].joined(separator: "|")
        return ChefIntent(key: key, station: work.area == nil ? nil : slot, loop: work.loop, oneShot: shot, hand: work.hand,
                          pickup: work.deliversPlate && !restored ? pickup : nil, urgent: work.urgent, prelude: restored ? nil : work.prelude,
                          strike: work.area == "bell" && shot != nil && !restored ? gongStrike : nil)
    }
    /// A new agent reads its order at the rail before starting work.
    /// A new chef's first steps: out of the elevator, then a wave to the camera.
    static func exitIntent(for agent: String) -> ChefIntent {
        ChefIntent(key: "arrival-exit", station: elevatorLanding, loop: "idle_available",
                   oneShot: .init(id: "arrive_wave:" + agent, clip: "arrive_wave", restored: false))
    }
    /// Then to the order rail, to read its ticket.
    static func arrivalIntent(at slot: ChefStation) -> ChefIntent {
        ChefIntent(key: "arrival|" + slot.id, station: slot, loop: "read_ticket", hand: .ticket)
    }

    /// Stand slots per area, in preference order. Chefs face the counter, standing so their
    /// hands reach it (`counter_front_from_root`).
    static var chefSlots: [String: [ChefStation]] {
        let s = chefScale, reach = chefCounterFront * s, spacing = 1.05 * s
        var result: [String: [ChefStation]] = [:]
        let navigation = chefNavigation
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
            case "bell": // a curve behind and beside the gong, everyone facing it (its face stays in view)
                let center = gongCenter, radius = Float(1.7)
                let order: [Float] = [0, -38, 38, -76, 76, -100] // the middle first, then out to the sides
                slots = order.map { degrees in
                    let angle = degrees * .pi / 180
                    let stand = center + SIMD2(sin(angle), -cos(angle)) * radius
                    let toward = center - stand
                    return ChefStation(id: "", area: area.id, stand: stand, facing: atan2(toward.x, toward.y))
                }
            case "break": // the machines, the two chairs and the standing circles (see `BreakRoom`)
                slots = BreakRoomLayout.spots.map(\.station)
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

    /// Walkable floor: fixtures are obstacles, inflated by the chef's half depth. The elevator car
    /// stays walkable (only its walls block) so arrivals can step out.
    static var chefNavigation: WorkspaceCapybaraNavigation {
        var navigation = WorkspaceCapybaraNavigation()
        let clearance = 0.35 * chefScale
        navigation.min = SIMD2(Float(floor.minX) + clearance, Float(floor.minY) + clearance)
        navigation.max = SIMD2(Float(floor.maxX) - clearance, Float(floor.maxY) - clearance)
        let fixtures = areas.filter { $0.id != "elevator" }.map(\.footprint) + connectors + breakRoomWalls + elevatorWalls + BreakRoomLayout.obstacles
        navigation.obstacles = fixtures.map { r in
            .init(min: SIMD2(Float(r.minX) - clearance, Float(r.minY) - clearance), max: SIMD2(Float(r.maxX) + clearance, Float(r.maxY) + clearance))
        }
        return navigation
    }

    /// Keeps each chef's slot while it stays in one area; otherwise takes the first free slot,
    /// queueing behind a taken slot when an area is full.
    static func assignSlots(_ wants: [(id: String, area: String?)], previous: [String: ChefStation]) -> [String: ChefStation] {
        let slots = chefSlots
        var result: [String: ChefStation] = [:], taken = Set<String>()
        for want in wants {
            if let area = want.area, let kept = previous[want.id], kept.area == area, !taken.contains(kept.id) {
                result[want.id] = kept; taken.insert(kept.id)
            }
        }
        var overflow: [String: Int] = [:]
        for want in wants where result[want.id] == nil {
            guard let area = want.area, let options = slots[area], !options.isEmpty else { continue }
            if let free = options.first(where: { !taken.contains($0.id) }) {
                result[want.id] = free; taken.insert(free.id)
            } else {
                let n = overflow[area, default: 0]; overflow[area] = n + 1
                let base = options[n % options.count], back = Float(n / options.count + 1) * 0.95 * chefScale
                let stand = base.stand - SIMD2(sin(base.facing), cos(base.facing)) * back
                result[want.id] = ChefStation(id: "\(base.id)~\(n)", area: area, stand: stand, facing: base.facing)
            }
        }
        return result
    }
}
