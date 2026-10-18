import AppKit
import SceneKit

/// The office's fixtures, one per station, each inside its footprint with its worktop at the
/// chef's working height (`ChefMetrics.worktopHeight`). Modelled fixtures from
/// `Resources/OfficeStations` (built by assets/office/build.sh) are used when bundled; these
/// procedural ones stand in otherwise. The elevator and the lounge are the kitchen's.
@MainActor enum OfficeStationGeometry {
    static func make(_ area: SceneArea) -> SCNNode {
        if let modelled = OfficeFixtures.make(area) { return modelled }
        switch area.id {
        case "elevator": return KitchenStationGeometry.elevator(area)
        case "break": return KitchenStationGeometry.breakTable(area)
        case "order": return ticketBoard(area)
        case "prep": return whiteboards(area)
        case "cooking": return desks(area)
        case "stove": return serverRack(area)
        case "tasting": return qaBench(area)
        case "bell": return deskBell(area)
        case "serving": return demoTable(area)
        case "pantry": return supplyCloset(area)
        default: return credenza(area)
        }
    }

    /// The worktop's height above the station's root (which stands on the floor).
    static var top: CGFloat { CGFloat(ChefMetrics.worktopHeight) - ChefMetrics.floorTop }
    private typealias M = OfficeMaterials

    /// A root on the floor at the footprint's centre; wall stations turn so local +z faces the room.
    private static func base(_ area: SceneArea) -> (root: SCNNode, kit: OfficeBuilder, width: CGFloat, depth: CGFloat) {
        let root = SCNNode(); root.name = area.id
        root.position = SCNVector3(area.footprint.midX, ChefMetrics.floorTop, area.footprint.midY)
        let sideways = area.wall == .left || area.wall == .right
        if area.wall == .left { root.eulerAngles.y = .pi / 2 }
        if area.wall == .right { root.eulerAngles.y = -.pi / 2 }
        return (root, OfficeBuilder(root), sideways ? area.footprint.height : area.footprint.width, sideways ? area.footprint.width : area.footprint.height)
    }

    /// A low white credenza with an oak top and pastel drawer fronts facing the room (+z).
    private static func credenzaBody(_ kit: OfficeBuilder, width: CGFloat, depth: CGFloat, accent: NSColor, fronts: Bool = true) {
        kit.box("credenza", width - 0.08, top - 0.05, depth - 0.12, 0, (top - 0.05) / 2, 0, M.white)
        kit.box("credenza top", width, 0.05, depth, 0, top - 0.025, 0, M.oak, chamfer: 0.015)
        kit.box("credenza plinth", width - 0.3, 0.08, depth - 0.3, 0, 0.04, 0, M.black)
        guard fronts else { return }
        let count = max(2, Int(width / 1.1)), bay = (width - 0.16) / CGFloat(count)
        for i in 0..<count {
            let x = -width / 2 + 0.08 + bay * (CGFloat(i) + 0.5)
            kit.box("drawer front", bay - 0.05, top - 0.24, 0.025, x, (top - 0.05) / 2 + 0.04, depth / 2 - 0.05, M.accent(i % 2 == 0 ? accent : .white))
            kit.box("drawer pull", 0.22, 0.025, 0.04, x, top - 0.16, depth / 2 - 0.02, M.black)
        }
    }
    private static func credenza(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        credenzaBody(kit, width: width, depth: depth, accent: area.accent)
        return root
    }

    /// The ticket board along the back wall: a credenza under a cork board full of sticky notes.
    private static func ticketBoard(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        credenzaBody(kit, width: width, depth: depth, accent: area.accent)
        let wall = -depth / 2 + 0.05
        kit.box("cork board frame", width - 0.3, 1.36, 0.05, 0, top + 1.05, wall, M.oakEdge)
        kit.box("cork board", width - 0.42, 1.24, 0.04, 0, top + 1.05, wall + 0.02, M.cork)
        let notes = [OfficeLayout.butter, OfficeLayout.peach, OfficeLayout.mint, OfficeLayout.sky, OfficeLayout.lilac, OfficeLayout.coral]
        let columns = max(3, Int((width - 0.7) / 0.34))
        for row in 0..<3 {
            for column in 0..<columns where (row * 7 + column * 3) % 5 != 0 {
                let x = -width / 2 + 0.5 + CGFloat(column) * (width - 1.0) / CGFloat(columns - 1)
                let note = kit.box("sticky note", 0.24, 0.24, 0.01, x, top + 0.6 + CGFloat(row) * 0.36, wall + 0.05,
                                   M.matte(notes[(row * 5 + column) % notes.count], roughness: 0.9), chamfer: 0.002)
                note.eulerAngles.z = CGFloat((row + column) % 3 - 1) * 0.07
                kit.sphere("pin", 0.018, x, top + 0.69 + CGFloat(row) * 0.36, wall + 0.065, M.matte(.systemRed, roughness: 0.4), segments: 8)
            }
        }
        // Today's tickets on the credenza: a tray of cards and a mug.
        kit.box("ticket tray", 0.6, 0.06, 0.4, width / 2 - 0.7, top + 0.03, -0.1, M.black)
        for i in 0..<3 { kit.box("ticket card", 0.42, 0.012, 0.3, width / 2 - 0.7, top + 0.07 + CGFloat(i) * 0.015, -0.1, M.paper) }
        kit.cylinder("mug", 0.06, 0.12, -width / 2 + 0.6, top + 0.06, 0.1, M.accent(OfficeLayout.peach))
        kit.plant(-width / 2 + 0.35, -0.15, height: 0.7, base: top, seed: 2)
        return root
    }

    /// Three whiteboards on the back wall over a long credenza, scribbled with plans.
    private static func whiteboards(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        credenzaBody(kit, width: width, depth: depth, accent: area.accent)
        let wall = -depth / 2 + 0.05, boards = 3
        let boardWidth = (width - 0.6) / CGFloat(boards) - 0.2
        let ink = [NSColor(srgbRed: 0.18, green: 0.36, blue: 0.70, alpha: 1), NSColor(srgbRed: 0.80, green: 0.27, blue: 0.24, alpha: 1),
                   NSColor(srgbRed: 0.20, green: 0.55, blue: 0.35, alpha: 1), NSColor(srgbRed: 0.15, green: 0.15, blue: 0.18, alpha: 1)].map { M.matte($0, roughness: 0.5) }
        for b in 0..<boards {
            let x = -width / 2 + 0.3 + (boardWidth + 0.2) * (CGFloat(b) + 0.5) + 0.1
            let y = top + 1.0
            kit.box("whiteboard frame", boardWidth + 0.08, 1.22, 0.04, x, y, wall, M.aluminium)
            kit.box("whiteboard", boardWidth, 1.14, 0.03, x, y, wall + 0.015, M.matte(.white, roughness: 0.15))
            // Boxes, arrows and lines of a plan, a little different on each board.
            for i in 0..<4 {
                let bx = x - boardWidth / 2 + 0.35 + CGFloat(i) * (boardWidth - 0.7) / 3
                let by = y + (i % 2 == 0 ? 0.25 : -0.05) - CGFloat(b % 2) * 0.1
                let color = ink[(i + b) % ink.count]
                for (w, h, dx, dy) in [(0.36, 0.02, 0.0, 0.12), (0.36, 0.02, 0.0, -0.12), (0.02, 0.24, -0.17, 0.0), (0.02, 0.24, 0.17, 0.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                    kit.box("plan stroke", w, h, 0.004, bx + dx, by + dy, wall + 0.032, color, chamfer: 0)
                }
                if i < 3 { kit.box("plan arrow", (boardWidth - 0.7) / 3 - 0.4, 0.015, 0.004, bx + (boardWidth - 0.7) / 6, (by + y + (i % 2 == 0 ? -0.05 : 0.25) - CGFloat(b % 2) * 0.1) / 2, wall + 0.032, ink[3], chamfer: 0) }
                kit.box("plan note", 0.15, 0.15, 0.006, bx + 0.08, by - 0.36, wall + 0.034, M.matte([OfficeLayout.butter, OfficeLayout.peach, OfficeLayout.mint][(i + b) % 3], roughness: 0.9), chamfer: 0)
            }
            for line in 0..<3 {
                kit.box("plan line", boardWidth * 0.5 - CGFloat(line) * 0.15, 0.012, 0.004, x - boardWidth * 0.12, y - 0.4 - CGFloat(line) * 0.06, wall + 0.032, ink[3], chamfer: 0)
            }
            kit.box("marker tray", boardWidth * 0.6, 0.03, 0.08, x, y - 0.6, wall + 0.06, M.aluminium)
            for m in 0..<3 {
                let marker = kit.cylinder("marker", 0.015, 0.13, x - 0.15 + CGFloat(m) * 0.12, y - 0.57, wall + 0.06, ink[m], segments: 8)
                marker.eulerAngles.z = .pi / 2
            }
        }
        kit.plant(width / 2 - 0.35, -0.1, height: 0.8, base: top, seed: 1)
        kit.box("sticky pad", 0.18, 0.04, 0.18, -width / 2 + 0.5, top + 0.02, 0.1, M.matte(OfficeLayout.butter, roughness: 0.9))
        return root
    }

    /// A long standing desk worked from its far side: a laptop per chef, its screen toward the
    /// chef (lit while someone types, `DeskScreens`), mugs, lamps and plants between.
    private static func desks(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        kit.box("desk top", width, 0.05, depth, 0, top - 0.025, 0, M.oak, chamfer: 0.015)
        kit.box("desk beam", width - 0.4, 0.06, 0.08, 0, top - 0.12, 0, M.black)
        let legs = max(2, Int(width / 2.2) + 1)
        for i in 0..<legs {
            let x = -width / 2 + 0.15 + CGFloat(i) * (width - 0.3) / CGFloat(legs - 1)
            for z in [-depth / 2 + 0.12, depth / 2 - 0.12] { kit.box("desk leg", 0.05, top - 0.05, 0.05, x, (top - 0.05) / 2, z, M.black) }
            kit.box("desk foot", 0.06, 0.03, depth - 0.15, x, 0.015, 0, M.black)
        }
        kit.box("cable tray", width - 0.6, 0.05, 0.22, 0, top - 0.2, depth / 2 - 0.2, M.accent(area.accent))
        let spots = area.spots
        for i in 0..<spots {
            let x = -width / 2 + (CGFloat(i) + 0.5) * width / CGFloat(spots)
            // Laptop: the base under the chef's hands, the lid leaning back toward the room.
            kit.box("laptop base", 0.52, 0.025, 0.36, x, top + 0.013, -depth / 2 + 0.36, M.graphite, chamfer: 0.01)
            kit.box("laptop keys", 0.44, 0.004, 0.16, x, top + 0.027, -depth / 2 + 0.32, M.black, chamfer: 0)
            let lid = SCNNode(); lid.name = "laptop lid"
            lid.position = SCNVector3(x, top + 0.025, -depth / 2 + 0.54); lid.eulerAngles.x = 0.22
            root.addChildNode(lid)
            kit.box("laptop shell", 0.52, 0.34, 0.018, 0, 0.17, 0, M.graphite, chamfer: 0.01, in: lid)
            let screen = SCNPlane(width: 0.47, height: 0.29)
            screen.materials = [M.glow(NSColor(srgbRed: 0.16, green: 0.20, blue: 0.28, alpha: 1), strength: 0.4)]
            let face = SCNNode(geometry: screen); face.name = "desk screen#\(i)"
            face.position = SCNVector3(0, 0.17, -0.0095); face.eulerAngles.y = .pi
            lid.addChildNode(face)
            let logo = kit.cylinder("desk logo#\(i)", 0.035, 0.004, 0, 0.19, 0.0095, M.glow(NSColor(white: 0.85, alpha: 1), strength: 0.2), segments: 16, in: lid)
            logo.eulerAngles.x = .pi / 2
            switch i % 3 {
            case 0: kit.cylinder("mug", 0.055, 0.11, x + 0.42, top + 0.055, 0.1, M.accent([OfficeLayout.peach, OfficeLayout.mint, OfficeLayout.butter][i % 3]))
            case 1: kit.plant(x + 0.45, 0.2, height: 0.5, base: top, seed: i)
            default:
                kit.cylinder("lamp base", 0.08, 0.02, x + 0.45, top + 0.01, 0.15, M.black)
                kit.cylinder("lamp arm", 0.012, 0.42, x + 0.45, top + 0.22, 0.15, M.black, segments: 8)
                kit.cone("lamp shade", top: 0.05, bottom: 0.11, 0.12, x + 0.45, top + 0.45, 0.15, M.accent(OfficeLayout.butter))
            }
        }
        return root
    }

    /// The server rack: graphite cabinets with a row of status lights per chef facing the room
    /// (blinking while that chef's command runs, `RackLights`), and a terminal on top facing the chef.
    private static func serverRack(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        kit.box("rack cabinet", width - 0.06, top - 0.04, depth - 0.08, 0, (top - 0.04) / 2, 0, M.graphite)
        kit.box("rack top", width, 0.04, depth, 0, top - 0.02, 0, M.black, chamfer: 0.01)
        let spots = area.spots, bay = width / CGFloat(spots)
        for i in 0..<spots {
            let x = -width / 2 + (CGFloat(i) + 0.5) * bay
            kit.box("rack door", bay - 0.06, top - 0.16, 0.02, x, (top - 0.04) / 2, depth / 2 - 0.03, M.black)
            for row in 0..<5 { kit.box("rack vent", bay - 0.3, 0.012, 0.01, x, 0.15 + CGFloat(row) * 0.06, depth / 2 - 0.018, M.graphite, chamfer: 0) }
            let lights = SCNNode(); lights.name = "rack lights#\(i)"; root.addChildNode(lights)
            for l in 0..<6 {
                kit.box("rack light", 0.05, 0.03, 0.012, x - 0.2 + CGFloat(l) * 0.08, top - 0.14, depth / 2 - 0.012,
                        M.glow(l % 3 == 2 ? OfficeLayout.butter : NSColor(srgbRed: 0.40, green: 0.95, blue: 0.62, alpha: 1), strength: 0.5), chamfer: 0, in: lights)
            }
            // The terminal: a keyboard under the chef's hands and a monitor facing it.
            kit.box("keyboard", 0.44, 0.02, 0.15, x, top + 0.01, -depth / 2 + 0.32, M.white, chamfer: 0.006)
            kit.box("monitor stand", 0.04, 0.26, 0.04, x, top + 0.13, -depth / 2 + 0.66, M.aluminium)
            kit.box("monitor foot", 0.2, 0.012, 0.14, x, top + 0.006, -depth / 2 + 0.66, M.aluminium)
            kit.box("monitor", 0.6, 0.36, 0.03, x, top + 0.38, -depth / 2 + 0.64, M.black, chamfer: 0.01)
            let screen = SCNPlane(width: 0.55, height: 0.31)
            screen.materials = [M.glow(NSColor(srgbRed: 0.08, green: 0.16, blue: 0.12, alpha: 1), strength: 0.6)]
            let face = SCNNode(geometry: screen); face.name = "rack screen#\(i)"
            face.position = SCNVector3(x, top + 0.38, -depth / 2 + 0.624); face.eulerAngles.y = .pi
            root.addChildNode(face)
        }
        // Cables looping between the units along the back.
        for i in 0..<max(1, spots - 1) {
            let cable = kit.cylinder("cable", 0.02, bay * 0.7, -width / 2 + bay * CGFloat(i + 1), top + 0.02, depth / 2 - 0.25,
                                     M.accent([OfficeLayout.sky, OfficeLayout.coral, OfficeLayout.butter][i % 3]), segments: 8)
            cable.eulerAngles.z = .pi / 2
        }
        return root
    }

    /// The QA bench along the right wall: phones and a tablet on stands, a test monitor with a
    /// green check, and a checklist clipboard.
    private static func qaBench(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        credenzaBody(kit, width: width, depth: depth, accent: area.accent)
        let wall = -depth / 2 + 0.05
        let colors = [OfficeLayout.sky, OfficeLayout.mint, OfficeLayout.peach, OfficeLayout.lilac, OfficeLayout.butter]
        let devices = max(3, Int((width - 0.8) / 0.55))
        for i in 0..<devices {
            let x = -width / 2 + 0.5 + CGFloat(i) * (width - 1.0) / CGFloat(devices - 1)
            let tablet = i % 3 == 1
            let w: CGFloat = tablet ? 0.34 : 0.15, h: CGFloat = tablet ? 0.25 : 0.3
            let stand = SCNNode(); stand.name = "device"; stand.position = SCNVector3(x, top, -0.15); stand.eulerAngles.x = -0.25
            root.addChildNode(stand)
            kit.box("device stand", w * 0.8, 0.02, 0.12, 0, 0.01, 0.02, M.aluminium, in: stand)
            kit.box("device body", w, h, 0.015, 0, h / 2 + 0.02, 0, M.black, chamfer: 0.008, in: stand)
            let screen = SCNPlane(width: w - 0.02, height: h - 0.03)
            screen.materials = [M.glow(colors[i % colors.count], strength: 0.55)]
            let face = SCNNode(geometry: screen); face.name = "device screen"; face.position = SCNVector3(0, h / 2 + 0.02, 0.009)
            stand.addChildNode(face)
        }
        // The test monitor on the wall: a big green check.
        let y = top + 0.95
        kit.box("test monitor", 1.1, 0.66, 0.04, 0, y, wall, M.black, chamfer: 0.01)
        kit.box("test screen", 1.02, 0.58, 0.01, 0, y, wall + 0.025, M.glow(NSColor(srgbRed: 0.10, green: 0.16, blue: 0.14, alpha: 1), strength: 0.5), chamfer: 0)
        let check = M.glow(NSColor(srgbRed: 0.40, green: 0.95, blue: 0.55, alpha: 1))
        let short = kit.box("check mark", 0.2, 0.06, 0.01, -0.1, y - 0.05, wall + 0.032, check, chamfer: 0); short.eulerAngles.z = -0.8
        let long = kit.box("check mark", 0.42, 0.06, 0.01, 0.08, y + 0.04, wall + 0.032, check, chamfer: 0); long.eulerAngles.z = 0.85
        for (i, x) in [-width / 2 + 0.35, width / 2 - 0.35].enumerated() {
            kit.box("test bar", 0.5, 0.05, 0.01, 0, y - 0.22 + CGFloat(i) * 0.08, wall + 0.032, M.glow(i == 0 ? OfficeLayout.mint : OfficeLayout.butter, strength: 0.6), chamfer: 0)
            _ = x
        }
        kit.box("clipboard", 0.26, 0.015, 0.34, width / 2 - 0.45, top + 0.008, 0.2, M.oakEdge)
        kit.box("checklist", 0.22, 0.004, 0.28, width / 2 - 0.45, top + 0.017, 0.2, M.paper, chamfer: 0)
        kit.plant(-width / 2 + 0.3, 0.2, height: 0.6, base: top, seed: 3)
        return root
    }

    /// The manager's desk bell on an oak pedestal; it bounces as a chef that needs you reaches it.
    private static func deskBell(_ area: SceneArea) -> SCNNode {
        let (root, kit, _, _) = base(area)
        kit.cylinder("bell pedestal", 0.28, top - 0.03, 0, (top - 0.03) / 2, 0, M.oak)
        kit.cylinder("bell pedestal cap", 0.32, 0.04, 0, top - 0.02, 0, M.white)
        kit.cylinder("bell plinth", 0.3, 0.05, 0, 0.025, 0, M.black)
        let bell = SCNNode(); bell.name = "desk bell"; bell.position = SCNVector3(0, top, 0); root.addChildNode(bell)
        kit.cylinder("bell base", 0.2, 0.04, 0, 0.02, 0, M.black, in: bell)
        let dome = kit.sphere("bell dome", 0.17, 0, 0.05, 0, M.brass, segments: 20, in: bell)
        dome.scale = SCNVector3(1, 0.62, 1)
        kit.cylinder("bell plunger", 0.018, 0.07, 0, 0.18, 0, M.brass, segments: 8, in: bell)
        kit.sphere("bell button", 0.035, 0, 0.225, 0, M.brass, segments: 10, in: bell)
        return root
    }

    /// The demo table: a long white table where finished work waits for review, with a screen at
    /// its end showing the demo.
    private static func demoTable(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        kit.box("table top", width, 0.05, depth, 0, top - 0.025, 0, M.white, chamfer: 0.02)
        kit.box("table runner", width - 0.3, 0.006, 0.36, 0, top + 0.003, 0.1, M.accent(area.accent), chamfer: 0)
        for x in [-width / 2 + 0.25, width / 2 - 0.25] {
            for z in [-depth / 2 + 0.15, depth / 2 - 0.15] { kit.box("table leg", 0.05, top - 0.05, 0.05, x, (top - 0.05) / 2, z, M.aluminium) }
        }
        kit.box("table beam", width - 0.5, 0.05, 0.05, 0, top - 0.1, 0, M.aluminium)
        // The demo screen, facing the room at the table's right end.
        let x = width / 2 - 0.45
        kit.box("screen post", 0.05, 0.6, 0.05, x, top + 0.3, -depth / 2 + 0.15, M.black)
        kit.box("demo screen", 0.86, 0.5, 0.04, x, top + 0.75, -depth / 2 + 0.15, M.black, chamfer: 0.01)
        kit.box("demo slide", 0.8, 0.44, 0.01, x, top + 0.75, -depth / 2 + 0.175, M.glow(NSColor(srgbRed: 0.97, green: 0.95, blue: 0.90, alpha: 1), strength: 0.6), chamfer: 0)
        for (i, color) in [OfficeLayout.coral, OfficeLayout.sky, OfficeLayout.mint].enumerated() {
            let h = 0.1 + CGFloat(i) * 0.07
            kit.box("slide bar", 0.1, h, 0.01, x - 0.2 + CGFloat(i) * 0.15, top + 0.6 + h / 2, -depth / 2 + 0.182, M.glow(color, strength: 0.7), chamfer: 0)
        }
        kit.box("slide title", 0.5, 0.04, 0.01, x, top + 0.9, -depth / 2 + 0.182, M.glow(NSColor(white: 0.3, alpha: 1), strength: 0.5), chamfer: 0)
        return root
    }

    /// The supply closet along the left wall: binders of skills, toolboxes of plugins and
    /// devices for MCP servers (each with a status light) on open shelves over a cabinet.
    private static func supplyCloset(_ area: SceneArea) -> SCNNode {
        let (root, kit, width, depth) = base(area)
        credenzaBody(kit, width: width, depth: depth, accent: area.accent)
        let back = -depth / 2 + 0.1
        kit.box("closet back", width - 0.1, 1.5, 0.05, 0, top + 0.8, back - 0.02, M.white)
        for i in 0...4 {
            let x = -width / 2 + 0.08 + CGFloat(i) * (width - 0.16) / 4
            kit.box("closet upright", 0.06, 1.5, 0.42, x, top + 0.8, back + 0.18, M.oakEdge)
        }
        let shelves: [CGFloat] = [top + 0.6, top + 1.15]
        for y in shelves { kit.box("closet shelf", width - 0.1, 0.04, 0.42, 0, y, back + 0.2, M.oak, chamfer: 0.01) }
        let colors = [OfficeLayout.sky, OfficeLayout.coral, OfficeLayout.mint, OfficeLayout.butter, OfficeLayout.lilac, OfficeLayout.peach]
        // Top shelf: binders of skills, in colour runs.
        let binders = Int((width - 0.4) / 0.11)
        for i in 0..<binders where i % 9 != 8 {
            let x = -width / 2 + 0.25 + CGFloat(i) * 0.11
            let binder = kit.box("skill binder", 0.08, 0.34, 0.28, x, shelves[1] + 0.19, back + 0.2, M.accent(colors[(i / 4) % colors.count]), chamfer: 0.008)
            if i % 9 == 7 { binder.eulerAngles.z = 0.2 }
            kit.box("binder label", 0.05, 0.1, 0.004, x, shelves[1] + 0.22, back + 0.342, M.paper, chamfer: 0)
        }
        // Middle shelf: toolboxes of plugins and cardboard boxes.
        for (i, x) in stride(from: -width / 2 + 0.5, through: width / 2 - 0.5, by: 0.9).enumerated() {
            if i % 3 == 2 {
                kit.box("cardboard box", 0.5, 0.32, 0.36, x, shelves[0] + 0.18, back + 0.2, M.matte(NSColor(srgbRed: 0.78, green: 0.62, blue: 0.42, alpha: 1), roughness: 0.95))
            } else {
                kit.box("plugin toolbox", 0.56, 0.24, 0.3, x, shelves[0] + 0.14, back + 0.2, M.accent(i % 2 == 0 ? OfficeLayout.coral : OfficeLayout.sky), chamfer: 0.03)
                kit.box("toolbox handle", 0.3, 0.04, 0.04, x, shelves[0] + 0.3, back + 0.2, M.black)
            }
        }
        // Worktop: devices for MCP servers, each with a green status light, and a label printer.
        let light = M.glow(NSColor(srgbRed: 0.40, green: 0.95, blue: 0.62, alpha: 1))
        for (i, x) in [-width * 0.32, 0, width * 0.32].enumerated() {
            kit.box("mcp device", 0.46, 0.12, 0.32, x, top + 0.06, back + 0.42, i == 1 ? M.accent(OfficeLayout.lilac) : M.white, chamfer: 0.03)
            for side in [-1.0, 1.0] as [CGFloat] {
                let antenna = kit.cylinder("mcp antenna", 0.012, 0.26, x + side * 0.18, top + 0.24, back + 0.3, M.black, segments: 6)
                antenna.eulerAngles.z = side * 0.25
            }
            kit.sphere("mcp device light", 0.025, x + 0.15, top + 0.09, back + 0.585, light, segments: 8)
        }
        kit.box("label printer", 0.3, 0.14, 0.24, width / 2 - 0.45, top + 0.07, back + 0.5, M.graphite, chamfer: 0.02)
        return root
    }
}

/// Modelled office fixtures (`Resources/OfficeStations/<area>.glb`, built by assets/office/build.sh),
/// each a root named after its station, already at its footprint's position; nil when not bundled.
@MainActor enum OfficeFixtures {
    private static let models: [String: SCNNode] = KitchenFood.models(in: "OfficeStations")
    static func make(_ area: SceneArea) -> SCNNode? {
        guard let template = models[area.id] else { return nil }
        let root = SCNNode(); root.name = area.id
        root.position = SCNVector3(area.footprint.midX, ChefMetrics.floorTop, area.footprint.midY)
        if area.wall == .left { root.eulerAngles.y = .pi / 2 }
        if area.wall == .right { root.eulerAngles.y = -.pi / 2 }
        for child in template.clone().childNodes { root.addChildNode(child) }
        return root
    }
}
