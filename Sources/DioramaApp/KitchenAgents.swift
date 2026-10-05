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

    /// Where an agent's chef works. Station ids are `KitchenArea.id`s plus "home" (aisle).
    struct ChefWork: Equatable {
        var area: String?
        var loop: String
        var hand: ChefProp? = nil
        var oneShot: String? = nil
        var urgent = false
        var deliversPlate = false
    }
    static func work(for agent: WorkspaceAgent) -> ChefWork {
        switch agent.status {
        case .ready: return .init(area: "home", loop: "idle_available")
        case .working:
            switch KitchenActivity.classify(tool: agent.latestTool, detail: agent.latestToolDetail) {
            case .planning: return .init(area: "prep", loop: "planning_recipe", hand: .card)
            case .researching: return .init(area: "context", loop: "researching_book", hand: .book)
            case .editing, .other: return .init(area: "prep", loop: "working_chop", hand: .knife)
            case .commands: return .init(area: "build", loop: "waiting_tool")
            case .testing: return .init(area: "test", loop: "testing_dish", hand: .spoon)
            }
        case .waiting: return .init(area: "attention", loop: "wait_input", oneShot: "request_input", urgent: true)
        case .failed: return .init(area: "attention", loop: "blocked_wait", oneShot: "error_react", urgent: true)
        case .done: return .init(area: "review", loop: "wait_review", oneShot: "present_review", deliversPlate: true)
        case .stopped: return .init(area: nil, loop: "idle_available", oneShot: "cancel_cleanup", urgent: true)
        case .unknown: return .init(area: nil, loop: "unknown_wait", urgent: true)
        }
    }
    static func intent(for agent: WorkspaceAgent, at slot: ChefStation?, pickup: ChefStation?, restored: Bool) -> ChefIntent {
        let work = work(for: agent)
        // One-shot ids are stable per cause, so re-delivered states never replay a gesture.
        let cause = agent.completionKey ?? agent.meaningfulEventID
        let shot = work.oneShot.map { ChefIntent.OneShot(id: "\($0):\(agent.status.rawValue):\(cause)", clip: $0, restored: restored) }
        let key = [work.area ?? "here", slot?.id ?? "", work.loop, work.hand?.rawValue ?? "", shot?.id ?? ""].joined(separator: "|")
        return ChefIntent(key: key, station: work.area == nil ? nil : slot, loop: work.loop, oneShot: shot, hand: work.hand,
                          pickup: work.deliversPlate && !restored ? pickup : nil, urgent: work.urgent)
    }

    /// Stand slots per area, in preference order. Chefs face the counter, standing so their
    /// hands reach it (`counter_front_from_root`).
    static var chefSlots: [String: [ChefStation]] {
        let s = chefScale, reach = chefCounterFront * s, spacing = 1.05 * s
        var result: [String: [ChefStation]] = [:]
        let navigation = chefNavigation
        func row(_ area: String, from a: SIMD2<Float>, to b: SIMD2<Float>, facing: Float) -> [ChefStation] {
            let length = simd_distance(a, b), count = max(1, Int(length / spacing))
            let points = (0..<count).map { simd_mix(a, b, SIMD2(repeating: (Float($0) + 0.5) / Float(count))) }
            // Corner slots can fall inside a connecting cabinet; keep at least one per row.
            let free = points.filter(navigation.isFree)
            return (free.isEmpty ? points : free).enumerated().map { ChefStation(id: "\(area)#\($0.offset)", area: area, stand: $0.element, facing: facing) }
        }
        for area in areas {
            let f = area.footprint
            let minX = Float(f.minX), maxX = Float(f.maxX), minZ = Float(f.minY), maxZ = Float(f.maxY)
            switch area.id {
            case "context", "build": // back counters: stand in front, face the wall (-Z)
                result[area.id] = row(area.id, from: SIMD2(minX, maxZ + reach), to: SIMD2(maxX, maxZ + reach), facing: .pi)
            case "prep": // island: the far side faces the camera, then the near side
                let far = row(area.id, from: SIMD2(minX, minZ - reach), to: SIMD2(maxX, minZ - reach), facing: 0)
                let near = row(area.id, from: SIMD2(minX, maxZ + reach), to: SIMD2(maxX, maxZ + reach), facing: .pi)
                result[area.id] = (far + near).enumerated().map { ChefStation(id: "prep#\($0.offset)", area: "prep", stand: $0.element.stand, facing: $0.element.facing) }
            case "test": // sink on the right wall: face +X
                result[area.id] = row(area.id, from: SIMD2(minX - reach, minZ), to: SIMD2(minX - reach, maxZ), facing: .pi / 2)
            default: // front counters: stand behind them, facing the room's front (+Z)
                result[area.id] = row(area.id, from: SIMD2(minX, minZ - reach), to: SIMD2(maxX, minZ - reach), facing: 0)
            }
        }
        // Idle spots in the aisles beside the island, facing the camera.
        let aisle = Float(areas.first { $0.id == "prep" }?.footprint.minX ?? -2.5) - 0.8 * s
        result["home"] = [SIMD2(aisle, -0.6 * s), SIMD2(-aisle, -0.6 * s), SIMD2(aisle, 0.6 * s), SIMD2(-aisle, 0.6 * s)]
            .enumerated().map { ChefStation(id: "home#\($0.offset)", area: "home", stand: $0.element, facing: 0) }
        return result
    }

    /// Walkable floor: every fixture footprint is an obstacle, inflated by the chef's half depth.
    static var chefNavigation: WorkspaceCapybaraNavigation {
        var navigation = WorkspaceCapybaraNavigation()
        let clearance = 0.35 * chefScale
        navigation.min = SIMD2(Float(floor.minX) + clearance, Float(floor.minY) + clearance)
        navigation.max = SIMD2(Float(floor.maxX) - clearance, Float(floor.maxY) - clearance)
        navigation.obstacles = (areas.map(\.footprint) + connectors).map { r in
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
