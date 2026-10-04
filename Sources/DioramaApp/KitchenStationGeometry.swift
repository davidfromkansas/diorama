import AppKit
import SceneKit

/// Small, static architectural models. Every fixture stays inside its station footprint.
@MainActor enum KitchenStationGeometry {
    static func make(_ area: KitchenArea) -> SCNNode {
        let root = SCNNode()
        root.name = area.id
        root.scale.y = 1.25 * CGFloat(KitchenLayout.heightScale)
        root.position = SCNVector3(area.footprint.midX, 0.112, area.footprint.midY)
        let sideways = area.id == "test"
        let width = sideways ? area.footprint.height : area.footprint.width
        let depth = sideways ? area.footprint.width : area.footprint.height
        if sideways { root.eulerAngles.y = -.pi / 2 }
        let green = material(NSColor(red: 0.15, green: 0.25, blue: 0.23, alpha: 1))
        let ivory = material(NSColor(red: 0.84, green: 0.82, blue: 0.74, alpha: 1))
        let brass = material(NSColor(red: 0.66, green: 0.47, blue: 0.23, alpha: 1), metal: 0.7)
        let dark = material(NSColor(red: 0.055, green: 0.065, blue: 0.06, alpha: 1))
        let oak = material(NSColor(red: 0.43, green: 0.26, blue: 0.13, alpha: 1))
        let ceramic = material(NSColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 1))
        let steel = material(NSColor(white: 0.48, alpha: 1), metal: 0.8)
        let paint = ["build", "prep", "review"].contains(area.id) ? green : ivory
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
        if area.id == "test" {
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
        // Framed doors, inset panels, and brass pulls on both island elevations.
        for side in (area.id == "prep" ? [-1.0, 1.0] : [1.0]) {
            let face = CGFloat(side) * (depth / 2 - 0.08)
            for i in 0..<count {
                let x = -width / 2 + 0.08 + bay * (CGFloat(i) + 0.5)
                box("framed door", bay - 0.035, 0.66, 0.035, x, 0.51, face, paint)
                box("inset panel", bay - 0.15, 0.47, 0.025, x, 0.49, face - CGFloat(side) * 0.012, ivoryIfNeeded(paint, area: area, ivory: ivory))
                box("brass pull", 0.28, 0.055, 0.075, x, 0.76, face + CGFloat(side) * 0.043, brass)
            }
        }
        switch area.id {
        case "context":
            // Open French dresser: shallow shelves leave the lower worktop useful.
            box("dresser back", width - 0.12, 1.4, 0.07, 0, 1.7, -depth / 2 + 0.07, paint)
            for x in [-width / 2 + 0.1, width / 2 - 0.1] {
                box("dresser stile", 0.12, 1.46, 0.44, x, 1.73, -depth / 2 + 0.24, paint)
            }
            for y in [1.38, 1.9, 2.43] {
                box("oak shelf", width - 0.12, 0.065, 0.48, 0, y, -depth / 2 + 0.27, oak)
            }
            box("dresser cornice", width, 0.09, 0.54, 0, 2.48, -depth / 2 + 0.27, ivory)
            for i in 0..<7 {
                let x = -width / 2 + 0.42 + CGFloat(i) * 0.62
                cylinder("pantry jar", 0.13, 0.27, x, 1.56, -0.35, ceramic)
                cylinder("jar lid", 0.14, 0.035, x, 1.71, -0.35, brass)
                for j in 0..<3 { cylinder("stacked bowl", 0.17, 0.05, x, 1.96 + CGFloat(j) * 0.045, -0.35, ceramic) }
            }
        case "build":
            // Enamel range with two oven doors and six cast-iron burners.
            box("range front", width - 0.2, 0.7, 0.055, 0, 0.52, depth / 2 - 0.015, green)
            for x in [-width * 0.24, width * 0.24] {
                box("oven brass frame", width * 0.4, 0.49, 0.04, x, 0.45, depth / 2 + 0.002, brass)
                box("oven enamel door", width * 0.4 - 0.06, 0.43, 0.03, x, 0.45, depth / 2 + 0.025, green)
                box("oven window", width * 0.29, 0.22, 0.025, x, 0.43, depth / 2 + 0.043, dark)
                box("oven rail", width * 0.28, 0.04, 0.065, x, 0.65, depth / 2 - 0.015, brass)
            }
            box("enameled cooktop", width - 0.2, 0.025, depth - 0.12, 0, 1.01, 0, dark)
            for x in [-1.5, 0.0, 1.5] { for z in [-0.34, 0.34] {
                cylinder("brass burner", 0.13, 0.04, x, 1.04, z, brass)
                ring(0.23, x, 1.08, z, dark)
                box("burner grate", 0.6, 0.055, 0.045, x, 1.08, z, steel)
                box("burner grate", 0.045, 0.055, 0.55, x, 1.08, z, steel)
            } }
            for i in 0..<6 {
                let knob = cylinder("range knob", 0.055, 0.04, -1.65 + CGFloat(i) * 0.66, 0.83, depth / 2 - 0.015, brass)
                knob.eulerAngles.x = .pi / 2
            }
            // Low backguard instead of a suspended hood that would hide the burners.
            box("range backguard", width - 0.14, 0.32, 0.08, 0, 1.14, -depth / 2 + 0.055, green)
            box("backguard brass trim", width - 0.1, 0.035, 0.1, 0, 1.31, -depth / 2 + 0.055, brass)
        case "prep":
            box("butcher block", 1.7, 0.09, 1.25, -1.05, 1.045, 0, oak)
            cylinder("mixing bowl", 0.32, 0.19, 0.45, 1.09, -0.35, ceramic)
            cylinder("bowl interior", 0.26, 0.012, 0.45, 1.19, -0.35, ivory)
            let pin = cylinder("rolling pin", 0.055, 0.8, -1.1, 1.13, 0.22, oak)
            pin.eulerAngles.z = .pi / 2
            box("folded linen", 0.56, 0.035, 0.65, 1.55, 1.02, 0.28, ivory)
        case "test":
            box("sink basin bottom", 1.2, 0.055, 0.88, -0.2, 0.69, 0, steel)
            for x in [-0.8, 0.4] { box("sink basin wall", 0.055, 0.32, 0.94, x, 0.85, 0, steel) }
            for z in [-0.44, 0.44] { box("sink basin wall", 1.25, 0.32, 0.055, -0.2, 0.85, z, steel) }
            cylinder("sink drain", 0.075, 0.015, -0.2, 0.724, 0, dark)
            cylinder("tap riser", 0.04, 0.48, -0.2, 1.25, -0.53, brass)
            box("tap spout", 0.075, 0.07, 0.42, -0.2, 1.49, -0.35, brass)
            cylinder("tap outlet", 0.045, 0.12, -0.2, 1.43, -0.14, brass)
            for i in 0..<5 { box("drainer groove", 0.025, 0.012, 0.7, 0.8 + CGFloat(i) * 0.1, 1.01, 0, brass) }
        case "attention":
            box("espresso machine", 1.05, 0.58, 0.63, -0.75, 1.29, -0.15, green)
            box("espresso brass fascia", 0.96, 0.12, 0.045, -0.75, 1.43, 0.19, brass)
            box("drip tray", 0.97, 0.045, 0.3, -0.75, 1.04, 0.25, steel)
            for x in [-0.98, -0.52] { cylinder("espresso cup", 0.075, 0.11, x, 1.12, 0.25, ceramic) }
            cylinder("cup saucer", 0.18, 0.025, 0.65, 1.02, 0.1, ceramic)
            cylinder("coffee cup", 0.10, 0.16, 0.65, 1.11, 0.1, ceramic)
        default:
            for x in [-1.35, 0.0, 1.35] {
                cylinder("serving platter", 0.42, 0.03, x, 1.025, 0, ceramic)
                let dome = SCNSphere(radius: 0.34); dome.segmentCount = 20; dome.materials = [steel]
                let node = SCNNode(geometry: dome); node.name = "silver cloche"
                node.scale = SCNVector3(1, 0.65, 1); node.position = SCNVector3(x, 1.045, 0); root.addChildNode(node)
                cylinder("cloche handle", 0.045, 0.075, x, 1.29, 0, brass)
            }
        }
        return root
    }

    private static func ivoryIfNeeded(_ paint: SCNMaterial, area: KitchenArea, ivory: SCNMaterial) -> SCNMaterial {
        area.id == "context" || area.id == "attention" || area.id == "test" ? ivory : paint
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
