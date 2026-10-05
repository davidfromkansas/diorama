import AppKit
import SceneKit

/// Small, static architectural models. Every fixture stays inside its station footprint.
@MainActor enum KitchenStationGeometry {
    static func make(_ area: KitchenArea) -> SCNNode {
        switch area.id {
        case "elevator": return elevator(area)
        case "bell": return bell(area)
        case "break": return breakTable(area)
        default: return counter(area)
        }
    }

    private static func counter(_ area: KitchenArea) -> SCNNode {
        let root = SCNNode()
        root.name = area.id
        root.scale.y = 1.25 * CGFloat(KitchenLayout.heightScale)
        root.position = SCNVector3(area.footprint.midX, KitchenLayout.floorTop, area.footprint.midY)
        // Fixtures are modelled with their working face toward local +Z (the room).
        let sideways = area.wall == .left || area.wall == .right
        let width = sideways ? area.footprint.height : area.footprint.width
        let depth = sideways ? area.footprint.width : area.footprint.height
        if area.wall == .left { root.eulerAngles.y = .pi / 2 }
        if area.wall == .right { root.eulerAngles.y = -.pi / 2 }
        let green = material(NSColor(red: 0.15, green: 0.25, blue: 0.23, alpha: 1))
        let ivory = material(NSColor(red: 0.84, green: 0.82, blue: 0.74, alpha: 1))
        let brass = material(NSColor(red: 0.66, green: 0.47, blue: 0.23, alpha: 1), metal: 0.7)
        let dark = material(NSColor(red: 0.055, green: 0.065, blue: 0.06, alpha: 1))
        let oak = material(NSColor(red: 0.43, green: 0.26, blue: 0.13, alpha: 1))
        let ceramic = material(NSColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 1))
        let steel = material(NSColor(white: 0.48, alpha: 1), metal: 0.8)
        let paper = material(NSColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1))
        let paint = ["stove", "cooking", "serving"].contains(area.id) ? green : ivory
        @discardableResult func box(_ name: String, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                                   _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ mat: SCNMaterial) -> SCNNode {
            let shape = SCNBox(width: w, height: h, length: d, chamferRadius: min(0.065, min(w, min(h, d)) / 4))
            shape.materials = [mat]
            let node = SCNNode(geometry: shape); node.name = name
            node.position = SCNVector3(x, y, z); root.addChildNode(node)
            return node
        }
        @discardableResult func cylinder(_ name: String, _ radius: CGFloat, _ h: CGFloat,
                                        _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ mat: SCNMaterial) -> SCNNode {
            let shape = SCNCylinder(radius: radius, height: h); shape.radialSegmentCount = 20; shape.materials = [mat]
            let node = SCNNode(geometry: shape); node.name = name; node.position = SCNVector3(x, y, z)
            root.addChildNode(node); return node
        }
        func ring(_ radius: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ mat: SCNMaterial) {
            let shape = SCNTorus(ringRadius: radius, pipeRadius: 0.025)
            shape.ringSegmentCount = 24; shape.pipeSegmentCount = 8; shape.materials = [mat]
            let node = SCNNode(geometry: shape); node.position = SCNVector3(x, y, z); root.addChildNode(node)
        }
        box("recessed plinth", width - 0.30, 0.18, depth - 0.30, 0, 0.07, 0, dark)
        if area.id == "tasting" {
            // A real opening through the worktop; the basin sits below its rim.
            box("sink cabinet base", width - 0.18, 0.44, depth - 0.18, 0, 0.40, 0, paint)
            for (x, w) in [((-width / 2 - 0.8) / 2, width / 2 - 0.8), ((width / 2 + 0.4) / 2, width / 2 - 0.4)] {
                box("sink cabinet side", w - 0.05, 0.3, depth - 0.18, x, 0.75, 0, paint)
                box("stone worktop wing", w, 0.16, depth, x, 0.92, 0, marble)
            }
            for z in [-1.0, 1.0] {
                box("stone sink surround", 1.2, 0.16, depth / 2 - 0.44, -0.2, 0.92, z * (depth / 2 + 0.44) / 2, marble)
            }
        } else {
            box("cabinet carcass", width - 0.18, 0.70, depth - 0.18, 0, 0.51, 0, paint)
            box("stone worktop", width, 0.16, depth, 0, 0.92, 0, marble)
        }
        let count = max(2, Int(width / 0.85))
        let bay = (width - 0.16) / CGFloat(count)
        // Framed doors, inset panels, and brass pulls on the room-facing elevations.
        for side in (area.wall == .island ? [-1.0, 1.0] : [1.0]) {
            let face = CGFloat(side) * (depth / 2 - 0.08)
            for i in 0..<count {
                let x = -width / 2 + 0.08 + bay * (CGFloat(i) + 0.5)
                box("framed door", bay - 0.035, 0.66, 0.035, x, 0.51, face, paint)
                box("inset panel", bay - 0.15, 0.47, 0.025, x, 0.49, face - CGFloat(side) * 0.012, paint === green ? ivory : paint)
                box("brass pull", 0.28, 0.055, 0.075, x, 0.76, face + CGFloat(side) * 0.043, brass)
            }
        }
        switch area.id {
        case "order":
            // A steel ticket rail on the wall with the incoming orders clipped to it.
            box("ticket rail", width - 0.3, 0.05, 0.06, 0, 1.9, -depth / 2 + 0.08, steel)
            for i in 0..<Int((width - 0.6) / 0.42) {
                let ticket = box("order ticket", 0.26, 0.36, 0.012, -width / 2 + 0.45 + CGFloat(i) * 0.42, 1.68, -depth / 2 + 0.1, paper)
                ticket.eulerAngles.z = CGFloat(i % 3 - 1) * 0.06
            }
            box("ticket spike", 0.04, 0.22, 0.04, width / 2 - 0.5, 1.11, 0, steel)
        case "prep":
            // Open French dresser for the cookbooks, and a recipe board for planning.
            box("dresser back", width - 0.12, 1.4, 0.07, 0, 1.7, -depth / 2 + 0.07, paint)
            for x in [-width / 2 + 0.1, width / 2 - 0.1] {
                box("dresser stile", 0.12, 1.46, 0.44, x, 1.73, -depth / 2 + 0.24, paint)
            }
            for y in [1.38, 1.9, 2.43] {
                box("oak shelf", width - 0.12, 0.065, 0.48, 0, y, -depth / 2 + 0.27, oak)
            }
            box("dresser cornice", width, 0.09, 0.54, 0, 2.48, -depth / 2 + 0.27, ivory)
            for i in 0..<max(1, Int((width / 2 - 0.4) / 0.42)) {
                let x = -width / 2 + 0.4 + CGFloat(i) * 0.42
                box("cookbook", 0.09, 0.34, 0.3, x, 1.58, -0.35, i % 2 == 0 ? green : oak)
            }
            box("recipe board", width * 0.4, 0.62, 0.04, width * 0.22, 2.0, -depth / 2 + 0.52, oak)
            for i in 0..<3 { box("recipe card", 0.3, 0.4, 0.012, width * 0.22 + CGFloat(i - 1) * 0.42, 2.0, -depth / 2 + 0.55, paper) }
        case "stove":
            // One clear burner per chef, centred on its working spot; flames are lit by the view.
            box("range front", width - 0.2, 0.7, 0.055, 0, 0.52, depth / 2 - 0.015, green)
            box("enameled cooktop", width - 0.2, 0.025, depth - 0.12, 0, 1.01, 0, dark)
            for i in 0..<area.spots {
                let x = -width / 2 + (CGFloat(i) + 0.5) * width / CGFloat(area.spots)
                cylinder("brass burner", 0.13, 0.04, x, 1.04, 0, brass)
                ring(0.23, x, 1.08, 0, dark)
                box("burner grate", 0.6, 0.055, 0.045, x, 1.08, 0, steel)
                box("burner grate", 0.045, 0.055, 0.55, x, 1.08, 0, steel)
                box("oven brass frame", width / CGFloat(area.spots) * 0.8, 0.49, 0.04, x, 0.45, depth / 2 + 0.002, brass)
                box("oven window", width / CGFloat(area.spots) * 0.55, 0.22, 0.025, x, 0.43, depth / 2 + 0.03, dark)
                let knob = cylinder("range knob", 0.055, 0.04, x, 0.83, depth / 2 - 0.015, brass)
                knob.eulerAngles.x = .pi / 2
            }
        case "cooking":
            // One clear cutting board per chef, on the chef's side of the island.
            for i in 0..<area.spots {
                let x = -width / 2 + (CGFloat(i) + 0.5) * width / CGFloat(area.spots)
                box("cutting board", 0.9, 0.05, 0.55, x, 1.025, -depth / 2 + 0.38, oak)
            }
        case "tasting":
            box("sink basin bottom", 1.2, 0.055, 0.88, -0.2, 0.69, 0, steel)
            for x in [-0.8, 0.4] { box("sink basin wall", 0.055, 0.32, 0.94, x, 0.85, 0, steel) }
            for z in [-0.44, 0.44] { box("sink basin wall", 1.25, 0.32, 0.055, -0.2, 0.85, z, steel) }
            cylinder("sink drain", 0.075, 0.015, -0.2, 0.724, 0, dark)
            cylinder("tap riser", 0.04, 0.48, -0.2, 1.25, -0.53, brass)
            box("tap spout", 0.075, 0.07, 0.42, -0.2, 1.49, -0.35, brass)
            cylinder("tap outlet", 0.045, 0.12, -0.2, 1.43, -0.14, brass)
            for i in 0..<5 { box("drainer groove", 0.025, 0.012, 0.7, 0.8 + CGFloat(i) * 0.1, 1.01, 0, brass) }
            for i in 0..<3 { cylinder("tasting spoon cup", 0.08, 0.16, width / 2 - 0.4 - CGFloat(i) * 0.3, 1.08, -0.3, ceramic) }
        case "serving":
            // The pass: a framed window with heat lamps over the counter.
            for x in [-width / 2 + 0.08, width / 2 - 0.08] { box("window post", 0.12, 1.9, 0.12, x, 1.95, 0, green) }
            box("window header", width, 0.22, 0.3, 0, 2.95, 0, green)
            let lamps = max(2, Int(width / 1.5))
            for i in 0..<lamps {
                let x = -width / 2 + (CGFloat(i) + 0.5) * width / CGFloat(lamps)
                cylinder("heat lamp", 0.16, 0.18, x, 2.75, 0, brass)
                cylinder("serving platter", 0.3, 0.03, x, 1.025, 0.15, ceramic)
            }
        default:
            break
        }
        return root
    }

    /// Elevator car opening onto the kitchen; doors are named so arrivals can slide them open.
    private static func elevator(_ area: KitchenArea) -> SCNNode {
        let root = SCNNode(); root.name = area.id
        root.position = SCNVector3(area.footprint.midX, KitchenLayout.floorTop, area.footprint.midY)
        let w = area.footprint.width, d = area.footprint.height, h: CGFloat = 2.9
        let frame = material(NSColor(red: 0.25, green: 0.27, blue: 0.3, alpha: 1), metal: 0.5)
        let steel = material(NSColor(white: 0.66, alpha: 1), metal: 0.85)
        let lamp = material(NSColor(red: 1, green: 0.78, blue: 0.4, alpha: 1)); lamp.emission.contents = NSColor(red: 1, green: 0.7, blue: 0.3, alpha: 1)
        func box(_ name: String, _ bw: CGFloat, _ bh: CGFloat, _ bd: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ mat: SCNMaterial) {
            let shape = SCNBox(width: bw, height: bh, length: bd, chamferRadius: 0.02); shape.materials = [mat]
            let node = SCNNode(geometry: shape); node.name = name; node.position = SCNVector3(x, y, z); root.addChildNode(node)
        }
        box("elevator back", w, h, 0.12, 0, h / 2, -d / 2 + 0.06, frame)
        for x in [-w / 2 + 0.06, w / 2 - 0.06] { box("elevator side", 0.12, h, d, x, h / 2, 0, frame) }
        box("elevator header", w, 0.42, 0.16, 0, h - 0.21, d / 2 - 0.08, frame)
        box("floor indicator", 0.5, 0.12, 0.03, 0, h - 0.2, d / 2 + 0.01, lamp)
        box("elevator floor", w - 0.24, 0.03, d - 0.12, 0, 0.015, 0, steel)
        for (name, x) in [("elevator door left", -w / 4 + 0.03), ("elevator door right", w / 4 - 0.03)] {
            box(name, w / 2 - 0.12, h - 0.46, 0.06, x, (h - 0.42) / 2, d / 2 - 0.05, steel)
        }
        return root
    }

    /// Brass service bell on a pedestal in the open middle of the room.
    private static func bell(_ area: KitchenArea) -> SCNNode {
        let root = SCNNode(); root.name = area.id
        root.position = SCNVector3(area.footprint.midX, KitchenLayout.floorTop, area.footprint.midY)
        let top = CGFloat(KitchenLayout.worktopHeight) - KitchenLayout.floorTop
        let green = material(NSColor(red: 0.15, green: 0.25, blue: 0.23, alpha: 1))
        let brass = material(NSColor(red: 0.78, green: 0.58, blue: 0.27, alpha: 1), metal: 0.85)
        let pedestal = SCNCylinder(radius: 0.32, height: top); pedestal.materials = [green]
        let column = SCNNode(geometry: pedestal); column.position.y = top / 2; root.addChildNode(column)
        let dome = SCNSphere(radius: 0.26); dome.materials = [brass]
        let bell = SCNNode(geometry: dome); bell.name = "service bell"; bell.scale = SCNVector3(1, 0.7, 1); bell.position.y = top + 0.04
        root.addChildNode(bell)
        let knob = SCNSphere(radius: 0.06); knob.materials = [brass]
        let button = SCNNode(geometry: knob); button.position.y = top + 0.24; root.addChildNode(button)
        return root
    }

    /// The break room: a low coffee table between two rows of Eames lounge chairs (the bundled
    /// Herman Miller Classic model). Each chair sits behind a chef slot, facing the table.
    static let loungeChairScale: CGFloat = 1.45
    /// How far a seated chef's root sits in front of its chair's centre.
    static let loungeChairSetback: Float = 0.12
    private static func breakTable(_ area: KitchenArea) -> SCNNode {
        let root = SCNNode(); root.name = area.id
        root.position = SCNVector3(area.footprint.midX, KitchenLayout.floorTop, area.footprint.midY)
        let walnut = material(NSColor(red: 0.34, green: 0.2, blue: 0.1, alpha: 1))
        let ceramic = material(NSColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 1))
        let w = area.footprint.width - 0.6, d = area.footprint.height * 0.6, top: CGFloat = 0.42
        let slab = SCNBox(width: w, height: 0.06, length: d, chamferRadius: 0.03); slab.materials = [walnut]
        let table = SCNNode(geometry: slab); table.name = "coffee table"; table.position.y = top; root.addChildNode(table)
        for x in [-w / 2 + 0.2, w / 2 - 0.2] { for z in [-d / 2 + 0.12, d / 2 - 0.12] {
            let legShape = SCNCylinder(radius: 0.035, height: top); legShape.materials = [walnut]
            let leg = SCNNode(geometry: legShape); leg.position = SCNVector3(x, top / 2, z); root.addChildNode(leg)
        } }
        for i in 0..<4 {
            let pot = SCNCylinder(radius: 0.09, height: 0.12); pot.materials = [ceramic]
            let node = SCNNode(geometry: pot); node.position = SCNVector3(-w / 2 + 0.6 + CGFloat(i) * (w - 1.2) / 3, top + 0.09, 0)
            root.addChildNode(node)
        }
        if let chair = OfficeLoungeAssets.template("EamesLounge") {
            let center = SIMD2(Float(area.footprint.midX), Float(area.footprint.midY))
            for seat in KitchenLayout.chefSlots[area.id] ?? [] {
                let forward = SIMD2(sin(seat.facing), cos(seat.facing))
                let spot = seat.stand - forward * loungeChairSetback - center
                let node = chair.clone(); node.name = "lounge chair"
                node.scale = SCNVector3(loungeChairScale, loungeChairScale, loungeChairScale)
                node.eulerAngles.y = CGFloat(seat.facing)
                node.position = SCNVector3(CGFloat(spot.x), -CGFloat(node.boundingBox.min.y) * loungeChairScale, CGFloat(spot.y))
                root.addChildNode(node)
            }
        }
        return root
    }

    private static func material(_ color: NSColor, metal: CGFloat = 0) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = color; result.lightingModel = .physicallyBased
        result.roughness.contents = metal > 0 ? 0.32 : 0.62; result.metalness.contents = metal
        return result
    }
    private static let marble: SCNMaterial = {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.lockFocus()
        NSColor(red: 0.94, green: 0.93, blue: 0.88, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 512, height: 512).fill()
        for i in 0..<12 {
            let path = NSBezierPath(); let y = CGFloat(i) * 52 - 65
            path.move(to: NSPoint(x: 0, y: y))
            path.curve(to: NSPoint(x: 512, y: y + 170), controlPoint1: NSPoint(x: 150, y: y + 130), controlPoint2: NSPoint(x: 340, y: y + 20))
            NSColor(red: 0.52, green: 0.53, blue: 0.48, alpha: 0.16).setStroke()
            path.lineWidth = i % 3 == 0 ? 2.5 : 0.7; path.stroke()
        }
        image.unlockFocus()
        let value = material(.white); value.diffuse.contents = image; value.roughness.contents = 0.38
        return value
    }()
}
