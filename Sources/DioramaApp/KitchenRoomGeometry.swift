import AppKit
import SceneKit

/// Quiet architectural framing; the front remains open and the circulation area stays clear.
@MainActor enum KitchenRoomGeometry {
    static func make() -> SCNNode {
        let root = SCNNode(); root.name = "kitchen-room"
        func material(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = color; m.roughness.contents = 0.85
            m.lightingModel = .physicallyBased; return m
        }
        let plaster = material(NSColor(red: 0.63, green: 0.65, blue: 0.55, alpha: 1))
        let trim = material(NSColor(red: 0.16, green: 0.25, blue: 0.21, alpha: 1))
        let stone = material(NSColor(red: 0.76, green: 0.73, blue: 0.61, alpha: 1))
        let glass = material(NSColor(red: 0.47, green: 0.65, blue: 0.69, alpha: 1))
        let oak = (0..<4).map { i in material(NSColor(red: 0.43 + Double(i) * 0.025, green: 0.28 + Double(i) * 0.022, blue: 0.15 + Double(i) * 0.017, alpha: 1)) }
        // Connecting cabinets follow the station worktop height (scaled about the floor line).
        let cabinets = SCNNode(); cabinets.name = "connecting cabinets"
        let k = CGFloat(KitchenLayout.heightScale)
        cabinets.scale.y = k; cabinets.position.y = KitchenLayout.floorTop * (1 - k)
        root.addChildNode(cabinets)
        func box(_ name: String, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ mat: SCNMaterial, in parent: SCNNode? = nil) {
            let shape = SCNBox(width: w, height: h, length: d, chamferRadius: min(0.035, h / 3))
            shape.materials = [mat]; let node = SCNNode(geometry: shape)
            node.name = name; node.position = SCNVector3(x, y, z); (parent ?? root).addChildNode(node)
        }
        let counter = material(NSColor(red: 0.9, green: 0.87, blue: 0.77, alpha: 1))
        let brass = material(NSColor(red: 0.63, green: 0.45, blue: 0.22, alpha: 1))
        for r in KitchenLayout.connectors {
            box("connecting cabinet", r.width - 0.10, 0.87, r.height - 0.10, r.midX, 0.72, r.midY, trim, in: cabinets)
            box("connecting counter", r.width, 0.20, r.height, r.midX, 1.262, r.midY, counter, in: cabinets)
            let sideways = r.height > r.width
            let length = sideways ? r.height : r.width
            let count = max(1, Int(length / 0.9))
            let bay = length / CGFloat(count)
            for i in 0..<count {
                let along = -length / 2 + (CGFloat(i) + 0.5) * bay
                if sideways {
                    let face = r.midX < 0 ? r.maxX - 0.04 : r.minX + 0.04
                    box("module door", 0.04, 0.72, bay - 0.05, face, 0.72, r.midY + along, plaster, in: cabinets)
                    box("module pull", 0.07, 0.045, 0.24, face, 0.99, r.midY + along, brass, in: cabinets)
                } else {
                    box("module door", bay - 0.05, 0.72, 0.04, r.midX + along, 0.72, r.maxY - 0.04, plaster, in: cabinets)
                    box("module pull", 0.24, 0.045, 0.07, r.midX + along, 0.99, r.maxY - 0.04, brass, in: cabinets)
                }
            }
        }
        // Staggered oak boards, with shared materials and deliberate, visible seams.
        let floor = KitchenLayout.floor
        let rows = Int(floor.height / 0.5), cols = Int(floor.width / 2) + 1
        for row in 0..<rows {
            let offset: CGFloat = row % 2 == 0 ? 0 : -1
            for col in 0..<cols {
                let start = max(floor.minX, floor.minX + CGFloat(col) * 2 + offset)
                let end = min(floor.maxX, floor.minX + 2 + CGFloat(col) * 2 + offset)
                guard end > start else { continue }
                box("oak board", end - start - 0.018, 0.018, 0.48, (start + end) / 2, 0.11, floor.minY + 0.25 + CGFloat(row) * 0.5, oak[(row * 3 + col) % 4])
            }
        }
        let back = floor.minY + 0.13
        box("back wall", floor.width, 2.9, 0.22, floor.midX, 1.55, back, plaster)
        box("back cornice", floor.width, 0.14, 0.28, floor.midX, 3.04, back + 0.02, trim)
        box("back skirting", floor.width, 0.2, 0.28, floor.midX, 0.24, back + 0.02, trim)
        // Large backsplash tiles give the wall scale without busy surface detail.
        for row in 0..<4 { for col in 0..<Int(floor.width) {
            box("backsplash tile", 0.97, 0.34, 0.025, floor.minX + 0.5 + CGFloat(col), 0.55 + CGFloat(row) * 0.37, back + 0.125, stone)
        } }
        for x: CGFloat in [floor.minX + 0.15, floor.maxX - 0.15] {
            box("low side wall", 0.26, 0.75, floor.height - 0.3, x, 0.49, floor.midY, plaster)
            box("side coping", 0.30, 0.09, floor.height - 0.3, x, 0.91, floor.midY, trim)
        }
        let window: CGFloat = 3.4
        box("window frame", 2.65, 1.8, 0.12, window, 1.96, back + 0.19, trim)
        box("window glass", 2.39, 1.54, 0.035, window, 1.96, back + 0.275, glass)
        box("window mullion", 0.075, 1.58, 0.06, window, 1.96, back + 0.31, trim)
        box("window crossbar", 2.42, 0.065, 0.06, window, 1.96, back + 0.31, trim)
        // Break room: low partial walls keep it visible from above, with a doorway to the kitchen.
        for wall in KitchenLayout.breakRoomWalls {
            box("break room wall", wall.width, 1.0, wall.height, wall.midX, 0.6, wall.midY, plaster)
            box("break room coping", wall.width + 0.04, 0.07, wall.height + 0.04, wall.midX, 1.12, wall.midY, trim)
        }
        return root
    }
}
