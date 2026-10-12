import AppKit
import DioramaCore
@preconcurrency import SceneKit

/// What a chef picks up at a station and carries out in both hands: from the pantry a salsa jar
/// for a skill, a crate for a plugin, a connector object for an MCP server or app; from prep a plan
/// plate; from the order rail a lightbulb (the idea); from the cooking island the chopped board it
/// worked on; from the stove its pot. It sits on the counter while the chef is there, is carried
/// (carry walk) to the next station, set down there and fades.
enum PantryCarry {
    nonisolated enum Kind: String, Sendable {
        case skill, plugin, connector, plan, idea, board, pot
        /// Kinds that stand for the station rather than the tool call: staying at the station
        /// keeps the same one instead of popping a new one each call.
        var sticky: Bool { [.plan, .idea, .board, .pot].contains(self) }
    }
    nonisolated struct Item: Equatable, Sendable {
        let kind: Kind
        let name: String
    }

    /// What the chef is fetching: the current tool call when it's a pantry resource, else the
    /// last resource of the turn (an owed pantry visit replays that one).
    static func item(for agent: WorkspaceAgent) -> Item? {
        if let item = item(tool: agent.latestTool, detail: agent.latestToolDetail) { return item }
        // The latest resource of the turn that names something (listings and plumbing don't).
        for entry in agent.turnWork.resources.reversed() where !entry.isEmpty {
            let found = entry.hasPrefix("skill://") ? item(tool: "read_mcp_resource", detail: entry)
                : entry.hasPrefix("mcp__") || LiveResources.isBrowsing(entry) ? item(tool: entry, detail: "")
                : entry.lowercased() == "skill" ? nil : item(tool: "Skill", detail: entry)
            if let found { return found }
        }
        return nil
    }
    static func item(tool: String, detail: String) -> Item? {
        // A skill read from an installed plugin (…/plugins/cache/<marketplace>/<plugin>/…/SKILL.md)
        // is that plugin's.
        if KitchenActivity.isSkillFile(detail), let plugin = pluginFolder(detail) { return Item(kind: .plugin, name: BrandMark.match(plugin)?.title ?? plugin) }
        guard let resource = LiveResources.resource(tool: tool, detail: detail) else { return nil }
        switch resource.kind {
        case .skill:
            // A skill a plugin brought (fetched from it by MCP resource): its crate.
            if let plugin = resource.plugin { return Item(kind: .plugin, name: plugin.hasPrefix("plugin_") ? resource.name : plugin) }
            // A namespaced skill ("vercel:deploy") comes from its plugin.
            if let colon = resource.name.firstIndex(of: ":"), colon != resource.name.startIndex {
                let plugin = String(resource.name[..<colon])
                return Item(kind: .plugin, name: BrandMark.match(plugin)?.title ?? plugin)
            }
            return Item(kind: .skill, name: resource.name)
        case .server:
            if let plugin = resource.plugin { return Item(kind: .plugin, name: BrandMark.match(plugin)?.title ?? plugin) }
            return Item(kind: .connector, name: resource.name)
        }
    }
    /// What a chef leaving the prep area carries on its plate: the step it's starting (the plan's
    /// step in progress, else the next one), else what it's doing, else just "Prep".
    static func planItem(for agent: WorkspaceAgent) -> Item {
        let steps = agent.plan?.checklist ?? []
        let active = steps.first { ["in_progress", "inprogress", "in progress", "running"].contains($0.status.lowercased()) }
            ?? steps.first { $0.status.lowercased() == "pending" }
        if let step = active?.title.trimmingCharacters(in: .whitespacesAndNewlines), !step.isEmpty { return Item(kind: .plan, name: step) }
        // What it's doing, unless that's only "Working…": then the task it's on.
        let phrase = AgentSidebar.phrase(agent).trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty, phrase != "Working…" { return Item(kind: .plan, name: phrase) }
        let task = TaskTitle.compact(agent.task).trimmingCharacters(in: .whitespacesAndNewlines)
        return Item(kind: .plan, name: task.isEmpty ? "Prep" : task)
    }
    /// What there is to pick up at a station that always has the same thing: the order rail's
    /// lightbulb, the cooking island's chopped board, the stove's pot.
    nonisolated static func stationItem(area: String) -> Item? {
        switch area {
        case "order": Item(kind: .idea, name: "Order")
        case "cooking": Item(kind: .board, name: "Chopped board")
        case "stove": Item(kind: .pot, name: "Stove pot")
        default: nil
        }
    }
    static func pluginFolder(_ text: String) -> String? {
        guard let range = text.range(of: "/plugins/cache/") else { return nil }
        let parts = text[range.upperBound...].split(separator: "/")
        return parts.count > 2 ? String(parts[1]) : nil
    }
    /// The models, by kind (`assets/props`).
    static var models: [Kind: SCNNode] {
        var result: [Kind: SCNNode] = [:]
        for (kind, id) in [(Kind.skill, "salsa_jar"), (.plugin, "plugin_crate"), (.connector, "connector_object"), (.plan, "plan_plate"),
                           (.idea, "lightbulb"), (.board, "chopped_board"), (.pot, "stove_pot")] { result[kind] = KitchenProps.templates[id] }
        return result
    }
}

/// One chef's pantry carry. `sync` runs every frame from the avatar, on the kitchen's render
/// thread under the chef lock.
nonisolated final class PantryCarrier: @unchecked Sendable {
    private let models: [PantryCarry.Kind: SCNNode]
    init(models: [PantryCarry.Kind: SCNNode]) { self.models = models }
    enum Placement: Equatable { case none, counter, carried, setDown }
    static let size: Float = 0.5
    /// Each kind's size (the models are normalized to a widest side of 1).
    static func size(_ kind: PantryCarry.Kind?) -> Float {
        switch kind {
        case .idea: 0.35
        case .board: 0.6
        case .pot: 0.55
        default: size
        }
    }
    /// Where the chopped board rests while the chef chops on it: on the station's board spot.
    static let boardSpot = SIMD3<Float>(-0.05, 0, 0.7)
    static let fade: Float = 3.5

    private(set) var placement = Placement.none
    private(set) var item: PantryCarry.Item?
    private(set) var node: SCNNode?
    /// 1 until it's set down, then down to 0 as it fades.
    private(set) var opacity: Float = 1
    private var faded: Float = 0

    /// The director carries it (carry walk) from the pantry until it's set down.
    var carrying: Bool { placement == .counter || placement == .carried }
    /// Stations with a counter at `counterTop` to set things down on.
    static let counterAreas: Set<String> = ["order", "prep", "cooking", "stove", "tasting", "pantry", "serving"]

    // Where it rests in the current placement; the animation plays on top of this.
    private var base = (position: SIMD3<Float>.zero, orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    /// Seconds in the current placement, and overall (for the carry jostle).
    private var phase: Float = 0
    private var clock: Float = 0
    private var landed = false
    private var reducedMotion = false

    /// - Parameters:
    ///   - wanted: what there is to pick up at each pickup station ("pantry": what it's fetching,
    ///     "prep": the plate with its step).
    ///   - area: the station the chef stands at (nil while walking).
    ///   - delivering: the chef is taking its dish to the serving window (picking it up or
    ///     carrying it). The dish goes in its arms instead: anything picked up here is set down.
    func sync(wanted: [String: PantryCarry.Item], area: String?, reducedMotion: Bool, delta: Float,
              carrySocket: SCNNode?, fit: (position: SIMD3<Float>, orientation: simd_quatf)?, floor: SCNNode, counterTop: Float,
              delivering: Bool = false) {
        self.reducedMotion = reducedMotion
        let step = max(0, min(delta, 0.1))
        phase += step; clock += step
        fadeRetired(step)
        if let area, wanted[area] != nil, delivering {
            // The dish wins: what it picked up here stays here, set down before it walks off.
            if carrying { retire(floor: floor, counterTop: counterTop) }
            return
        }
        if let area, let want = wanted[area] {
            if carrying && origin == area && item?.kind == want.kind && (want.kind.sticky || item == want) {
                // Still at the station it came from: the same thing (a plate's step follows the plan).
                item = want
            } else {
                // Whatever it was holding is set down here; the new thing pops onto the counter.
                if carrying { retire(floor: floor, counterTop: counterTop) }
                spawn(want); origin = area
            }
            // The chopped board lies where the chef chops; everything else stands on the counter.
            let spot = want.kind == .board ? Self.boardSpot + SIMD3(0, counterTop, 0) : SIMD3(0, counterTop, 0.5)
            place(.counter, parent: floor, position: spot, orientation: nil)
            animate()
            return
        }
        switch placement {
        case .counter, .carried:
            if area == nil {
                // Walking away: in both hands, on the carry socket like the plate.
                if let carrySocket { place(.carried, parent: carrySocket, position: fit?.position ?? .zero, orientation: fit?.orientation) }
                else { place(.carried, parent: floor, position: SIMD3(0, counterTop * 0.85, 0.32), orientation: nil) }
            } else if !Self.counterAreas.contains(area!) {
                // Arrived where there's no counter (the break room, the gong): nowhere to set it
                // down, so it vanishes in a poof from the chef's arms rather than hanging in the air.
                if let node, !reducedMotion { puff(node) }
                clear(); return
            } else {
                // Arrived somewhere else: set it down beside the chef, then let it fade.
                faded = 0; opacity = 1; landed = false
                place(.setDown, parent: floor, position: SIMD3(0.42, counterTop, 0.5), orientation: nil)
                if reducedMotion { clear(); return }
            }
        case .setDown:
            // A beat on the counter, then it fades.
            if phase > 0.6 { faded += step }
            opacity = max(0, 1 - faded / Self.fade)
            if opacity <= 0 { clear(); return }
        case .none:
            break
        }
        animate()
    }

    /// The fun part, on top of the resting pose: a springy pop when it appears, a jostle in the
    /// chef's arms, a bounce and squash when it's set down, and a shrinking poof as it fades.
    private func animate() {
        guard let node else { return }
        var offset = SIMD3<Float>.zero, scale = SIMD3<Float>(repeating: 1), turn = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if !reducedMotion {
            switch placement {
            case .counter where item?.kind == .board:
                // The board pops into place and then lies still, so the knife meets it.
                scale = SIMD3(repeating: Self.overshoot(min(1, phase / 0.45)))
            case .counter:
                // Pops up out of the shelf with an overshoot and a half spin, then hovers.
                let p = min(1, phase / 0.45)
                scale = SIMD3(repeating: Self.overshoot(p))
                offset.y = 0.22 * (1 - p) * (1 - p) + (p >= 1 ? 0.025 * sin(phase * 3) : 0)
                turn = simd_quatf(angle: Float.pi * (1 - p), axis: SIMD3(0, 1, 0))
            case .carried:
                // Jostles in the arms with each step, tipping side to side.
                let gait = clock * 8.5
                offset.y = 0.035 * abs(sin(gait))
                turn = simd_quatf(angle: 0.14 * sin(gait), axis: SIMD3(0, 0, 1)) * simd_quatf(angle: 0.07 * sin(gait * 0.5), axis: SIMD3(1, 0, 0))
                // A little lift into the arms first.
                let p = min(1, phase / 0.25)
                scale = SIMD3(repeating: 0.85 + 0.15 * Self.overshoot(p))
            case .setDown:
                // Dropped from the arms: bounces twice, squashes on landing.
                let p = min(1, phase / 0.5)
                let bounce = abs(cos(p * Float.pi * 2.5)) * (1 - p) * (1 - p)
                offset.y = 0.28 * bounce
                let squash = p > 0.15 && p < 0.55 ? sin((p - 0.15) / 0.4 * Float.pi) * 0.18 : 0
                scale = SIMD3(1 + squash, 1 - squash, 1 + squash)
                if p >= 0.2, !landed { landed = true; puff(node) }
                // Fading: shrinks and floats up a touch, like a poof.
                let gone = 1 - opacity
                scale *= 1 - 0.45 * gone
                offset.y += 0.2 * gone
            case .none:
                break
            }
        }
        node.simdPosition = base.position + offset
        node.simdOrientation = base.orientation * turn
        node.simdScale = scale * Self.size(item?.kind)
        node.opacity = CGFloat(opacity)
    }
    static func overshoot(_ p: Float) -> Float {
        // Ease out back: past 1 and settle.
        let c: Float = 2.2, x = p - 1
        return 1 + (c + 1) * x * x * x + c * x * x
    }

    func clear() {
        node?.removeFromParentNode(); node = nil; item = nil; origin = nil; placement = .none; opacity = 1; faded = 0; phase = 0; landed = false
    }

    /// The station the current item came from.
    private(set) var origin: String?
    /// Items put down when a new one was picked up at a pickup station, fading out beside the chef.
    private var retired: [(node: SCNNode, time: Float, size: Float)] = []
    private func retire(floor: SCNNode, counterTop: Float) {
        guard let node else { return }
        if reducedMotion { node.removeFromParentNode() } else {
            // Still on this counter: it stays where it lies. In the arms: set down beside the chef.
            let lies = placement == .counter
            node.removeFromParentNode(); floor.addChildNode(node)
            node.simdPosition = lies ? base.position : SIMD3(0.42, counterTop, 0.5); node.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            retired.append((node, 0, Self.size(item?.kind)))
            puff(node)
        }
        self.node = nil; item = nil; origin = nil; placement = .none; opacity = 1; faded = 0
    }
    private func fadeRetired(_ step: Float) {
        guard !retired.isEmpty else { return }
        retired = retired.compactMap { entry in
            let time = entry.time + step, gone = min(1, time / 1.2)
            entry.node.opacity = CGFloat(1 - gone)
            entry.node.simdScale = SIMD3(repeating: entry.size * (1 - 0.45 * gone))
            if gone >= 1 { entry.node.removeFromParentNode(); return nil }
            return (entry.node, time, entry.size)
        }
    }
    /// How many put-down items are still fading, for tests.
    var fading: Int { retired.count }

    private func spawn(_ wanted: PantryCarry.Item) {
        clear()
        guard let template = models[wanted.kind] else { return }
        let node = template.clone()
        node.simdScale = SIMD3(repeating: Self.size(wanted.kind))
        node.name = "pantry-carry"
        self.node = node; item = wanted; placement = .counter
        if !reducedMotion { puff(node, delay: 0.05) }
    }

    private func place(_ next: Placement, parent: SCNNode, position: SIMD3<Float>, orientation: simd_quatf?) {
        guard let node else { return }
        let changed = placement != next || node.parent !== parent
        if placement != next { phase = 0 }
        placement = next
        base = (position, orientation ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        guard changed else { return }
        node.removeFromParentNode()
        parent.addChildNode(node)
    }

    /// A short burst of sparkles in the kind's colour.
    private func puff(_ node: SCNNode, delay: CGFloat = 0) {
        guard let item, let parent = node.parent else { return }
        let burst = SCNParticleSystem()
        burst.loops = false
        burst.birthRate = 260
        burst.emissionDuration = 0.08
        burst.warmupDuration = 0
        burst.particleLifeSpan = 0.55
        burst.particleLifeSpanVariation = 0.2
        burst.particleVelocity = 0.9
        burst.particleVelocityVariation = 0.5
        burst.spreadingAngle = 80
        burst.emittingDirection = SCNVector3(0, 1, 0)
        burst.acceleration = SCNVector3(0, -1.6, 0)
        burst.particleSize = 0.035
        burst.particleSizeVariation = 0.015
        burst.particleImage = Self.dot
        burst.particleColor = Self.color(item.kind)
        burst.particleColorVariation = SCNVector4(0, 0.1, 0.15, 0)
        burst.blendMode = .additive
        let emitter = SCNNode()
        emitter.simdPosition = node.simdPosition + SIMD3(0, 0.35, 0)
        parent.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: delay), .run { $0.addParticleSystem(burst) }, .wait(duration: 1.2), .removeFromParentNode()]))
    }
    private static func color(_ kind: PantryCarry.Kind) -> NSColor {
        switch kind {
        case .skill: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        case .plugin: NSColor(red: 1.0, green: 0.7, blue: 0.25, alpha: 1)
        case .connector, .plan: NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1)
        case .idea: NSColor(red: 1.0, green: 0.88, blue: 0.35, alpha: 1)
        case .board: NSColor(red: 0.55, green: 0.85, blue: 0.4, alpha: 1)
        case .pot: NSColor(red: 1.0, green: 0.55, blue: 0.3, alpha: 1)
        }
    }
    nonisolated(unsafe) private static let dot: NSImage = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
        let gradient = NSGradient(colors: [.white, NSColor.white.withAlphaComponent(0)])
        gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        return true
    }
}
