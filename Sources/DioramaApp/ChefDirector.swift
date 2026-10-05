import Foundation
import simd

/// A place a chef stands to work: a station slot or an aisle spot. Floor X/Z, facing yaw
/// (the chef model faces +Z at yaw 0; `x += sin(yaw)`, `z += cos(yaw)` when walking).
struct ChefStation: Equatable {
    let id: String
    let area: String
    let stand: SIMD2<Float>
    let facing: Float
}

/// What a chef should be doing for its agent's current state. Equal keys mean "keep going".
struct ChefIntent: Equatable {
    struct OneShot: Equatable {
        let id: String
        let clip: String
        /// Already happened before the chef saw it (history, view re-entry): apply its end
        /// state without replaying the gesture.
        var restored: Bool
    }
    var key: String
    /// Where to stand; nil stays put (urgent states never wait on travel).
    var station: ChefStation?
    var loop: String
    var oneShot: OneShot? = nil
    var hand: ChefProp? = nil
    /// Pick the plate up here and carry it to `station` before presenting.
    var pickup: ChefStation? = nil
    var urgent = false
    /// A gesture played where the chef stands before it sets off (arrival wave, celebration).
    var prelude: String? = nil
}

struct ChefClipCommand: Equatable {
    var name: String
    var loop: Bool
    /// Changes whenever the clip must (re)start, even with the same name.
    var token: Int
    var fade: Float
    var timeScale: Float
}

/// Engine-independent chef behaviour: navigation, clip sequencing, marker-synchronised prop
/// hand-offs and interruption reconciliation. Ported from the avatar prototype
/// (`app/src/avatar/director.ts`); routes now avoid kitchen fixtures. ChefAvatar renders
/// whatever this decides; tests drive it directly.
@MainActor final class ChefDirector {
    static let walkSpeed: Float = 0.75, runSpeed: Float = 1.55, runDistance: Float = 2.6
    static let turnRate: Float = 7, acceleration: Float = 4
    static let fade: Float = 0.22, urgentFade: Float = 0.12, locomotionFade: Float = 0.15
    static let locomotionClips: Set<String> = ["walk", "run", "carry_walk"]

    let clips: [String: ChefManifest.Clip]
    /// World units per chef unit: speeds and tolerances scale with the rendered chef.
    let unit: Float
    var navigation: WorkspaceCapybaraNavigation
    var reducedMotion = false
    /// Markers crossed in looping clips (e.g. each knife impact in `working_chop`).
    var onEvent: ((_ marker: String, _ clip: String) -> Void)?

    private(set) var position = SIMD2<Float>.zero
    private(set) var heading: Float = 0
    private(set) var speed: Float = 0
    private(set) var clip = ChefClipCommand(name: "idle_available", loop: true, token: 0, fade: 0, timeScale: 1)
    private(set) var clipTime: Float = 0
    private(set) var intent: ChefIntent?
    /// Where the chef stands after arriving; nil while travelling or after leaving.
    private(set) var station: ChefStation?
    private(set) var held: Set<ChefProp> = []
    /// The plate left on the pass after presenting; cleared when the chef moves on.
    private(set) var placedPlate: ChefStation?

    private enum Step {
        case goto(ChefStation, carry: Bool)
        case face(Float, carry: Bool)
        case grab(ChefProp)
        case once(String, markers: [String: () -> Void], interrupted: (() -> Void)?)
        case loop(String)
    }
    private var steps: [Step] = []
    private var path: [SIMD2<Float>] = []
    private var pathGoal: SIMD2<Float>?
    private var fired: Set<String> = []
    private var played: Set<String> = []
    private var token = 0

    init(clips: [String: ChefManifest.Clip], unit: Float, navigation: WorkspaceCapybaraNavigation) {
        self.clips = clips; self.unit = unit; self.navigation = navigation
    }

    /// Only the terminal loop remains and nothing moves.
    var settled: Bool {
        guard steps.count == 1, case .loop = steps[0] else { return steps.isEmpty }
        return speed == 0
    }
    var stepNames: [String] {
        steps.map {
            switch $0 {
            case let .goto(station, _): "goto:\(station.area)"
            case let .face(_, carry): carry ? "face:carry" : "face"
            case let .grab(prop): "grab:\(prop.rawValue)"
            case let .once(clip, _, _): "once:\(clip)"
            case let .loop(clip): "loop:\(clip)"
            }
        }
    }

    func place(_ point: SIMD2<Float>, heading: Float = 0) {
        position = point; self.heading = heading; speed = 0; path = []; pathGoal = nil
    }

    func setIntent(_ requested: ChefIntent) {
        guard intent?.key != requested.key else { return }
        var next = requested
        // A one-shot id plays at most once per chef, whatever re-plans happen afterwards.
        if let shot = next.oneShot {
            if played.contains(shot.id) { next.oneShot?.restored = true; next.pickup = nil }
            played.insert(shot.id)
        }
        interrupt(next)
        intent = next
        if next.urgent && next.station == nil { speed = 0; path = []; pathGoal = nil }
        var plan: [Step] = []
        if !reducedMotion {
            // Get out of the chair before walking off, then any requested gesture.
            let seated = clip.name.hasPrefix("sit_")
            if seated && next.station != station && next.station != nil { plan.append(.once("stand_up", markers: [:], interrupted: nil)) }
            if let prelude = next.prelude { plan.append(.once(prelude, markers: [:], interrupted: nil)) }
        }
        if let target = next.station {
            let carry = next.pickup != nil || (held.contains(.plate) && next.oneShot?.clip == "present_review")
            if let pickup = next.pickup, !held.contains(.plate) {
                plan += [.goto(pickup, carry: false), .face(pickup.facing, carry: false),
                         .once("pickup", markers: ["attach": { [weak self] in self?.held.insert(.plate) }], interrupted: nil)]
            }
            if station != target || simd_distance(position, target.stand) > 0.05 * unit { plan.append(.goto(target, carry: carry)) }
            plan.append(.face(target.facing, carry: carry))
            if let hand = next.hand { plan.append(.grab(hand)) }
        }
        if let shot = next.oneShot, !shot.restored, !reducedMotion {
            plan.append(oneShotStep(shot.clip, at: next.station))
        } else if next.oneShot != nil {
            applyOutcome(next) // jump to the end state without replaying the gesture
        }
        plan.append(.loop(next.loop))
        steps = plan
        startStep(fade: next.urgent ? Self.urgentFade : Self.fade)
    }

    /// Reconcile everything the current sequence was in the middle of.
    private func interrupt(_ next: ChefIntent) {
        if case let .once(_, _, interrupted)? = steps.first { interrupted?() }
        var keep: Set<ChefProp> = []
        if let hand = next.hand { keep.insert(hand) }
        if next.pickup != nil { keep.insert(.plate) }
        if next.oneShot?.clip == "cancel_cleanup", next.oneShot?.restored == false, !reducedMotion {
            keep.formUnion(held) // put down during cancel_cleanup
        }
        held.formIntersection(keep)
        if let placedPlate, next.station != placedPlate { self.placedPlate = nil }
        if let station, next.station != station { self.station = nil }
        path = []; pathGoal = nil
    }

    private func oneShotStep(_ name: String, at target: ChefStation?) -> Step {
        switch name {
        case "present_review":
            let release = { [weak self] in
                guard let self, self.held.contains(.plate) else { return }
                self.held.remove(.plate)
                self.placedPlate = target.flatMap { simd_distance(self.position, $0.stand) < 0.1 * self.unit ? $0 : nil }
            }
            return .once(name, markers: ["release": release], interrupted: release)
        case "cancel_cleanup":
            let release = { [weak self] in self?.held.removeAll(); return }
            return .once(name, markers: ["release": release], interrupted: release)
        default:
            return .once(name, markers: [:], interrupted: nil)
        }
    }

    private func applyOutcome(_ next: ChefIntent) {
        switch next.oneShot?.clip {
        case "present_review": held.remove(.plate); placedPlate = next.station
        case "cancel_cleanup": held.removeAll()
        default: break
        }
    }

    private func play(_ name: String, fade: Float, restart: Bool = false, timeScale: Float = 1) {
        if clip.name == name && !restart { clip.timeScale = timeScale; return }
        token += 1
        clip = ChefClipCommand(name: name, loop: clips[name]?.loop ?? true, token: token, fade: fade, timeScale: timeScale)
        clipTime = 0; fired = []
    }

    private func startStep(fade: Float) {
        guard let step = steps.first else { return }
        switch step {
        case let .once(name, _, _): play(name, fade: fade, restart: true)
        case let .loop(name): play(name, fade: fade)
        case let .goto(_, carry), let .face(_, carry):
            // While turning in place keep a stationary loop; walking settles to idle.
            play(carry ? "carry_idle" : Self.locomotionClips.contains(clip.name) ? "idle_available" : clip.name, fade: fade)
        case .grab: break
        }
    }

    private func advance() {
        steps.removeFirst()
        startStep(fade: Self.fade)
    }

    func update(_ delta: Float) {
        var dt = max(0, delta)
        let meta = clips[clip.name], previous = clipTime
        clipTime += dt * clip.timeScale
        if let meta, meta.loop, meta.duration > 0, !reducedMotion, let onEvent {
            // Fire loop markers crossed this frame, including across the wrap.
            let u0 = previous / meta.duration, u1 = clipTime / meta.duration, base = u0.rounded(.down)
            for (name, at) in meta.markers { for k in [base, base + 1] where k + at > u0 && k + at <= u1 { onEvent(name, clip.name) } }
        }
        var budget = 8
        loop: while budget > 0, let step = steps.first {
            budget -= 1
            switch step {
            case let .goto(target, carry):
                guard move(to: target, carry: carry, dt: dt) else { break loop }
                station = target
                advance(); dt = 0
            case let .face(yaw, _):
                guard turn(to: yaw, dt: dt) else { break loop }
                advance()
            case let .grab(prop):
                held.insert(prop)
                advance()
            case let .once(name, markers, _):
                let meta = clips[name]
                let u = meta.map { clipTime / max($0.duration, 0.0001) } ?? 1
                for (marker, at) in meta?.markers ?? [:] where u >= at && !fired.contains(marker) {
                    fired.insert(marker); markers[marker]?()
                }
                guard u >= 1 else { break loop }
                advance()
            case .loop:
                break loop
            }
        }
        if let meta = clips[clip.name], meta.loop, meta.duration > 0, clipTime > meta.duration {
            clipTime = clipTime.truncatingRemainder(dividingBy: meta.duration)
        }
    }

    private func move(to target: ChefStation, carry: Bool, dt: Float) -> Bool {
        if pathGoal != target.stand {
            pathGoal = target.stand
            path = navigation.route(from: position, to: target.stand) ?? [target.stand]
        }
        while path.count > 1, simd_distance(position, path[0]) < 0.2 * unit { path.removeFirst() }
        let goal = path.first ?? target.stand, final = path.count <= 1
        let delta = goal - position, distance = simd_length(delta)
        if final && distance < 0.03 * unit {
            position = target.stand; speed = 0; path = []; pathGoal = nil
            return true
        }
        let error = Self.wrap(atan2(delta.x, delta.y) - heading)
        heading = Self.wrap(heading + max(-Self.turnRate * dt, min(Self.turnRate * dt, error)))
        let remaining = simd_distance(position, target.stand)
        let run = !carry && remaining > Self.runDistance * unit
        let top = (run ? Self.runSpeed : Self.walkSpeed * (carry ? 0.9 : 1)) * unit
        let wanted = min(top, final ? distance * 3 : top) * max(0, cos(error))
        speed += max(-Self.acceleration * unit * dt * 2, min(Self.acceleration * unit * dt, wanted - speed))
        let step = min(speed * dt, distance)
        position += SIMD2(sin(heading), cos(heading)) * step
        let moving = speed > 0.02 * unit
        let name = carry ? "carry_walk" : run && speed > Self.walkSpeed * unit * 1.1 ? "run" : moving ? "walk" : "idle_available"
        // Stride playback follows actual ground speed; stepping stops when movement stops.
        let scale = clips[name]?.nominalSpeed.map { max(0.6, min(1.5, speed / ($0 * unit))) } ?? 1
        play(name, fade: Self.locomotionFade, timeScale: scale)
        return false
    }

    private func turn(to yaw: Float, dt: Float) -> Bool {
        let error = Self.wrap(yaw - heading)
        if abs(error) < 0.02 { heading = yaw; return true }
        heading = Self.wrap(heading + max(-Self.turnRate * dt, min(Self.turnRate * dt, error)))
        return false
    }

    static func wrap(_ angle: Float) -> Float {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}
