import SceneKit
import SwiftUI

enum WorkspaceSceneKind: String, CaseIterable { case office = "Office", kitchen = "Kitchen" }

/// Which side of a station the chefs work from; fixtures face the room accordingly.
enum KitchenWall { case back, left, right, front, island, freestanding }

struct KitchenArea: Identifiable {
    let id: String
    let label: String
    let short: String
    let footprint: CGRect // X/Z coordinates on the floor.
    let wall: KitchenWall
    /// Agreed number of chefs working here at once; more queue behind.
    let spots: Int
    let accent: NSColor
    var center: SCNVector3 { SCNVector3(footprint.midX, 0.6, footprint.midY) }
}
/// The kitchen follows an agent's journey: elevator → order rail → prep → cooking (cutting
/// boards for editing, burners for commands) → tasting → serving window, with the service bell in the middle
/// and the break room for finished chefs. Sized for 10 agents in parallel.
enum KitchenLayout {
    static let floor = CGRect(x: -12, y: -8, width: 24, height: 16)
    /// Cabinets that close the gaps between wall stations.
    static let connectors: [CGRect] = [
        .init(x: -9.2, y: -7.8, width: 0.8, height: 1.2),
        .init(x: -3.6, y: -7.8, width: 2.4, height: 1.2),
        .init(x: 8.0, y: -7.8, width: 3.8, height: 1.2),
        .init(x: -11.8, y: -5.8, width: 1.2, height: 8.9),
        .init(x: 10.6, y: -6.6, width: 1.2, height: 2.2),
        .init(x: 10.6, y: 0.4, width: 1.2, height: 7.2)
    ]
    static let areas: [KitchenArea] = [
        .init(id: "elevator", label: "Elevator: new agents arrive", short: "Elevator", footprint: .init(x: -11.6, y: -7.8, width: 2.4, height: 2.0), wall: .freestanding, spots: 1, accent: .init(red: 0.55, green: 0.52, blue: 0.68, alpha: 1)),
        .init(id: "order", label: "Order rail: read the request", short: "Orders", footprint: .init(x: -8.4, y: -7.8, width: 4.8, height: 1.2), wall: .back, spots: 3, accent: .init(red: 0.56, green: 0.67, blue: 0.61, alpha: 1)),
        .init(id: "prep", label: "Prep: planning and research", short: "Prep", footprint: .init(x: -1.2, y: -7.8, width: 9.2, height: 1.2), wall: .back, spots: 6, accent: .init(red: 0.56, green: 0.67, blue: 0.61, alpha: 1)),
        // Two long islands, each worked from the far side so chefs face the camera: one
        // cutting board or burner per chef.
        .init(id: "cooking", label: "Cooking island: editing code", short: "Cooking", footprint: .init(x: -4.5, y: -2.8, width: 9.0, height: 1.2), wall: .front, spots: 6, accent: .init(red: 0.57, green: 0.64, blue: 0.72, alpha: 1)),
        .init(id: "stove", label: "Stove island: running commands", short: "Stove", footprint: .init(x: -4.5, y: 0.6, width: 9.0, height: 1.2), wall: .front, spots: 6, accent: .init(red: 0.69, green: 0.59, blue: 0.47, alpha: 1)),
        .init(id: "tasting", label: "Tasting: tests and QA", short: "Tasting", footprint: .init(x: 10.6, y: -4.4, width: 1.2, height: 4.8), wall: .right, spots: 3, accent: .init(red: 0.64, green: 0.59, blue: 0.72, alpha: 1)),
        .init(id: "bell", label: "Service bell: needs you", short: "Needs you", footprint: .init(x: -0.5, y: 4.0, width: 1.0, height: 1.0), wall: .freestanding, spots: 6, accent: .init(red: 0.75, green: 0.58, blue: 0.47, alpha: 1)),
        .init(id: "serving", label: "Serving window: ready for review", short: "Serving", footprint: .init(x: 3.2, y: 6.4, width: 7.4, height: 1.2), wall: .front, spots: 5, accent: .init(red: 0.51, green: 0.67, blue: 0.66, alpha: 1)),
        .init(id: "break", label: "Break room: finished agents", short: "Break room", footprint: .init(x: -11.0, y: 5.4, width: 6.6, height: 1.0), wall: .island, spots: 10, accent: .init(red: 0.55, green: 0.52, blue: 0.68, alpha: 1))
    ]
    /// Low partial walls enclosing the break room, with a doorway toward the kitchen.
    static let breakRoomWalls: [CGRect] = [
        .init(x: -12, y: 3.125, width: 6.6, height: 0.15),
        .init(x: -3.475, y: 3.125, width: 0.15, height: 4.875)
    ]
    /// The elevator car's side and back walls; its interior and doorway stay walkable.
    static let elevatorWalls: [CGRect] = [
        .init(x: -11.6, y: -7.8, width: 0.12, height: 2.0),
        .init(x: -9.32, y: -7.8, width: 0.12, height: 2.0)
    ]
}
struct KitchenSceneSurface: NSViewRepresentable {
    var agents: [SpatialAgent] = []
    /// The project (or conversation) on screen, so even an empty one counts as already shown.
    var scope: String? = nil
    /// Review state per conversation (see `KitchenReviews`).
    var reviews: [String: KitchenReviews.State] = [:]
    var active = false
    var reducedMotion = false
    var select: (SpatialFocus) -> Void = { _ in }
    /// Clicking a chef waiting at the serving window opens the review panel instead.
    var review: ((SpatialAgent) -> Void)? = nil
    func makeNSView(context: Context) -> KitchenSceneView { KitchenSceneView() }
    func updateNSView(_ view: KitchenSceneView, context: Context) {
        view.select = select
        view.review = review
        view.reviews = reviews
        view.apply(agents: agents, scope: scope, active: active, reducedMotion: reducedMotion)
        view.fitFloor()
    }
    static func dismantleNSView(_ view: KitchenSceneView, coordinator: ()) { view.tearDown() }
}
@MainActor private final class KitchenFrameDriver: NSObject {
    weak var view: KitchenSceneView?
    @objc func frame(_ link: CADisplayLink) { view?.frameStep(at: link.targetTimestamp) }
}
private final class KitchenLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Kitchen workspace: the focused project's agents appear as chefs working at the station that
/// matches their state. It only observes agent state; it never controls provider execution.
final class KitchenSceneView: SCNView {
    static let maxChefs = 12
    let floorSize = SIMD3<Float>(Float(KitchenLayout.floor.width), 0.2, Float(KitchenLayout.floor.height))
    var select: ((SpatialFocus) -> Void)?
    var review: ((SpatialAgent) -> Void)?
    var reviews: [String: KitchenReviews.State] = [:]
    private(set) var chefs: [String: ChefAvatar] = [:]
    private var chefAgents: [String: SpatialAgent] = [:]
    private var chefLabels: [String: NSTextField] = [:]
    private var slots: [String: ChefStation] = [:]
    private let navigation = KitchenLayout.chefNavigation
    private var active = false
    private var reduced = false
    private var frameLink: CADisplayLink?
    private var frameDriver: KitchenFrameDriver?
    private var lastFrame: TimeInterval?
    private var windowObservers: [NSObjectProtocol] = []
    private var labels: [NSTextField] = []
    /// One flame per burner, keyed by the stove slot it belongs to.
    private var flames: [String: (node: SCNNode, fire: SCNParticleSystem)] = [:]
    private let leaders = CAShapeLayer()
    private var fittedSize = CGSize.zero
    var labelFrames: [CGRect] { labels.map(\.frame) }
    override init(frame: NSRect = .zero, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        let world = SCNScene()
        world.background.contents = NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.92, alpha: 1)
        func material(_ color: NSColor) -> SCNMaterial {
            let value = SCNMaterial(); value.diffuse.contents = color; value.roughness.contents = 0.9; return value
        }
        func box(_ name: String, width: CGFloat, height: CGFloat, depth: CGFloat, at position: SCNVector3, material: SCNMaterial) -> SCNNode {
            let shape = SCNBox(width: width, height: height, length: depth, chamferRadius: min(0.07, height / 3))
            shape.materials = [material]
            let node = SCNNode(geometry: shape); node.name = name; node.position = position
            world.rootNode.addChildNode(node); return node
        }
        _ = box("Kitchen floor", width: KitchenLayout.floor.width, height: 0.2, depth: KitchenLayout.floor.height, at: SCNVector3Zero, material: material(.init(white: 0.71, alpha: 1)))
        world.rootNode.addChildNode(KitchenRoomGeometry.make())
        for slot in KitchenLayout.chefSlots["stove"] ?? [] {
            let burner = SCNVector3(slot.stand.x, KitchenLayout.worktopHeight + 0.04, Float(KitchenLayout.areas.first { $0.id == "stove" }?.footprint.midY ?? 0))
            let flame = Self.flame(); flame.node.position = burner
            world.rootNode.addChildNode(flame.node); flames[slot.id] = flame
        }
        for area in KitchenLayout.areas {
            world.rootNode.addChildNode(KitchenStationGeometry.make(area))
            let label = KitchenLabel(labelWithString: area.short)
            label.toolTip = area.label; label.setAccessibilityLabel(area.label)
            label.font = .systemFont(ofSize: 11, weight: .medium); label.textColor = .init(white: 0.18, alpha: 1)
            label.alignment = .center; label.maximumNumberOfLines = 3; label.lineBreakMode = .byWordWrapping
            label.wantsLayer = true; label.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
            label.layer?.cornerRadius = 5
            labels.append(label); addSubview(label)
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = false
        camera.camera?.projectionDirection = .vertical
        camera.camera?.fieldOfView = 38; camera.camera?.zNear = 0.1; camera.camera?.zFar = 200
        // Overcooked-style framing: elevated front view with screen-aligned aisles.
        let elevation = 62.0 * Double.pi / 180, yaw = 0.0
        camera.position = SCNVector3(30 * cos(elevation) * sin(yaw), 30 * sin(elevation), 30 * cos(elevation) * cos(yaw))
        camera.look(at: SCNVector3(0, 0.65, 0)); world.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient; ambient.light?.intensity = 180
        ambient.light?.color = NSColor(red: 1, green: 0.97, blue: 0.91, alpha: 1)
        world.rootNode.addChildNode(ambient)
        let daylight = SCNNode(); daylight.light = SCNLight()
        daylight.light?.type = .directional; daylight.light?.intensity = 1100
        daylight.light?.castsShadow = true; daylight.light?.shadowRadius = 4
        daylight.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        daylight.light?.orthographicScale = 22
        daylight.light?.shadowColor = NSColor(white: 0.08, alpha: 0.48)
        daylight.position = SCNVector3(-8, 12, -5); daylight.look(at: SCNVector3Zero)
        world.rootNode.addChildNode(daylight)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light?.type = .directional; fill.light?.intensity = 240
        fill.light?.color = NSColor(red: 0.82, green: 0.89, blue: 1, alpha: 1)
        fill.position = SCNVector3(8, 6, 8); fill.look(at: SCNVector3Zero)
        world.rootNode.addChildNode(fill)
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.65
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.4
        scene = world; pointOfView = camera; autoenablesDefaultLighting = false
        delegate = self
        allowsCameraControl = false; isPlaying = false; rendersContinuously = false
        wantsLayer = true; leaders.strokeColor = NSColor.darkGray.withAlphaComponent(0.25).cgColor
        leaders.fillColor = nil; leaders.lineWidth = 1; layer?.addSublayer(leaders)
        setAccessibilityLabel("Kitchen layout. " + KitchenLayout.areas.map(\.label).joined(separator: ", ") + ".")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); fitFloor() }

    // MARK: Chefs

    /// Per-chef pacing: the latest wanted intent, when the chef arrived where it stands, and
    /// whether it is still reading its order after arriving by elevator.
    private struct Pacing { var desired: ChefIntent; var arrivedAt: Double?; var arriving = false }
    private var pacing: [String: Pacing] = [:]
    /// Chefs are stepped on SceneKit's render thread (`renderer(_:updateAtTime:)`) so their
    /// animation never waits for the main thread; main-thread steering takes the same lock.
    nonisolated let chefLock = NSRecursiveLock()
    nonisolated(unsafe) private var renderChefs: [ChefAvatar] = []
    nonisolated(unsafe) private var lastRenderTime: TimeInterval?
    private func publishChefs() { chefLock.lock(); renderChefs = Array(chefs.values); chefLock.unlock() }
    /// Projects (or standalone conversations) already shown here: only agents that start while
    /// their project is on screen ride the elevator in; everything else appears in place.
    private var seenScopes: Set<String> = []

    /// Reconcile chefs with agents: attention first, then working, capped at `maxChefs`.
    func apply(agents: [SpatialAgent], scope: String? = nil, active: Bool, reducedMotion: Bool, now: Double = CACurrentMediaTime()) {
        chefLock.lock(); defer { chefLock.unlock(); publishChefs() }
        let applyStart = CACurrentMediaTime()
        defer { if CACurrentMediaTime() - applyStart > 0.02 { Self.trace(String(format: "slow apply %.0f ms", (CACurrentMediaTime() - applyStart) * 1000)) } }
        if active != self.active { Self.trace("active -> \(active)") }
        self.active = active; reduced = reducedMotion
        defer { if let scope { seenScopes.insert(scope) } }
        let ranked = agents.enumerated().sorted { a, b in
            let ra = a.element.needsAttention ? 0 : a.element.value.status == .working ? 1 : 2
            let rb = b.element.needsAttention ? 0 : b.element.value.status == .working ? 1 : 2
            return ra != rb ? ra < rb : a.offset < b.offset
        }.prefix(Self.maxChefs).map(\.element)
        let ids = Set(ranked.map(\.id))
        for id in chefs.keys where !ids.contains(id) {
            chefs.removeValue(forKey: id)?.root.removeFromParentNode()
            chefLabels.removeValue(forKey: id)?.removeFromSuperview()
            chefAgents[id] = nil; slots[id] = nil; pacing[id] = nil
        }
        guard !ranked.isEmpty, case let .success(assets) = ChefAssets.shared, let world = scene else { updatePlayback(); return }
        let table = KitchenLayout.chefSlots, pickup = table["cooking"]?.first
        let arriving = ranked.filter { chefs[$0.id] == nil && seenScopes.contains($0.projectID ?? $0.conversationID) && [.live, .recentlyObserved].contains($0.value.freshness) }.map(\.id)
        slots = KitchenLayout.assignSlots(ranked.map { agent in
            (agent.id, pacing[agent.id]?.arriving == true || arriving.contains(agent.id) ? "order" : KitchenLayout.work(for: agent.value, review: reviews[agent.conversationID]).area)
        }, previous: slots)
        for agent in ranked {
            chefAgents[agent.id] = agent
            let desired = KitchenLayout.intent(for: agent.value, at: slots[agent.id], pickup: pickup, restored: false, review: reviews[agent.conversationID])
            if chefs[agent.id] == nil {
                let chef = ChefAvatar(id: agent.id, assets: assets, scale: KitchenLayout.chefScale, navigation: navigation)
                chef.director.reducedMotion = reduced
                if arriving.contains(agent.id), let door = table["elevator"]?.first, let order = slots[agent.id] {
                    // A new agent joins: it rides the elevator in and reads its order first.
                    chef.director.place(door.stand, heading: door.facing)
                    chef.director.setIntent(KitchenLayout.arrivalIntent(at: order))
                    pacing[agent.id] = Pacing(desired: desired, arriving: true)
                    openElevator()
                } else {
                    // Chefs shown from history start in place: no walk-in, no replayed gesture.
                    let home = table["break"] ?? []
                    let spawn = slots[agent.id] ?? (home.isEmpty ? nil : home[chefs.count % home.count])
                    if let spawn { chef.director.place(spawn.stand, heading: spawn.facing) }
                    chef.director.setIntent(KitchenLayout.intent(for: agent.value, at: slots[agent.id], pickup: pickup, restored: true, review: reviews[agent.conversationID]))
                    pacing[agent.id] = Pacing(desired: chef.director.intent ?? desired)
                }
                chef.update(0)
                world.rootNode.addChildNode(chef.root); chefs[agent.id] = chef
                let label = KitchenLabel(labelWithString: "")
                label.font = .systemFont(ofSize: 10, weight: .semibold); label.alignment = .center
                label.wantsLayer = true; label.layer?.cornerRadius = 4
                label.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
                chefLabels[agent.id] = label; addSubview(label)
            } else {
                chefs[agent.id]?.director.reducedMotion = reduced
                pacing[agent.id]?.desired = desired
            }
            // The label always shows the live action, even while the chef stays put.
            let doing = agent.value.status == .working && !agent.value.latestActivity.isEmpty ? agent.value.latestActivity : agent.value.statusLabel
            let label = chefLabels[agent.id]
            label?.stringValue = agent.value.name + " · " + (doing.count > 48 ? String(doing.prefix(47)) + "…" : doing)
            label?.textColor = agent.needsAttention ? .systemOrange : .init(white: 0.2, alpha: 1)
        }
        seenScopes.formUnion(ranked.map { $0.projectID ?? $0.conversationID })
        pace(now: now)
        updateFlames()
        placeChefLabels()
        updatePlayback()
        needsDisplay = true
    }
    /// Applies wanted intents: urgent ones at once, others after the chef has worked at its
    /// station for `minimumDwell` (or read its order for `orderReading` after arriving).
    func pace(now: Double) {
        for (id, chef) in chefs {
            guard var state = pacing[id] else { continue }
            let director = chef.director
            if director.station != nil, state.arrivedAt == nil { state.arrivedAt = now }
            let settledFor = state.arrivedAt.map { now - $0 } ?? 0
            var apply = false
            if state.arriving {
                apply = state.arrivedAt != nil && settledFor >= KitchenLayout.orderReading
                if apply, let agent = chefAgents[id] {
                    // Done reading: claim a place at the station its work calls for.
                    state.arriving = false; pacing[id]?.arriving = false
                    slots = KitchenLayout.assignSlots(chefAgents.values.map { a in
                        (a.id, pacing[a.id]?.arriving == true ? "order" : KitchenLayout.work(for: a.value, review: reviews[a.conversationID]).area)
                    }.sorted { $0.0 < $1.0 }, previous: slots)
                    state.desired = KitchenLayout.intent(for: agent.value, at: slots[id], pickup: KitchenLayout.chefSlots["cooking"]?.first, restored: false, review: reviews[agent.conversationID])
                }
            } else if state.desired.key != director.intent?.key {
                // Redirect at once when urgent, while still walking, or after the minimum stay.
                apply = state.desired.urgent || director.intent?.station == nil || director.station == nil || settledFor >= KitchenLayout.minimumDwell
            }
            if apply {
                var next = state.desired
                // Work that leaves the serving window for the break room was accepted: celebrate.
                if next.station?.area == "break", director.intent?.station?.area == "serving" { next.prelude = "celebrate_done" }
                director.setIntent(next)
                state.arrivedAt = nil
            }
            pacing[id] = state
        }
    }
    /// A burner is lit while a chef works at it (watching its command cook).
    func updateFlames() {
        let lit = Set(chefs.values.compactMap { chef -> String? in
            guard let station = chef.director.station, station.area == "stove", chef.director.clip.name == "waiting_tool" else { return nil }
            return station.id
        })
        for (id, flame) in flames {
            let on = lit.contains(id)
            flame.node.isHidden = !on
            flame.fire.birthRate = on && !reduced ? 140 : 0
        }
    }
    var litBurners: Set<String> { Set(flames.filter { !$0.value.node.isHidden }.map(\.key)) }
    private static func flame() -> (node: SCNNode, fire: SCNParticleSystem) {
        let node = SCNNode(); node.name = "burner flame"; node.isHidden = true
        // A steady glow (also shown under reduced motion) plus rising particles.
        let glow = SCNCone(topRadius: 0.02, bottomRadius: 0.2, height: 0.32)
        let hot = SCNMaterial(); hot.lightingModel = .constant; hot.diffuse.contents = NSColor(red: 1, green: 0.55, blue: 0.12, alpha: 0.85)
        hot.emission.contents = NSColor(red: 1, green: 0.45, blue: 0.1, alpha: 1); hot.blendMode = .add; hot.writesToDepthBuffer = false
        glow.materials = [hot]
        let cone = SCNNode(geometry: glow); cone.position.y = 0.16; node.addChildNode(cone)
        let fire = SCNParticleSystem()
        fire.birthRate = 0
        fire.particleLifeSpan = 0.45; fire.particleLifeSpanVariation = 0.15
        fire.particleSize = 0.11; fire.particleSizeVariation = 0.04
        fire.particleVelocity = 0.9; fire.particleVelocityVariation = 0.3
        fire.emittingDirection = SCNVector3(0, 1, 0); fire.spreadingAngle = 18
        fire.emitterShape = SCNTorus(ringRadius: 0.17, pipeRadius: 0.03)
        fire.particleColor = NSColor(red: 1, green: 0.52, blue: 0.12, alpha: 1); fire.particleColorVariation = SCNVector4(0.04, 0.1, 0, 0)
        fire.blendMode = .additive; fire.isLightingEnabled = false; fire.isAffectedByGravity = false
        fire.particleImage = flameSprite
        let fade = CAKeyframeAnimation(); fade.values = [0.0, 1.0, 0.6, 0.0]; fade.keyTimes = [0, 0.15, 0.6, 1]
        let shrink = CAKeyframeAnimation(); shrink.values = [1.0, 0.8, 0.2]; shrink.keyTimes = [0, 0.5, 1]
        fire.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade), .size: SCNParticlePropertyController(animation: shrink)]
        node.addParticleSystem(fire)
        return (node, fire)
    }
    private static let flameSprite: NSImage = {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSGradient(colors: [.white, NSColor(white: 1, alpha: 0)])?.draw(in: NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 64, height: 64)), relativeCenterPosition: .zero)
        image.unlockFocus()
        return image
    }()
    private var pacingPending: Bool {
        pacing.contains { id, state in state.arriving || state.desired.key != chefs[id]?.director.intent?.key }
    }
    private func openElevator() {
        guard let car = scene?.rootNode.childNode(withName: "elevator", recursively: false) else { return }
        let width = CGFloat(KitchenLayout.areas.first { $0.id == "elevator" }?.footprint.width ?? 2.4)
        for (name, direction) in [("elevator door left", -1.0), ("elevator door right", 1.0)] {
            guard let door = car.childNode(withName: name, recursively: false), door.action(forKey: "doors") == nil else { continue }
            let slide = CGFloat(direction) * (width / 2 - 0.2)
            door.runAction(.sequence([.moveBy(x: slide, y: 0, z: 0, duration: 0.6), .wait(duration: 2.4), .moveBy(x: -slide, y: 0, z: 0, duration: 0.6)]), forKey: "doors")
        }
    }
    /// Diagnostics: when /tmp/diorama-kitchen-frames.log exists, frame gaps over 50 ms, slow
    /// reconciles and playback pauses are appended to it.
    nonisolated(unsafe) private static let frameLog: FileHandle? = FileHandle(forWritingAtPath: "/tmp/diorama-kitchen-frames.log")
    nonisolated static func trace(_ text: @autoclosure () -> String) {
        guard let log = frameLog else { return }
        log.seekToEndOfFile(); log.write(Data((String(format: "%.3f ", CACurrentMediaTime()) + text() + "\n").utf8))
    }
    func frameStep(at time: TimeInterval) {
        if let last = lastFrame, time - last > 0.05 { Self.trace(String(format: "gap %.0f ms", (time - last) * 1000)) }
        let stepStart = CACurrentMediaTime()
        defer { if CACurrentMediaTime() - stepStart > 0.02 { Self.trace(String(format: "slow frameStep %.0f ms", (CACurrentMediaTime() - stepStart) * 1000)) } }
        let delta = lastFrame.map { Float(min(0.05, max(0, time - $0))) } ?? 0
        lastFrame = time
        _ = delta // chefs advance on the render thread; this loop only paces and places tags
        chefLock.lock(); defer { chefLock.unlock() }
        pace(now: CACurrentMediaTime())
        updateFlames()
        placeChefLabels()
        updatePlayback()
    }
    private var effectiveActive: Bool { active && (window == nil || window?.occlusionState.contains(.visible) == true) }
    func updatePlayback() {
        chefLock.lock(); defer { chefLock.unlock() }
        let moving = effectiveActive && (chefs.values.contains(where: \.animating) || pacingPending)
        if isPlaying != moving { isPlaying = moving }
        if rendersContinuously != moving { rendersContinuously = moving }
        if frameLink?.isPaused != !moving {
            Self.trace("playback \(moving ? "running" : "paused") active=\(active) window=\(window?.occlusionState.contains(.visible) ?? false)")
            frameLink?.isPaused = !moving
        }
        if !moving { lastFrame = nil }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        guard let window else { return }
        let driver = KitchenFrameDriver(); driver.view = self; frameDriver = driver
        let link = displayLink(target: driver, selector: #selector(KitchenFrameDriver.frame(_:)))
        link.add(to: .main, forMode: .common); frameLink = link
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlayback() }
        })
        updatePlayback()
    }
    func tearDown() {
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        scene = nil
    }
    /// Projects a world point to view coordinates (origin bottom-left, like `projectPoint`) with
    /// the camera's matrices. `projectPoint` takes SceneKit's scene lock and waits for the
    /// renderer, which stalled every animation frame when used for per-frame name tags.
    func projectWithoutLock(_ point: SIMD3<Float>) -> CGPoint? {
        guard let eye = pointOfView, let camera = eye.camera, bounds.width > 0, bounds.height > 0 else { return nil }
        let projection = simd_float4x4(camera.projectionTransform(withViewportSize: bounds.size))
        let clip = projection * eye.simdWorldTransform.inverse * SIMD4(point, 1)
        guard clip.w > 0.0001 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return CGPoint(x: CGFloat(ndc.x + 1) / 2 * bounds.width, y: CGFloat(ndc.y + 1) / 2 * bounds.height)
    }
    private func placeChefLabels() {
        var placed: [CGRect] = []
        for (id, chef) in chefs.sorted(by: { $0.key < $1.key }) {
            guard let label = chefLabels[id] else { continue }
            let head = chef.root.simdPosition + SIMD3(0, 2.05 * KitchenLayout.chefScale, 0)
            guard let point = projectWithoutLock(head) else { label.isHidden = true; continue }
            label.isHidden = false
            let size = label.attributedStringValue.size()
            let width = min(160, size.width + 12), height = size.height + 4
            let y = isFlipped ? bounds.height - CGFloat(point.y) : CGFloat(point.y)
            // Keep name tags fully inside the view near the walls.
            let x = min(max(4, CGFloat(point.x) - width / 2), max(4, bounds.width - width - 4))
            var frame = CGRect(x: x, y: min(max(4, y), max(4, bounds.height - height - 4)), width: width, height: height)
            // Neighbouring chefs (e.g. side by side in the break room) stack their tags instead of overlapping.
            while let clash = placed.first(where: { $0.insetBy(dx: -2, dy: -1).intersects(frame) }) {
                frame.origin.y = isFlipped ? clash.maxY + 2 : clash.minY - height - 2
            }
            placed.append(frame)
            label.frame = frame
        }
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("agent:"), let agent = chefAgents[String(name.dropFirst(6))] {
                    chefLock.lock(); let serving = chefs[agent.id]?.director.intent?.station?.area == "serving"; chefLock.unlock()
                    if let review, serving { review(agent); return }
                    select?(.agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true))
                    return
                }
                node = current.parent
            }
        }
        super.mouseUp(with: event)
    }
    var floorCorners: [SCNVector3] {
        var result: [SCNVector3] = []
        let signs: [Float] = [-1, 1]
        let half = SIMD2(Float(KitchenLayout.floor.width / 2), Float(KitchenLayout.floor.height / 2))
        for x in signs { for y in signs { for z in signs { result.append(SCNVector3(x * half.x, y * 0.1, z * half.y)) } } }
        return result
    }
    var framingPoints: [SCNVector3] {
        var points: [SCNVector3] = []
        for name in KitchenLayout.areas.map(\.id) {
            guard let node = scene?.rootNode.childNode(withName: name, recursively: false) else { continue }
            let (low, high) = node.boundingBox
            for x in [low.x, high.x] { for y in [low.y, high.y] { for z in [low.z, high.z] {
                points.append(node.convertPosition(SCNVector3(x, y, z), to: nil))
            } } }
        }
        return points
    }
    func fitFloor() {
        guard bounds.width > 1, bounds.height > 1, let camera = pointOfView else { return }
        guard fittedSize != bounds.size else { placeLabels(); return }
        fittedSize = bounds.size
        let points = framingPoints
        let elevation = 62.0 * Double.pi / 180
        let target = SCNVector3(0, 0.65, 0)
        func position(_ distance: Double) {
            camera.position = SCNVector3(0, 0.65 + distance * sin(elevation), distance * cos(elevation))
            camera.look(at: target)
        }
        // Fit the usable stations, not the decorative room envelope. Perspective
        // keeps the foreground substantial; only the outer scenery may crop.
        let tangentY = tan(19.0 * Double.pi / 180)
        let tangentX = tangentY * Double(bounds.width / bounds.height)
        let availableX = max(0.1, 1 - 20 / Double(bounds.width))
        let availableY = max(0.1, 1 - 56 / Double(bounds.height))
        // Solve in camera space; SceneKit's presentation projection can lag
        // node mutations until rendering and cannot drive an iterative fit.
        let distance = points.reduce(5.0) { distance, point in
            let y = Double(point.y) - 0.65, z = Double(point.z)
            let cameraY = y * cos(elevation) - z * sin(elevation)
            let towardCamera = y * sin(elevation) + z * cos(elevation)
            return max(distance,
                       towardCamera + abs(Double(point.x)) / (tangentX * availableX),
                       towardCamera + abs(cameraY) / (tangentY * availableY))
        }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        position(distance)
        SCNTransaction.commit()
        SCNTransaction.flush()
        placeLabels(); needsDisplay = true
    }
    private func placeLabels() {
        var occupied: [CGRect] = []
        let path = CGMutablePath()
        for (index, area) in KitchenLayout.areas.enumerated() {
            let point = projectPoint(SCNVector3(area.footprint.midX, 2.6, area.footprint.minY))
            let anchor = CGPoint(x: CGFloat(point.x), y: isFlipped ? bounds.height - CGFloat(point.y) : CGFloat(point.y))
            let width: CGFloat = min(110, labels[index].attributedStringValue.size().width + 14)
            let size = labels[index].cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width - 8, height: 100)) ?? CGSize(width: width, height: 32)
            let height = max(20, size.height + 4)
            func candidate(_ offset: CGFloat) -> CGRect {
                CGRect(x: min(max(8, anchor.x - width / 2), max(8, bounds.width - width - 8)),
                       y: min(max(8, anchor.y + offset - height / 2), max(8, bounds.height - height - 8)), width: width, height: height)
            }
            var frame = candidate(0)
            for step in 0..<20 {
                let offset = CGFloat((step + 1) / 2) * (height + 6) * (step % 2 == 0 ? -1 : 1)
                let proposed = candidate(offset)
                if !occupied.contains(where: { $0.insetBy(dx: -4, dy: -4).intersects(proposed) }) { frame = proposed; break }
            }
            labels[index].frame = frame; occupied.append(frame)
            path.move(to: anchor); path.addLine(to: CGPoint(x: frame.midX, y: frame.midY))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        leaders.frame = bounds; leaders.path = path
        CATransaction.commit()
    }
}

extension KitchenSceneView: SCNSceneRendererDelegate {
    /// Runs on SceneKit's render thread every rendered frame, independent of main-thread work.
    nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        chefLock.lock(); defer { chefLock.unlock() }
        if let last = lastRenderTime, time - last > 0.05 { Self.trace(String(format: "render gap %.0f ms", (time - last) * 1000)) }
        let delta = lastRenderTime.map { Float(min(0.1, max(0, time - $0))) } ?? 0
        lastRenderTime = time
        for chef in renderChefs { chef.update(delta) }
    }
}
