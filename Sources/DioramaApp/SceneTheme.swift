import AppKit
import SceneKit
import SwiftUI
import simd

/// A seat around the scene where a guest (a restaurant diner, an office client) sits.
struct SceneSeat: Equatable {
    let id: String
    /// Where a seated guest's root stands, and the spot on the table in front of it.
    let stand: SIMD2<Float>
    let dish: SIMD3<Float>
    /// Facing the table (yaw, `x += sin`, `z += cos`, as chefs use).
    var facing: Float { atan2(dish.x - stand.x, dish.z - stand.y) }
}

/// The world around a scene's floor, with seats for guests who receive finished work.
@MainActor protocol SceneSurroundings: AnyObject {
    /// Nearest the serving pass first.
    var seats: [SceneSeat] { get }
    /// A fresh copy for one scene (geometry and materials are shared).
    func make() -> SCNNode
}

/// What guests do between being served: the clips they chat with, and the ones they play when
/// served and while enjoying it.
nonisolated struct GuestScript: Sendable {
    var chatting: [(String, Double)]
    var listening: [(String, Double)]
    var talking: Set<String> = ["sit_talk", "sit_gesture"]
    var cheer = "sit_cheer"
    /// Played after the cheer, until the served work is accepted.
    var enjoy: String
    var enjoyHand: ChefProp?
    static let restaurant = GuestScript(
        chatting: [("sit_talk", 4), ("sit_eat", 3), ("sit_gesture", 1.5), ("sit_sip", 1.5), ("sit_laugh", 1), ("sit_idle", 1)],
        listening: [("sit_idle", 2), ("sit_laugh", 2), ("sit_eat", 3), ("sit_sip", 1)],
        enjoy: "sit_eat", enjoyHand: .spoon)
}

/// Names the interface uses for a scene; panels over the scene read it from the environment.
struct SceneVocabulary {
    /// "kitchen", "office".
    let place: String
    /// The supplies station's card title ("Pantry").
    let supplies: String
    /// What sits on a guest's table once served ("dish", "deliverable").
    let deliverable: String
}
private struct SceneVocabularyKey: EnvironmentKey {
    static let defaultValue = SceneVocabulary(place: "kitchen", supplies: "Pantry", deliverable: "dish")
}
extension EnvironmentValues {
    var sceneVocabulary: SceneVocabulary {
        get { self[SceneVocabularyKey.self] }
        set { self[SceneVocabularyKey.self] = newValue }
    }
}

/// A station's live detail, driven by where chefs stand and what they play (burner flames,
/// idle cutting boards, glowing desk screens).
@MainActor protocol SceneStationEffect: AnyObject {
    func update(_ chefs: [ChefSnapshot], reduced: Bool)
}
/// One chef as station effects see it.
struct ChefSnapshot {
    let station: ChefStation?
    let clip: String
    let position: SIMD2<Float>
    let choppingOnBoard: Bool
}

/// One kind of scene: its floor plan and station table, how it is built and lit, what is carried
/// and served in it, and what it sounds like. The engine (`DioramaSceneView`) runs any theme.
@MainActor protocol SceneTheme: AnyObject {
    var kind: SceneKind { get }
    var layout: SceneLayout { get }
    /// Beyond the scene, also behind panels that fade away while a chef is held.
    var backdrop: NSColor { get }
    var vocabulary: SceneVocabulary { get }
    /// The bundled sound set (`Resources/<folder>/<sound>-<n>.caf`); missing sounds play the kitchen's.
    var soundFolder: String { get }
    var surroundings: (any SceneSurroundings)? { get }
    var guestScript: GuestScript { get }
    /// What chefs carry and serve, and what they fetch at stations.
    var avatarKit: ChefAvatar.Kit { get }
    /// What sits on each guest's table before anything is served, by id.
    var tableSettings: [String: SCNNode] { get }
    /// The deliverable (dish) for a task key; stable across launches.
    func deliverable(for key: String) -> String?
    /// The floor and the room around it.
    func buildRoom() -> [SCNNode]
    /// A station's fixture, named after its area id.
    func buildStation(_ area: SceneArea) -> SCNNode
    func makeEffects(world: SCNNode, stations: [String: SCNNode]) -> [any SceneStationEffect]
    /// Ambient, key and fill lights.
    func light(_ world: SCNNode, camera: SCNCamera)
    /// The needs-you fixture reacts (the gong shivers, the desk bell bounces).
    func ringNeedsYou(_ fixture: SCNNode)
}

enum SceneThemes {
    static func vocabulary(_ kind: SceneKind) -> SceneVocabulary { theme(kind).vocabulary }
    static func theme(_ kind: SceneKind) -> any SceneTheme {
        switch kind {
        case .kitchen: KitchenTheme.shared
        case .office: OfficeTheme.shared
        }
    }
}

// MARK: Kitchen

/// The French kitchen beside a Mediterranean restaurant: the scene Diorama started with.
@MainActor final class KitchenTheme: SceneTheme {
    static let shared = KitchenTheme()
    let kind = SceneKind.kitchen
    var layout: SceneLayout { SceneLayout.kitchen }
    /// A summer sky beyond the canal.
    let backdrop = NSColor(srgbRed: 0.55, green: 0.78, blue: 0.86, alpha: 1)
    let vocabulary = SceneVocabulary(place: "kitchen", supplies: "Pantry", deliverable: "dish")
    let soundFolder = KitchenAudio.kitchenFolder
    var surroundings: (any SceneSurroundings)? { KitchenRestaurant.shared }
    let guestScript = GuestScript.restaurant
    var avatarKit: ChefAvatar.Kit { .kitchen }
    var tableSettings: [String: SCNNode] { KitchenFood.templates }
    func deliverable(for key: String) -> String? { KitchenFood.dish(for: key) }

    func buildRoom() -> [SCNNode] {
        let material = SCNMaterial(); material.diffuse.contents = NSColor(white: 0.71, alpha: 1); material.roughness.contents = 0.9
        let shape = SCNBox(width: KitchenLayout.floor.width, height: 0.2, length: KitchenLayout.floor.height, chamferRadius: min(0.07, 0.2 / 3))
        shape.materials = [material]
        let floor = SCNNode(geometry: shape); floor.name = "Kitchen floor"
        return [floor, KitchenRoomGeometry.make()]
    }
    func buildStation(_ area: SceneArea) -> SCNNode { KitchenStationGeometry.make(area) }
    func makeEffects(world: SCNNode, stations: [String: SCNNode]) -> [any SceneStationEffect] {
        var effects: [any SceneStationEffect] = [BurnerFlames(world: world, layout: layout)]
        if let island = stations["cooking"] { effects.append(IdleBoards(island: island, layout: layout)) }
        return effects
    }
    func light(_ world: SCNNode, camera: SCNCamera) {
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient; ambient.light?.intensity = 180
        ambient.light?.color = NSColor(red: 1, green: 0.97, blue: 0.91, alpha: 1)
        world.addChildNode(ambient)
        let daylight = SCNNode(); daylight.light = SCNLight()
        daylight.light?.type = .directional; daylight.light?.intensity = 1100
        daylight.light?.castsShadow = true; daylight.light?.shadowRadius = 4
        daylight.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        daylight.light?.orthographicScale = 34
        daylight.light?.shadowColor = NSColor(white: 0.08, alpha: 0.48)
        daylight.position = SCNVector3(-8, 12, -5); daylight.look(at: SCNVector3Zero)
        world.addChildNode(daylight)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light?.type = .directional; fill.light?.intensity = 240
        fill.light?.color = NSColor(red: 0.82, green: 0.89, blue: 1, alpha: 1)
        fill.position = SCNVector3(8, 6, 8); fill.look(at: SCNVector3Zero)
        world.addChildNode(fill)
        camera.screenSpaceAmbientOcclusionIntensity = 0.65
        camera.screenSpaceAmbientOcclusionRadius = 0.4
    }
    func ringNeedsYou(_ fixture: SCNNode) { KitchenFixtures.strike(fixture) }
}

/// A burner is lit while a chef works at it (watching its command cook).
@MainActor final class BurnerFlames: SceneStationEffect {
    /// One flame per burner, keyed by the stove slot it belongs to.
    private(set) var flames: [String: (node: SCNNode, fire: SCNParticleSystem)] = [:]
    init(world: SCNNode, layout: SceneLayout) {
        for (index, slot) in (layout.chefSlots["stove"] ?? []).enumerated() {
            // On the range's burner crowns; the old counter's spots if the model didn't load.
            let burner = KitchenStove.shared?.burner(index).map { SCNVector3($0) }
                ?? SCNVector3(slot.stand.x, ChefMetrics.worktopHeight + 0.04, Float(layout.areas.first { $0.id == "stove" }?.footprint.midY ?? 0))
            let flame = Self.flame(); flame.node.position = burner
            world.addChildNode(flame.node); flames[slot.id] = flame
        }
    }
    var lit: Set<String> { Set(flames.filter { !$0.value.node.isHidden }.map(\.key)) }
    func update(_ chefs: [ChefSnapshot], reduced: Bool) {
        let lit = Set(chefs.compactMap { chef -> String? in
            guard let station = chef.station, station.area == "stove", chef.clip == "waiting_tool" else { return nil }
            return station.id
        })
        for (id, flame) in flames {
            let on = lit.contains(id)
            flame.node.isHidden = !on
            flame.fire.birthRate = on && !reduced ? 140 : 0
        }
    }
    private static func flame() -> (node: SCNNode, fire: SCNParticleSystem) {
        let node = SCNNode(); node.name = "burner flame"; node.isHidden = true
        // A steady glow (also shown under reduced motion) plus rising particles.
        let glow = SCNCone(topRadius: 0.02, bottomRadius: 0.17, height: 0.3)
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
        fire.emitterShape = SCNTorus(ringRadius: 0.155, pipeRadius: 0.025)   // the burner crown's flame ports
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
}

/// Per cooking slot: the plain board a chef chops on, and the cleaver-on-board model shown while
/// nobody is there.
@MainActor final class IdleBoards: SceneStationEffect {
    private(set) var boards: [String: (plain: SCNNode, idle: SCNNode)] = [:]
    /// Pairs each plain board on the island with its cooking slot (nearest along the island) and
    /// lays the cleaver model over it, sized to the plain board.
    init(island: SCNNode, layout: SceneLayout) {
        guard let template = KitchenProps.cleaverBoard else { return }
        let slots = layout.chefSlots["cooking"] ?? []
        for plain in island.childNodes where plain.name == "cutting board" {
            let x = Float(island.convertPosition(plain.position, to: nil).x)
            guard let slot = slots.min(by: { abs($0.stand.x - x) < abs($1.stand.x - x) }), boards[slot.id] == nil,
                  let box = plain.geometry as? SCNBox else { continue }
            let idle = template.clone(); idle.name = "idle cutting board"
            // The model is 1.0 wide; the island's height scale is undone so it keeps its proportions.
            let width = box.width, lift = CGFloat(island.scale.y)
            idle.scale = SCNVector3(width, width / lift, width)
            idle.position = SCNVector3(plain.position.x, plain.position.y - box.height / 2, plain.position.z)
            island.addChildNode(idle)
            plain.isHidden = true
            boards[slot.id] = (plain, idle)
        }
    }
    var idle: Set<String> { Set(boards.filter { !$0.value.idle.isHidden }.map(\.key)) }
    /// A board shows the resting cleaver until a chef reaches it.
    func update(_ chefs: [ChefSnapshot], reduced: Bool) {
        guard !boards.isEmpty else { return }
        var busy: Set<String> = [], chopped: Set<String> = []
        for chef in chefs {
            guard let station = chef.station, station.area == "cooking", simd_distance(chef.position, station.stand) < 0.35 else { continue }
            busy.insert(station.id)
            if chef.choppingOnBoard { chopped.insert(station.id) }
        }
        for (id, board) in boards {
            let used = busy.contains(id)
            // A chef chopping on its chopped board needs no plain board under it.
            let plain = used && !chopped.contains(id)
            if board.plain.isHidden != !plain { board.plain.isHidden = !plain }
            if board.idle.isHidden != used { board.idle.isHidden = used }
        }
    }
}
