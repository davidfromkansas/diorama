import simd

/// The restaurant's guests: who sits where, and what each is doing. Pure state, so the kitchen
/// (and tests) drive it with the clock.
///
/// Partners at a table take turns: while one talks or gestures, the other listens, laughs or
/// eats; then it swaps. Every seat runs on its own seeded clock, so no two guests move in step,
/// and the same kitchen behaves the same way each time.
nonisolated struct RestaurantGuests {
    /// Talking to the table; a partner meanwhile listens.
    static let talking: Set<String> = ["sit_talk", "sit_gesture"]
    static let cheer = "sit_cheer", eat = "sit_eat"
    private static let chatting: [(String, Double)] = [("sit_talk", 4), ("sit_eat", 3), ("sit_gesture", 1.5), ("sit_sip", 1.5), ("sit_laugh", 1), ("sit_idle", 1)]
    private static let listening: [(String, Double)] = [("sit_idle", 2), ("sit_laugh", 2), ("sit_eat", 3), ("sit_sip", 1)]

    struct Seat {
        var clip: String
        var until: Double
        var random: SplitMix
        /// Being served: cheer, then eat until then.
        var feastUntil: Double?
    }
    private(set) var seats: [Seat]
    let partners: [Int?]
    private let durations: [String: Double]

    /// `positions`: each seat's dish on its table (tables seat two; a seat's partner is the one
    /// whose dish is nearest). `durations`: clip lengths in seconds.
    init(positions: [SIMD3<Float>], durations: [String: Double], seed: UInt64 = 0x5EA7) {
        self.durations = durations
        partners = positions.indices.map { i in
            positions.indices.filter { $0 != i }.min { simd_distance(positions[$0], positions[i]) < simd_distance(positions[$1], positions[i]) }
                .flatMap { simd_distance(positions[$0], positions[i]) < 1.5 ? $0 : nil }
        }
        seats = positions.indices.map { i in
            var random = SplitMix(seed: seed &+ UInt64(i) &* 0x9E3779B97F4A7C15)
            let clip = Self.pick(Self.chatting, &random)
            return Seat(clip: clip, until: random.next(in: 0.5...4.5), random: random)
        }
    }

    /// Advance to `now`; returns the seats whose clip changed.
    mutating func update(now: Double) -> [Int] {
        var changed: [Int] = []
        for i in seats.indices where now >= seats[i].until {
            if let feast = seats[i].feastUntil {
                if now < feast { seats[i].clip = Self.eat; seats[i].until = feast }
                else { seats[i].feastUntil = nil; choose(i, now: now) }
            } else {
                choose(i, now: now)
            }
            changed.append(i)
        }
        return changed
    }

    /// A served dish arrives: a cheer, then eating for `minutes` of scene time.
    mutating func serve(_ seat: Int, now: Double, eating seconds: Double = 12) {
        guard seats.indices.contains(seat) else { return }
        let cheer = durations[Self.cheer] ?? 1.6
        seats[seat].clip = Self.cheer
        seats[seat].until = now + cheer
        seats[seat].feastUntil = now + cheer + seconds
    }

    private mutating func choose(_ i: Int, now: Double) {
        let partnerTalking = partners[i].map { Self.talking.contains(seats[$0].clip) } ?? false
        var options = partnerTalking ? Self.listening : Self.chatting
        // Not the same thing twice running, so a table always changes.
        options = options.map { $0.0 == seats[i].clip ? ($0.0, $0.1 * 0.25) : $0 }
        let clip = Self.pick(options, &seats[i].random)
        let loop = durations[clip] ?? 3
        let repeats = Double(Int(seats[i].random.next(in: 1...2.999)))
        seats[i].clip = clip
        seats[i].until = now + max(3, loop * repeats)
    }

    private static func pick(_ options: [(String, Double)], _ random: inout SplitMix) -> String {
        let total = options.reduce(0) { $0 + $1.1 }
        var x = random.next(in: 0...total)
        for (clip, weight) in options {
            x -= weight
            if x <= 0 { return clip }
        }
        return options.last!.0
    }

    /// Which guest sits at each of `count` seats: every guest once (a fixed shuffle), then repeats
    /// at the seats farthest from where that guest already sits.
    static func cast(_ guests: [String], seats positions: [SIMD3<Float>], seed: UInt64 = 0xD1E7) -> [String] {
        guard !guests.isEmpty else { return [] }
        var random = SplitMix(seed: seed)
        var order = guests
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, Int(random.next(in: 0...Double(i) + 0.999))) }
        var cast = Array(order.prefix(positions.count))
        var repeated = Set<String>()
        while cast.count < positions.count {
            let seat = cast.count
            let candidates = order.filter { !repeated.contains($0) }
            let best = (candidates.isEmpty ? order : candidates).max { a, b in
                let da = cast.indices.filter { cast[$0] == a }.map { simd_distance(positions[$0], positions[seat]) }.min() ?? 0
                let db = cast.indices.filter { cast[$0] == b }.map { simd_distance(positions[$0], positions[seat]) }.min() ?? 0
                return da < db
            }!
            repeated.insert(best); cast.append(best)
        }
        return cast
    }
}

/// A small seeded generator (SplitMix64): the same guests do the same things every launch.
nonisolated struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
