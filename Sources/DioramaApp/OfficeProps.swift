import AppKit
import SceneKit

/// What office chefs carry and serve. Models follow the kitchen's props' normalization (centred,
/// base at 0, widest side about 1): modelled ones from `Resources/OfficeProps` (assets/office)
/// replace these procedural stand-ins when bundled.
@MainActor enum OfficeProps {
    private typealias M = OfficeMaterials
    private static let modelled: [String: SCNNode] = KitchenFood.models(in: "OfficeProps")

    /// Finished work: a gift-wrapped box per task, in the office's pastels.
    static let deliverables: [String: SCNNode] = {
        let wraps: [(String, NSColor, NSColor)] = [
            ("box_sky", OfficeLayout.sky, OfficeLayout.coral), ("box_mint", OfficeLayout.mint, OfficeLayout.lilac),
            ("box_peach", OfficeLayout.peach, OfficeLayout.sky), ("box_lilac", OfficeLayout.lilac, OfficeLayout.butter),
            ("box_butter", OfficeLayout.butter, OfficeLayout.coral), ("box_coral", OfficeLayout.coral, OfficeLayout.mint)]
        var result: [String: SCNNode] = [:]
        for (id, paper, ribbon) in wraps {
            if let model = modelled[id] { result[id] = model; continue }
            let kit = OfficeBuilder(named: "OfficeProps:" + id)
            let w: CGFloat = 0.8, h: CGFloat = 0.46, d: CGFloat = 0.62
            kit.box("box", w, h, d, 0, h / 2, 0, M.matte(paper, roughness: 0.6), chamfer: 0.02)
            kit.box("box lid", w + 0.04, 0.08, d + 0.04, 0, h - 0.02, 0, M.matte(paper.blended(withFraction: 0.12, of: .white) ?? paper, roughness: 0.6), chamfer: 0.02)
            let tie = M.matte(ribbon, roughness: 0.45)
            kit.box("ribbon", w + 0.05, h + 0.06, 0.08, 0, h / 2 + 0.01, 0, tie, chamfer: 0.005)
            kit.box("ribbon", 0.08, h + 0.06, d + 0.05, 0, h / 2 + 0.01, 0, tie, chamfer: 0.005)
            for side in [-1.0, 1.0] as [CGFloat] {
                let loop = SCNTorus(ringRadius: 0.09, pipeRadius: 0.03); loop.materials = [tie]
                let node = SCNNode(geometry: loop); node.name = "bow"
                node.position = SCNVector3(side * 0.09, h + 0.1, 0); node.eulerAngles = SCNVector3(.pi / 2, 0, side * 0.5)
                kit.root.addChildNode(node)
            }
            result[id] = kit.root
        }
        return result
    }()

    /// What sits on a lobby table before anything is served: a laptop or coffee cups.
    static let tableSettings: [String: SCNNode] = {
        var result: [String: SCNNode] = [:]
        let laptop = OfficeBuilder(named: "OfficeProps:laptop")
        laptop.box("laptop base", 0.6, 0.03, 0.42, 0, 0.015, 0.05, M.aluminium, chamfer: 0.012)
        let lid = laptop.box("laptop lid", 0.6, 0.4, 0.02, 0, 0.21, -0.17, M.aluminium, chamfer: 0.012)
        lid.eulerAngles.x = -0.25
        result["laptop"] = laptop.root
        let coffee = OfficeBuilder(named: "OfficeProps:coffee")
        coffee.cylinder("saucer", 0.16, 0.02, -0.18, 0.01, 0, M.white)
        coffee.cylinder("cup", 0.09, 0.14, -0.18, 0.09, 0, M.white)
        coffee.cylinder("coffee", 0.08, 0.005, -0.18, 0.16, 0, M.matte(NSColor(srgbRed: 0.35, green: 0.22, blue: 0.14, alpha: 1)))
        coffee.cylinder("saucer", 0.16, 0.02, 0.2, 0.01, 0.05, M.white)
        coffee.cylinder("cup", 0.09, 0.14, 0.2, 0.09, 0.05, M.accent(OfficeLayout.peach))
        result["coffee"] = coffee.root
        let notebook = OfficeBuilder(named: "OfficeProps:notebook")
        notebook.box("notebook", 0.36, 0.04, 0.5, -0.12, 0.02, 0, M.accent(OfficeLayout.sage), chamfer: 0.01)
        notebook.box("pen", 0.04, 0.03, 0.42, 0.18, 0.015, 0, M.black, chamfer: 0.01)
        notebook.cylinder("cup", 0.08, 0.14, 0.3, 0.07, -0.2, M.white)
        result["notebook"] = notebook.root
        return result
    }()

    /// What chefs carry out of stations, by kind: binders of skills, toolboxes of plugins,
    /// devices for MCP servers, the plan from the whiteboards and the idea from the ticket board.
    static var carryModels: [PantryCarry.Kind: SCNNode] {
        var result: [PantryCarry.Kind: SCNNode] = [:]
        result[.skill] = modelled["binder"] ?? {
            let kit = OfficeBuilder(named: "OfficeProps:binder")
            kit.box("binder", 0.3, 0.9, 0.75, 0, 0.45, 0, M.accent(OfficeLayout.sky), chamfer: 0.03)
            kit.box("binder pages", 0.24, 0.84, 0.72, 0.04, 0.45, 0, M.paper, chamfer: 0.01)
            kit.box("binder label", 0.02, 0.3, 0.4, -0.16, 0.5, 0, M.paper, chamfer: 0)
            return kit.root
        }()
        result[.plugin] = modelled["toolbox"] ?? {
            let kit = OfficeBuilder(named: "OfficeProps:toolbox")
            kit.box("toolbox", 1.0, 0.45, 0.5, 0, 0.225, 0, M.accent(OfficeLayout.coral), chamfer: 0.06)
            kit.box("toolbox lid", 1.02, 0.08, 0.52, 0, 0.47, 0, M.accent(OfficeLayout.coral.blended(withFraction: 0.2, of: .black) ?? OfficeLayout.coral), chamfer: 0.03)
            kit.box("toolbox handle", 0.5, 0.06, 0.08, 0, 0.62, 0, M.black, chamfer: 0.02)
            for x in [-0.25, 0.25] as [CGFloat] { kit.box("toolbox post", 0.06, 0.12, 0.08, x, 0.55, 0, M.black) }
            return kit.root
        }()
        result[.connector] = modelled["device"] ?? {
            let kit = OfficeBuilder(named: "OfficeProps:device")
            kit.box("device", 1.0, 0.26, 0.7, 0, 0.13, 0, M.white, chamfer: 0.06)
            kit.sphere("device light", 0.05, 0.3, 0.2, 0.36, M.glow(NSColor(srgbRed: 0.40, green: 0.95, blue: 0.62, alpha: 1)), segments: 8)
            for x in [-0.38, 0.38] as [CGFloat] { kit.cylinder("antenna", 0.025, 0.6, x, 0.55, -0.3, M.black, segments: 6) }
            return kit.root
        }()
        result[.plan] = modelled["plan_board"] ?? {
            let kit = OfficeBuilder(named: "OfficeProps:plan")
            kit.box("clipboard", 0.8, 0.04, 1.0, 0, 0.02, 0, M.oakEdge, chamfer: 0.02)
            kit.box("plan page", 0.7, 0.01, 0.85, 0, 0.045, -0.03, M.paper, chamfer: 0)
            kit.box("clip", 0.3, 0.06, 0.1, 0, 0.06, -0.47, M.aluminium, chamfer: 0.01)
            for i in 0..<4 { kit.box("plan line", 0.5 - CGFloat(i % 2) * 0.15, 0.004, 0.03, -0.05, 0.052, -0.25 + CGFloat(i) * 0.15, M.matte(OfficeLayout.sky), chamfer: 0) }
            return kit.root
        }()
        result[.idea] = KitchenProps.templates["lightbulb"]
        return result
    }

    /// The ticket board always hands out the idea (a lightbulb); desks and the rack hand out nothing.
    nonisolated static func stationItem(area: String) -> PantryCarry.Item? {
        area == "order" ? PantryCarry.Item(kind: .idea, name: "Ticket") : nil
    }
}
