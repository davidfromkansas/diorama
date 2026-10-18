import AppKit
import SceneKit
import simd

/// The startup office at golden hour (see `SceneLayout.office`): the same chefs, a light oak floor,
/// pastel stations, a window wall onto the city and clients waiting in the lobby for deliverables.
@MainActor final class OfficeTheme: SceneTheme {
    static let shared = OfficeTheme()
    let kind = SceneKind.office
    var layout: SceneLayout { SceneLayout.office }
    /// A warm evening haze behind the skyline.
    let backdrop = NSColor(srgbRed: 0.96, green: 0.82, blue: 0.70, alpha: 1)
    let vocabulary = SceneVocabulary(place: "office", supplies: "Supply closet", deliverable: "deliverable")
    let soundFolder = "OfficeSounds"
    var surroundings: (any SceneSurroundings)? { OfficeLobby.shared }
    /// Clients chat, sip coffee and laugh; once served they look the work over with their partner.
    let guestScript = GuestScript(
        chatting: [("sit_talk", 4), ("sit_sip", 2.5), ("sit_gesture", 1.5), ("sit_laugh", 1), ("sit_idle", 1.5)],
        listening: [("sit_idle", 2), ("sit_laugh", 1.5), ("sit_sip", 1.5)],
        enjoy: "sit_gesture", enjoyHand: nil)
    var avatarKit: ChefAvatar.Kit {
        ChefAvatar.Kit(deliverables: OfficeProps.deliverables, carryModels: OfficeProps.carryModels,
                       stationItem: { OfficeProps.stationItem(area: $0) }, workInProgress: false)
    }
    var tableSettings: [String: SCNNode] { OfficeProps.tableSettings }
    func deliverable(for key: String) -> String? {
        KitchenFood.dish(for: key, among: OfficeProps.deliverables.keys.sorted())
    }

    func buildRoom() -> [SCNNode] { OfficeRoomGeometry.make(layout) }
    func buildStation(_ area: SceneArea) -> SCNNode { OfficeStationGeometry.make(area) }
    func makeEffects(world: SCNNode, stations: [String: SCNNode]) -> [any SceneStationEffect] {
        var effects: [any SceneStationEffect] = []
        if let desks = stations["cooking"] { effects.append(DeskScreens(desks: desks, layout: layout)) }
        if let rack = stations["stove"] { effects.append(RackLights(rack: rack, layout: layout)) }
        return effects
    }
    /// Golden hour: a low, warm sun from the left through the window wall, long shadows, and a
    /// cool fill from the lobby side.
    func light(_ world: SCNNode, camera: SCNCamera) {
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient; ambient.light?.intensity = 230
        ambient.light?.color = NSColor(red: 1, green: 0.93, blue: 0.86, alpha: 1)
        world.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight()
        sun.light?.type = .directional; sun.light?.intensity = 1150
        sun.light?.color = NSColor(red: 1, green: 0.84, blue: 0.64, alpha: 1)
        sun.light?.castsShadow = true; sun.light?.shadowRadius = 5
        sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.light?.orthographicScale = 36
        sun.light?.shadowColor = NSColor(red: 0.18, green: 0.10, blue: 0.16, alpha: 0.42)
        sun.position = SCNVector3(-12, 9, -7); sun.look(at: SCNVector3Zero)
        world.addChildNode(sun)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light?.type = .directional; fill.light?.intensity = 260
        fill.light?.color = NSColor(red: 0.78, green: 0.84, blue: 1, alpha: 1)
        fill.position = SCNVector3(9, 6, 9); fill.look(at: SCNVector3Zero)
        world.addChildNode(fill)
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        camera.screenSpaceAmbientOcclusionRadius = 0.4
    }
    /// The desk bell hops and rings.
    func ringNeedsYou(_ fixture: SCNNode) {
        guard let bell = fixture.childNode(withName: "desk bell", recursively: true) else { return }
        bell.removeAction(forKey: "ring")
        let hop = SCNAction.sequence([.moveBy(x: 0, y: 0.07, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.07, z: 0, duration: 0.12)])
        let wobble = SCNAction.sequence([.rotateBy(x: 0, y: 0, z: 0.12, duration: 0.06), .rotateBy(x: 0, y: 0, z: -0.24, duration: 0.1),
                                         .rotateBy(x: 0, y: 0, z: 0.12, duration: 0.08)])
        bell.runAction(.group([hop, wobble]), forKey: "ring")
    }
}

/// Pairs numbered parts of a station (`<prefix>#<i>`) with its slots, nearest along the station.
@MainActor private func slotParts(_ station: SCNNode, prefix: String, slots: [ChefStation]) -> [String: SCNNode] {
    var result: [String: SCNNode] = [:]
    station.enumerateChildNodes { node, _ in
        guard let name = node.name, name.hasPrefix(prefix + "#") else { return }
        let x = Float(node.convertPosition(SCNVector3Zero, to: nil).x)
        guard let slot = slots.min(by: { abs($0.stand.x - x) < abs($1.stand.x - x) }), result[slot.id] == nil else { return }
        result[slot.id] = node
    }
    return result
}

/// A laptop's screen lights up while a chef types at it; its logo glows on the back.
@MainActor final class DeskScreens: SceneStationEffect {
    private(set) var screens: [String: (screen: SCNNode, logo: SCNNode?)] = [:]
    init(desks: SCNNode, layout: SceneLayout) {
        let slots = layout.chefSlots["cooking"] ?? []
        let logos = slotParts(desks, prefix: "desk logo", slots: slots)
        for (id, screen) in slotParts(desks, prefix: "desk screen", slots: slots) {
            screen.geometry = screen.geometry?.copy() as? SCNGeometry
            screen.geometry?.materials = screen.geometry?.materials.compactMap { $0.copy() as? SCNMaterial } ?? []
            let logo = logos[id]
            logo?.geometry = logo?.geometry?.copy() as? SCNGeometry
            logo?.geometry?.materials = logo?.geometry?.materials.compactMap { $0.copy() as? SCNMaterial } ?? []
            screens[id] = (screen, logo)
        }
    }
    /// Desks whose screen is lit now (for tests).
    private(set) var lit: Set<String> = []
    func update(_ chefs: [ChefSnapshot], reduced: Bool) {
        let typing = Set(chefs.compactMap { chef -> String? in
            guard let station = chef.station, station.area == "cooking", simd_distance(chef.position, station.stand) < 0.35 else { return nil }
            return station.id
        })
        guard typing != lit else { return }
        lit = typing
        for (id, parts) in screens {
            let on = typing.contains(id)
            let color = on ? NSColor(srgbRed: 0.72, green: 0.86, blue: 1.0, alpha: 1) : NSColor(srgbRed: 0.16, green: 0.20, blue: 0.28, alpha: 1)
            parts.screen.geometry?.firstMaterial?.diffuse.contents = color
            parts.screen.geometry?.firstMaterial?.emission.contents = color
            parts.logo?.geometry?.firstMaterial?.emission.contents = NSColor(white: on ? 1 : 0.2, alpha: 1)
        }
    }
}

/// A rack's status lights blink while its chef's command runs, and its terminal scrolls green.
@MainActor final class RackLights: SceneStationEffect {
    private(set) var units: [String: (lights: SCNNode, screen: SCNNode?)] = [:]
    init(rack: SCNNode, layout: SceneLayout) {
        let slots = layout.chefSlots["stove"] ?? []
        let screens = slotParts(rack, prefix: "rack screen", slots: slots)
        for (id, lights) in slotParts(rack, prefix: "rack lights", slots: slots) {
            let screen = screens[id]
            screen?.geometry = screen?.geometry?.copy() as? SCNGeometry
            screen?.geometry?.materials = screen?.geometry?.materials.compactMap { $0.copy() as? SCNMaterial } ?? []
            units[id] = (lights, screen)
        }
    }
    /// Units running a command now (for tests).
    private(set) var running: Set<String> = []
    func update(_ chefs: [ChefSnapshot], reduced: Bool) {
        let busy = Set(chefs.compactMap { chef -> String? in
            guard let station = chef.station, station.area == "stove", chef.clip == "waiting_tool" else { return nil }
            return station.id
        })
        guard busy != running else { return }
        running = busy
        for (id, unit) in units {
            let on = busy.contains(id)
            unit.lights.removeAction(forKey: "blink")
            unit.lights.opacity = on ? 1 : 0.55
            if on && !reduced {
                unit.lights.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.35, duration: 0.18), .fadeOpacity(to: 1, duration: 0.22)])), forKey: "blink")
            }
            let color = on ? NSColor(srgbRed: 0.35, green: 0.95, blue: 0.55, alpha: 1) : NSColor(srgbRed: 0.08, green: 0.16, blue: 0.12, alpha: 1)
            unit.screen?.geometry?.firstMaterial?.diffuse.contents = color
            unit.screen?.geometry?.firstMaterial?.emission.contents = color
        }
    }
}
