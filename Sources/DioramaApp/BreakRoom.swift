import CoreGraphics
import simd

/// The break room's layout, in kitchen x/z: three arcade cabinets against the far wall, the red
/// vending machine against the left wall, two lounge chairs across a side table by the short wall,
/// and two standing circles on the rug.
/// Machines face the camera (far wall) or the room (left wall) so they read from the kitchen view.
nonisolated enum BreakRoomLayout {
    enum Kind: Equatable, Sendable { case arcade, vending, espresso, chair, circle(Int) }

    struct Machine: Sendable {
        /// Its model in `Resources/BreakRoom`, built by assets/breakroom/build.sh.
        let asset: String
        let kind: Kind
        /// Where its footprint is centred, which way its front faces (yaw: 0 is +z), and its size
        /// (width across its front, depth) once scaled.
        let center: SIMD2<Float>
        let facing: Float
        let size: SIMD2<Float>
        /// Uniform scale from the model's normalized size (widest side 1) to the kitchen.
        let scale: Float
        /// On the coffee bar, not the floor.
        var onBar = false
        var front: SIMD2<Float> { SIMD2(sin(facing), cos(facing)) }
        /// Where a chef stands to use it: its hands reach the controls (`chefCounterFront`).
        var use: ChefStation {
            let reach: Float = 0.43 * 1.4 // KitchenLayout.chefCounterFront × chefScale (checked in tests)
            let face = onBar ? coffeeBarDepth : size.y
            let stand = (onBar ? coffeeBar.center : center) + front * (face / 2 + reach + 0.02)
            let (cx, cz) = onBar ? (stand.x, center.y) : (stand.x, stand.y)
            return ChefStation(id: "break:" + asset, area: "break", stand: SIMD2(cx, cz), facing: facing + .pi)
        }
        /// The floor it takes up (axis-aligned; machines face along an axis).
        var rect: CGRect {
            let across = abs(sin(facing)) > 0.5 ? SIMD2(size.y, size.x) : size
            return CGRect(x: CGFloat(center.x - across.x / 2), y: CGFloat(center.y - across.y / 2), width: CGFloat(across.x), height: CGFloat(across.y))
        }
    }

    /// The room inside its walls (see `KitchenFloor.breakRoom`): far wall z 3.275, left wall x -11.72.
    static let farWall: Float = 3.275, leftWall: Float = -11.72
    static let coffeeBarDepth: Float = 0.72, coffeeBarLength: Float = 1.6
    static let coffeeBar = (center: SIMD2<Float>(leftWall + 0.02 + coffeeBarDepth / 2, 5.6), facing: Float.pi / 2)

    /// Arcade cabinets about 2 m tall (control panels at the chef's hands) and the vending machine,
    /// 2.1 m, where the coffee bar used to stand. Sizes are the normalized models' times scale.
    static let machines: [Machine] = {
        func far(_ asset: String, x: Float, width: Float, depth: Float, height: Float) -> Machine {
            let scale = 2.0 / height
            return Machine(asset: asset, kind: .arcade, center: SIMD2(x, farWall + 0.02 + depth * scale / 2), facing: 0,
                           size: SIMD2(width, depth) * scale, scale: scale)
        }
        let vendingScale: Float = 2.1 / 1.736
        return [
            far("arcade_cosmic", x: -8.9, width: 0.866, depth: 1.0, height: 2.05),
            far("arcade_jungle", x: -7.5, width: 1.0, depth: 0.95, height: 1.879),
            far("arcade_blue", x: -6.1, width: 1.0, depth: 0.938, height: 1.937),
            Machine(asset: "vending", kind: .vending, center: SIMD2(leftWall + 0.02 + 0.76 * vendingScale / 2, coffeeBar.center.y), facing: .pi / 2,
                    size: SIMD2(1.0, 0.76) * vendingScale, scale: vendingScale),
        ]
    }()

    /// The two lounge chairs' seats (a seated chef's root), facing each other across the side table.
    static let sideTable = CGRect(x: -4.8, y: 5.97, width: 0.6, height: 0.6)
    static var chairs: [ChefStation] {
        let x = Float(sideTable.midX), z = Float(sideTable.midY)
        return [ChefStation(id: "break:chair0", area: "break", stand: SIMD2(x, z - 0.97), facing: 0),
                ChefStation(id: "break:chair1", area: "break", stand: SIMD2(x, z + 0.97), facing: .pi)]
    }
    /// Standing circles: three around each centre (one at the back facing the camera, two in front),
    /// everyone facing the middle. A third, smaller group holds anyone over the count.
    static let circleCenters: [SIMD2<Float>] = [SIMD2(-8.6, 6.6), SIMD2(-6.5, 6.6)]
    static let circleRadius: Float = 0.95
    static var circles: [[ChefStation]] {
        var groups = circleCenters.enumerated().map { g, center in
            [Float(0), 120, -120].enumerated().map { i, degrees in
                let a = degrees * .pi / 180
                let stand = center + SIMD2(sin(a), -cos(a)) * circleRadius
                let toward = center - stand
                return ChefStation(id: "break:circle\(g).\(i)", area: "break", stand: stand, facing: atan2(toward.x, toward.y))
            }
        }
        // Overflow (resting chefs still walking in past the cap): a pair between the circles.
        let a = SIMD2<Float>(-7.55, 5.8), b = SIMD2<Float>(-4.9, 4.6)
        groups.append([ChefStation(id: "break:extra0", area: "break", stand: a, facing: atan2(b.x - a.x, b.y - a.y)),
                       ChefStation(id: "break:extra1", area: "break", stand: b, facing: atan2(a.x - b.x, a.y - b.y))])
        return groups
    }

    /// Every spot, in the order newcomers take them: machines, then chairs, then the circles.
    struct Spot: Sendable { let station: ChefStation; let kind: Kind }
    static var spots: [Spot] {
        machines.map { Spot(station: $0.use, kind: $0.kind) }
            + chairs.map { Spot(station: $0, kind: .chair) }
            + circles.enumerated().flatMap { g, group in group.map { Spot(station: $0, kind: .circle(g)) } }
    }
    /// What chefs walk around: the machines on the floor and the side table.
    static var obstacles: [CGRect] { machines.filter { !$0.onBar }.map(\.rect) + [sideTable] }
}

/// Who does what in the break room. Resting chefs take a free machine first, then a chair, then a
/// place in a circle. Every 45–90 s (each on its own clock) a machine's user hands it to whoever
/// has waited longest in a circle and joins the circle. In the circles and the chairs they take
/// turns: while one talks, the others listen or laugh. Pure state on a seeded clock, like
/// `RestaurantGuests`, so the kitchen and tests drive it the same way.
nonisolated struct BreakRoom {
    typealias Kind = BreakRoomLayout.Kind
    static let talking: Set<String> = ["talk_reply", "sit_talk", "sit_gesture"]
    static let laughing: Set<String> = ["stand_laugh", "sit_laugh"]
    private static let standChat: [(String, Double)] = [("talk_reply", 4), ("stand_listen", 2), ("stand_laugh", 1)]
    private static let standListen: [(String, Double)] = [("stand_listen", 3), ("stand_laugh", 2)]
    private static let sitChat: [(String, Double)] = [("sit_talk", 4), ("sit_gesture", 1.5), ("sit_sip", 1.5), ("sit_laugh", 1), ("sit_idle", 1)]
    private static let sitListen: [(String, Double)] = [("sit_idle", 2), ("sit_laugh", 2), ("sit_sip", 1)]
    static let turn: ClosedRange<Double> = 45...90

    struct Member: Equatable {
        var spot: Int
        var clip: String
        /// When its clip changes next.
        var until: Double
        /// When it came to this spot (a machine turn's start; the wait for one in a circle).
        var since: Double
        /// Machine users: when they hand over.
        var turnEnds: Double?
    }
    let spots: [BreakRoomLayout.Spot]
    private(set) var members: [String: Member] = [:]
    private var random: SplitMix
    private let durations: [String: Double]

    init(spots: [BreakRoomLayout.Spot] = BreakRoomLayout.spots, durations: [String: Double], seed: UInt64 = 0xB4EA) {
        self.spots = spots; self.durations = durations; random = SplitMix(seed: seed)
    }

    func station(for id: String) -> ChefStation? { members[id].map { spots[$0.spot].station } }
    func kind(of id: String) -> Kind? { members[id].map { spots[$0.spot].kind } }

    /// A resting chef arrives: the first free spot (machines, chairs, circles).
    mutating func join(_ id: String, now: Double) {
        guard members[id] == nil else { return }
        let taken = Set(members.values.map(\.spot))
        guard let spot = spots.indices.first(where: { !taken.contains($0) }) else { return }
        members[id] = Member(spot: spot, clip: "", until: 0, since: now)
        settle(id, now: now)
    }

    /// Keeps the members to the chefs resting now and moves everyone on; returns those whose spot
    /// or clip changed.
    mutating func update(resting: [String], now: Double) -> Set<String> {
        var changed = Set<String>()
        let staying = Set(resting)
        for id in members.keys where !staying.contains(id) { members[id] = nil }
        for id in resting.sorted() where members[id] == nil { join(id, now: now); changed.insert(id) }
        // A turn ends: the machine goes to the circle member who has waited longest.
        for id in members.keys.sorted() {
            guard let member = members[id], let ends = member.turnEnds, now >= ends else { continue }
            let waiting = members.filter { if case .circle = spots[$0.value.spot].kind { return true }; return false }
                .min { ($0.value.since, $0.key) < ($1.value.since, $1.key) }
            guard let (next, other) = waiting else { members[id]?.turnEnds = now + random.next(in: Self.turn); continue }
            members[id]?.spot = other.spot; members[id]?.since = now
            members[next]?.spot = member.spot; members[next]?.since = now
            settle(id, now: now); settle(next, now: now)
            changed.formUnion([id, next])
            break // one hand-over at a time keeps the room calm
        }
        for id in members.keys.sorted() where now >= members[id]!.until && !changed.contains(id) {
            choose(id, now: now)
            changed.insert(id)
        }
        return changed
    }

    /// Fresh at a spot: a machine's loop and a new turn, or a first word in a group.
    private mutating func settle(_ id: String, now: Double) {
        guard var member = members[id] else { return }
        switch spots[member.spot].kind {
        case .arcade: member.clip = "play_arcade"
        case .vending, .espresso: member.clip = "stand_sip"
        case .chair, .circle: member.clip = ""
        }
        if [Kind.arcade, .vending, .espresso].contains(spots[member.spot].kind) {
            member.turnEnds = now + random.next(in: Self.turn); member.until = .infinity
        } else {
            member.turnEnds = nil; member.until = now
        }
        members[id] = member
        if member.clip.isEmpty { choose(id, now: now) }
    }

    private mutating func choose(_ id: String, now: Double) {
        guard let member = members[id] else { return }
        let kind = spots[member.spot].kind
        let seated = kind == .chair
        guard seated || { if case .circle = kind { return true }; return false }() else { return }
        let group = members.filter { $0.key != id && spots[$0.value.spot].kind == kind }
        let someoneTalking = group.values.contains { Self.talking.contains($0.clip) }
        var options = seated ? (someoneTalking ? Self.sitListen : Self.sitChat) : (someoneTalking ? Self.standListen : Self.standChat)
        options = options.map { $0.0 == member.clip ? ($0.0, $0.1 * 0.25) : $0 } // keep it changing
        let total = options.reduce(0) { $0 + $1.1 }
        var x = random.next(in: 0...total)
        var clip = options.last!.0
        for (name, weight) in options { x -= weight; if x <= 0 { clip = name; break } }
        let loop = durations[clip] ?? 3
        members[id]?.clip = clip
        members[id]?.until = now + max(3, loop * Double(Int(random.next(in: 1...2.999))))
    }
}
