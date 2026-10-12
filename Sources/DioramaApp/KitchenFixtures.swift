import AppKit
import SceneKit

/// The French wall stations built in Blender (`assets/kitchen`): the Orders pass (`order.glb`),
/// the Prep dresser (`prep.glb`), the Tasting pass (`tasting.glb`), the Pantry (`pantry.glb`,
/// a Provençal garde-manger; clicking it still opens the pantry), the service gong (`bell.glb`,
/// hung from its pivot so it can shiver when struck), and the cabinets joining
/// them (`connectors.glb`). Each is loaded once and cloned per kitchen,
/// standing at its station footprint's centre on the floor. Their worktops are at the kitchen's
/// worktop height with the front strip clear, so chefs set things down exactly as before.
@MainActor enum KitchenFixtures {
    private static var templates: [String: SCNNode?] = [:]

    /// The station's model, or nil when there isn't one (the procedural counter is used then).
    static func make(_ area: KitchenArea) -> SCNNode? {
        guard ["order", "prep", "tasting", "pantry", "bell"].contains(area.id) else { return nil }
        if templates[area.id] == nil {
            let template = (try? GLBStaticMeshes.load(area.id, subdirectory: "KitchenStations"))?[area.id]
            // The pantry appliances' status lights glow (the GLB carries no emission).
            template?.enumerateHierarchy { node, _ in
                for material in node.geometry?.materials ?? [] where material.name == "status_light" {
                    material.emission.contents = NSColor(red: 0.35, green: 1, blue: 0.62, alpha: 1)
                }
            }
            templates[area.id] = template
        }
        guard let template = templates[area.id] ?? nil else { return nil }
        let root = SCNNode()
        root.name = area.id
        root.simdPosition = SIMD3(Float(area.footprint.midX), Float(KitchenLayout.floorTop), Float(area.footprint.midY))
        // Modelled facing the room along +z, against the back wall; turned for a side wall.
        let model = template.clone()
        if area.wall == .right { model.eulerAngles.y = -.pi / 2 }
        if area.wall == .left { model.eulerAngles.y = .pi / 2 }
        root.addChildNode(model)
        if area.id == "bell" { hangGong(model) }
        return root
    }

    /// Moves the gong's meshes (materials `gong_*`) under a node at the `gong_pivot` anchor, so
    /// turning that node swings the gong on its cords.
    private static func hangGong(_ model: SCNNode) {
        guard let anchor = model.childNode(withName: "gong_pivot", recursively: true) else { return }
        let pivot = SCNNode(); pivot.name = gongPivot
        pivot.simdPosition = anchor.simdPosition
        anchor.parent?.addChildNode(pivot)
        var parts: [SCNNode] = []
        model.enumerateHierarchy { node, _ in
            if node.geometry?.materials.contains(where: { $0.name?.hasPrefix("gong_") == true }) == true { parts.append(node) }
        }
        for part in parts {
            let world = part.simdWorldTransform
            pivot.addChildNode(part)
            part.simdWorldTransform = world
        }
    }
    static let gongPivot = "gong pivot"

    /// A struck gong swings back on its cords and settles, ringing.
    static func strike(_ gong: SCNNode) {
        guard let pivot = gong.childNode(withName: gongPivot, recursively: true) else { return }
        pivot.removeAction(forKey: "strike")
        let swings: [CGFloat] = [0.16, -0.11, 0.07, -0.045, 0.025, -0.012, 0] // first away from the mallet
        let steps = swings.enumerated().map { i, angle in
            let move = SCNAction.rotateTo(x: angle, y: 0, z: 0, duration: i == 0 ? 0.12 : 0.34)
            move.timingMode = .easeInEaseOut
            return move
        }
        pivot.runAction(.sequence(steps), forKey: "strike")
    }

    /// The cabinets between the wall stations (`KitchenLayout.connectors`), in kitchen space, or
    /// nil when the model isn't there (the procedural cabinets are used then).
    static func connectors() -> SCNNode? {
        if templates["connectors"] == nil {
            templates["connectors"] = (try? GLBStaticMeshes.load("connectors", subdirectory: "KitchenStations"))?["connectors"]
        }
        guard let template = templates["connectors"] ?? nil else { return nil }
        let node = template.clone()
        node.name = "connecting cabinets"
        node.simdPosition = SIMD3(0, Float(KitchenLayout.floorTop), 0)
        return node
    }
}
