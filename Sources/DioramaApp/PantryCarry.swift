import AppKit
import DioramaCore
@preconcurrency import SceneKit

/// What a chef fetched from the pantry, carried out in both hands: a salsa jar for a skill, a
/// crate for a plugin, a connector object for an MCP server or app. It sits on the pantry counter
/// while the chef is there, is carried (carry walk) to the next station, set down there and fades.
enum PantryCarry {
    nonisolated enum Kind: String, Sendable { case skill, plugin, connector }
    nonisolated struct Item: Equatable, Sendable {
        let kind: Kind
        let name: String
    }

    /// What the chef is fetching: the current tool call when it's a pantry resource, else the
    /// last resource of the turn (an owed pantry visit replays that one).
    static func item(for agent: WorkspaceAgent) -> Item? {
        if let item = item(tool: agent.latestTool, detail: agent.latestToolDetail) { return item }
        guard let last = agent.turnWork.resources.last, !last.isEmpty else { return nil }
        if last.hasPrefix("skill://") { return item(tool: "read_mcp_resource", detail: last) }
        return last.hasPrefix("mcp__") ? item(tool: last, detail: "") : item(tool: "Skill", detail: last)
    }
    static func item(tool: String, detail: String) -> Item? {
        // A skill read from an installed plugin (…/plugins/cache/<marketplace>/<plugin>/…/SKILL.md)
        // is that plugin's.
        if KitchenActivity.isSkillFile(detail), let plugin = pluginFolder(detail) { return Item(kind: .plugin, name: plugin) }
        guard let resource = LiveResources.resource(tool: tool, detail: detail) else { return nil }
        switch resource.kind {
        case .skill:
            // A skill a plugin brought (fetched from it by MCP resource): its crate.
            if resource.plugin != nil { return Item(kind: .plugin, name: resource.name) }
            // A namespaced skill ("vercel:deploy") comes from its plugin.
            if let colon = resource.name.firstIndex(of: ":"), colon != resource.name.startIndex {
                return Item(kind: .plugin, name: String(resource.name[..<colon]))
            }
            return Item(kind: .skill, name: resource.name)
        case .server:
            if let plugin = resource.plugin { return Item(kind: .plugin, name: plugin) }
            return Item(kind: .connector, name: resource.name)
        }
    }
    static func pluginFolder(_ text: String) -> String? {
        guard let range = text.range(of: "/plugins/cache/") else { return nil }
        let parts = text[range.upperBound...].split(separator: "/")
        return parts.count > 2 ? String(parts[1]) : nil
    }
    /// The models, by kind (`assets/props`: salsa_jar, plugin_crate, connector_object).
    static var models: [Kind: SCNNode] {
        var result: [Kind: SCNNode] = [:]
        for (kind, id) in [(Kind.skill, "salsa_jar"), (.plugin, "plugin_crate"), (.connector, "connector_object")] { result[kind] = KitchenProps.templates[id] }
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
    static let fade: Float = 3.5

    private(set) var placement = Placement.none
    private(set) var item: PantryCarry.Item?
    private(set) var node: SCNNode?
    /// 1 until it's set down, then down to 0 as it fades.
    private(set) var opacity: Float = 1
    private var faded: Float = 0

    /// The director carries it (carry walk) from the pantry until it's set down.
    var carrying: Bool { placement == .counter || placement == .carried }

    // Where it rests in the current placement; the animation plays on top of this.
    private var base = (position: SIMD3<Float>.zero, orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    /// Seconds in the current placement, and overall (for the carry jostle).
    private var phase: Float = 0
    private var clock: Float = 0
    private var landed = false
    private var reducedMotion = false

    /// - Parameters:
    ///   - wanted: what the chef is fetching, from its latest activity.
    ///   - area: the station the chef stands at (nil while walking).
    func sync(wanted: PantryCarry.Item?, area: String?, reducedMotion: Bool, delta: Float,
              carrySocket: SCNNode?, fit: (position: SIMD3<Float>, orientation: simd_quatf)?, floor: SCNNode, counterTop: Float) {
        self.reducedMotion = reducedMotion
        let step = max(0, min(delta, 0.1))
        phase += step; clock += step
        if area == "pantry" {
            // At the pantry with something to fetch: a fresh one pops onto the counter.
            if let wanted, !(carrying && item == wanted) { spawn(wanted) }
            if carrying { place(.counter, parent: floor, position: SIMD3(0, counterTop, 0.5), orientation: nil) }
            animate()
            return
        }
        switch placement {
        case .counter, .carried:
            if area == nil {
                // Walking away: in both hands, on the carry socket like the plate.
                if let carrySocket { place(.carried, parent: carrySocket, position: fit?.position ?? .zero, orientation: fit?.orientation) }
                else { place(.carried, parent: floor, position: SIMD3(0, counterTop * 0.85, 0.32), orientation: nil) }
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
        node.simdScale = scale * Self.size
        node.opacity = CGFloat(opacity)
    }
    static func overshoot(_ p: Float) -> Float {
        // Ease out back: past 1 and settle.
        let c: Float = 2.2, x = p - 1
        return 1 + (c + 1) * x * x * x + c * x * x
    }

    func clear() {
        node?.removeFromParentNode(); node = nil; item = nil; placement = .none; opacity = 1; faded = 0; phase = 0; landed = false
    }

    private func spawn(_ wanted: PantryCarry.Item) {
        clear()
        guard let template = models[wanted.kind] else { return }
        let node = template.clone()
        node.simdScale = SIMD3(repeating: Self.size)
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
        case .connector: NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1)
        }
    }
    nonisolated(unsafe) private static let dot: NSImage = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
        let gradient = NSGradient(colors: [.white, NSColor.white.withAlphaComponent(0)])
        gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        return true
    }
}

/// The name of what's carried, floating over it: a pill in the live bar's colour for its kind,
/// larger than a chef's name tag and wrapping to two lines.
final class PantryCarryTag: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let mark = NSTextField(labelWithString: "✦")
    private var kind: PantryCarry.Kind?
    static let maxWidth: CGFloat = 170

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.alignment = .left
        mark.font = .systemFont(ofSize: 11, weight: .bold)
        addSubview(mark); addSubview(label)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ item: PantryCarry.Item) {
        if label.stringValue != item.name { label.stringValue = item.name; setAccessibilityLabel(item.name) }
        guard kind != item.kind else { return }
        kind = item.kind
        let group: AgentSidebarGroup = item.kind == .skill ? .done : item.kind == .plugin ? .needsYou : .inProgress
        let tint = SidebarStyle.tint(group)
        layer?.backgroundColor = NSColor(tint.band).cgColor
        layer?.borderColor = NSColor(tint.dot).withAlphaComponent(0.45).cgColor
        label.textColor = NSColor(tint.text)
        mark.textColor = NSColor(tint.dot)
        mark.stringValue = item.kind == .skill ? "✦" : item.kind == .plugin ? "▣" : "◉"
    }
    /// Lays the pill out around its text and returns its size.
    func fit() -> CGSize {
        let markSize = mark.intrinsicContentSize
        label.preferredMaxLayoutWidth = Self.maxWidth - markSize.width - 22
        let text = label.sizeThatFits(NSSize(width: label.preferredMaxLayoutWidth, height: 200))
        let size = CGSize(width: ceil(text.width + markSize.width + 22), height: ceil(max(text.height, markSize.height) + 10))
        mark.frame = CGRect(x: 8, y: (size.height - markSize.height) / 2, width: markSize.width, height: markSize.height)
        label.frame = CGRect(x: 8 + markSize.width + 4, y: (size.height - text.height) / 2, width: text.width + 2, height: text.height)
        return size
    }
}

extension KitchenSceneView {
    /// One floating tag per carrier, kept on the main thread.
    private static var pantryTags: [ObjectIdentifier: PantryCarryTag] = [:]

    /// Floats each carried item's name over it; hidden when another chef has the stage.
    func placePantryCarryTags() {
        chefLock.lock()
        let carries = chefs.map { id, chef -> (String, ObjectIdentifier, PantryCarry.Item?, Float, SIMD3<Float>?) in
            let carrier = chef.pantryCarry
            let position = carrier.node.flatMap { $0.parent == nil ? nil : $0.simdWorldPosition }
            return (id, ObjectIdentifier(carrier), carrier.item, carrier.opacity, position)
        }
        chefLock.unlock()
        let here = Set(carries.map(\.1))
        // Chefs that left this kitchen take their tags with them.
        for (key, tag) in Self.pantryTags where tag.superview === self && !here.contains(key) {
            tag.removeFromSuperview(); Self.pantryTags[key] = nil
        }
        for (id, key, item, opacity, position) in carries {
            guard let item, let position, selectedID == nil || selectedID == id,
                  let point = projectWithoutLock(position + SIMD3(0, 0.85 * KitchenLayout.chefScale, 0)) else {
                Self.pantryTags[key]?.isHidden = true; continue
            }
            let tag = Self.pantryTags[key] ?? PantryCarryTag()
            Self.pantryTags[key] = tag
            if tag.superview !== self { addSubview(tag) }
            tag.show(item)
            let size = tag.fit()
            let y = isFlipped ? bounds.height - point.y : point.y
            tag.frame = CGRect(x: point.x - size.width / 2, y: isFlipped ? y - size.height : y, width: size.width, height: size.height)
            tag.alphaValue = CGFloat(opacity)
            tag.isHidden = false
        }
    }
}
