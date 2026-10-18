import AppKit
import SceneKit
import simd

/// The office's room: a light oak floor, a floor-to-ceiling window wall at the back onto the city,
/// low glass rails at the sides (the front stays open to the lobby), white cabinets between the
/// wall stations, the lounge's low planter walls and rug, and plants.
@MainActor enum OfficeRoomGeometry {
    private typealias M = OfficeMaterials

    static func make(_ layout: SceneLayout) -> [SCNNode] {
        let floor = layout.floor
        let slab = SCNBox(width: floor.width, height: 0.224, length: floor.height, chamferRadius: 0.02)
        slab.materials = [plankMaterial(floor), M.oakEdge, M.oakEdge, M.oakEdge, plankMaterial(floor), M.oakEdge]
        let floorNode = SCNNode(geometry: slab); floorNode.name = "Office floor"
        let room = SCNNode(); room.name = "office-room"
        let kit = OfficeBuilder(room)
        let top = OfficeStationGeometry.top + ChefMetrics.floorTop
        // Cabinets that close the gaps between wall stations, at worktop height.
        for (i, r) in layout.connectors.enumerated() {
            kit.box("connecting cabinet", r.width - 0.08, top - ChefMetrics.floorTop - 0.05, r.height - 0.08, r.midX, (top + ChefMetrics.floorTop - 0.05) / 2, r.midY, M.white)
            kit.box("connecting top", r.width, 0.05, r.height, r.midX, top - 0.025, r.midY, M.oak, chamfer: 0.015)
            if r.width * r.height > 2 { kit.plant(r.midX, r.midY, height: 0.9, base: top, seed: i) }
        }
        // The window wall: a sill, tall glass in black mullions, a beam on top.
        let back = floor.minY + 0.13
        kit.box("window sill", floor.width, 0.36, 0.24, floor.midX, ChefMetrics.floorTop + 0.18, back, M.white)
        kit.box("window glass", floor.width - 0.1, 2.5, 0.03, floor.midX, ChefMetrics.floorTop + 0.36 + 1.25, back, M.glass(transparency: 0.22))
        kit.box("window beam", floor.width, 0.14, 0.26, floor.midX, ChefMetrics.floorTop + 2.93, back, M.black)
        for x in stride(from: floor.minX + 0.03, through: floor.maxX - 0.03, by: floor.width / 16) {
            kit.box("window mullion", 0.06, 2.6, 0.09, x, ChefMetrics.floorTop + 1.6, back, M.black, chamfer: 0.005)
        }
        // Low glass rails along the sides, with an oak handrail.
        for x in [floor.minX + 0.12, floor.maxX - 0.12] {
            kit.box("side rail glass", 0.03, 0.62, floor.height - 0.4, x, ChefMetrics.floorTop + 0.36, floor.midY, M.glass(transparency: 0.25))
            kit.box("side rail top", 0.08, 0.05, floor.height - 0.3, x, ChefMetrics.floorTop + 0.7, floor.midY, M.oak)
            kit.box("side rail base", 0.12, 0.08, floor.height - 0.3, x, ChefMetrics.floorTop + 0.04, floor.midY, M.black)
        }
        // The lounge: low white walls topped with planters, a rug, and a big plant by the doorway.
        for wall in layout.partitionWalls {
            kit.box("lounge wall", wall.width, 0.9, wall.height, wall.midX, ChefMetrics.floorTop + 0.45, wall.midY, M.white)
            kit.box("lounge planter", wall.width + 0.06, 0.12, wall.height + 0.12, wall.midX, ChefMetrics.floorTop + 0.96, wall.midY, M.oak)
            let along = wall.width > wall.height
            let length = along ? wall.width : wall.height
            for i in 0..<Int(length / 0.32) {
                let t = -length / 2 + 0.16 + CGFloat(i) * 0.32
                kit.sphere("planter leaves", 0.15 + CGFloat(i % 3) * 0.02, wall.midX + (along ? t : 0), ChefMetrics.floorTop + 1.07, wall.midY + (along ? 0 : t),
                           i % 2 == 0 ? M.leaf : M.leafLight, segments: 8)
            }
        }
        let rug = layout.restSign
        kit.box("lounge rug", rug.width, 0.012, rug.height, rug.midX, ChefMetrics.floorTop + 0.006, rug.midY, M.matte(NSColor(srgbRed: 0.86, green: 0.82, blue: 0.90, alpha: 1), roughness: 0.98), chamfer: 0.004)
        kit.box("lounge rug border", rug.width + 0.16, 0.008, rug.height + 0.16, rug.midX, ChefMetrics.floorTop + 0.004, rug.midY, M.matte(OfficeLayout.lilac, roughness: 0.98), chamfer: 0.004)
        // Plants in the open corners.
        for (i, spot) in [(floor.minX + 0.6, floor.minY + 2.4), (floor.maxX - 0.6, floor.maxY - 0.5), (floor.minX + 0.7, floor.maxY - 0.6), (-3.0, floor.maxY - 0.5)].enumerated() {
            kit.plant(spot.0, spot.1, height: 1.5, base: ChefMetrics.floorTop, pot: i % 2 == 0 ? M.white : M.terracotta, seed: i)
        }
        return [floorNode, room]
    }

    /// Light oak planks running across the room, drawn once.
    private static func plankMaterial(_ floor: CGRect) -> SCNMaterial {
        let material = OfficeMaterials.matte(.white, roughness: 0.55)
        material.diffuse.contents = planks
        material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(floor.width / 4, floor.height / 4, 1)
        return material
    }
    private static let planks: NSImage = {
        let side: CGFloat = 512
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        var random = SplitMix(seed: 0x0A4)
        let rows = 8, rowHeight = side / CGFloat(rows)
        for row in 0..<rows {
            var x = -CGFloat(random.next(in: 0...200))
            while x < side {
                let length = CGFloat(random.next(in: 180...340))
                let tone = random.next(in: -0.035...0.035)
                NSColor(srgbRed: 0.86 + tone, green: 0.73 + tone, blue: 0.55 + tone * 0.8, alpha: 1).setFill()
                NSRect(x: x, y: CGFloat(row) * rowHeight, width: length, height: rowHeight).fill()
                // Fine grain.
                for g in 0..<4 {
                    NSColor(srgbRed: 0.70, green: 0.56, blue: 0.40, alpha: 0.12).setFill()
                    NSRect(x: x, y: CGFloat(row) * rowHeight + CGFloat(g + 1) * rowHeight / 5 + CGFloat(random.next(in: -3...3)), width: length, height: 1).fill()
                }
                NSColor(srgbRed: 0.62, green: 0.48, blue: 0.33, alpha: 0.55).setFill()
                NSRect(x: x, y: CGFloat(row) * rowHeight, width: 1.5, height: rowHeight).fill()
                x += length
            }
            NSColor(srgbRed: 0.62, green: 0.48, blue: 0.33, alpha: 0.5).setFill()
            NSRect(x: 0, y: CGFloat(row) * rowHeight, width: side, height: 1.5).fill()
        }
        image.unlockFocus()
        return image
    }()
}

/// The client lobby around the office and the city beyond the windows. Clients sit at café
/// tables along both sides of the floor, where the home camera sees them, at the same spots as
/// the restaurant's diners (`assets/restaurant`): seats 0.64 high fit the chef rig's `sit_*`
/// clips, tables 0.98 high. A modelled lobby (`Resources/OfficeLobby/lobby.glb` with the same
/// `seat_NN`/`dish_NN` anchors) replaces this one when bundled.
@MainActor final class OfficeLobby: SceneSurroundings {
    static let shared = OfficeLobby()
    let template: SCNNode
    let seats: [SceneSeat]
    private typealias M = OfficeMaterials

    init() {
        if let modelled = try? KitchenRestaurant(roots: GLBStaticMeshes.load("lobby", subdirectory: "OfficeLobby").mapKeys { $0 == "lobby" ? "restaurant" : $0 }) {
            template = modelled.template; seats = modelled.seats; return
        }
        let root = SCNNode(); root.name = "lobby"
        let kit = OfficeBuilder(root)
        let ground: CGFloat = 0.02
        // Polished concrete under everything, and the city beyond the back windows.
        kit.box("lobby floor", 44, 0.04, 34, 0, 0, 2, M.matte(NSColor(srgbRed: 0.84, green: 0.82, blue: 0.78, alpha: 1), roughness: 0.4), chamfer: 0)
        root.addChildNode(Self.skyline())
        // Café tables along both sides, chairs at the front and back of each so faces show.
        var stands: [(SIMD2<Float>, SIMD3<Float>)] = []
        let chairColors = [OfficeLayout.sky, OfficeLayout.peach, OfficeLayout.mint, OfficeLayout.lilac, OfficeLayout.butter, OfficeLayout.coral]
        for (t, (x, z)) in [(13.6, -4.5), (13.6, -0.8), (13.6, 2.9), (-13.6, -4.5), (-13.6, -0.8), (-13.6, 2.9)].enumerated() {
            kit.cylinder("table foot", 0.32, 0.05, x, ground + 0.025, z, M.black)
            kit.cylinder("table stem", 0.05, 0.9, x, ground + 0.48, z, M.black, segments: 10)
            kit.cylinder("table top", 0.62, 0.05, x, ground + 0.955, z, M.white, segments: 28)
            for side in [-1.0, 1.0] as [CGFloat] {
                let chairZ = z + side * 0.98, chair = M.accent(chairColors[(t * 2 + (side > 0 ? 1 : 0)) % chairColors.count])
                kit.box("chair seat", 0.52, 0.07, 0.5, x, ground + 0.605, chairZ, chair, chamfer: 0.03)
                kit.box("chair back", 0.48, 0.5, 0.06, x, ground + 0.9, chairZ + side * 0.24, chair, chamfer: 0.03)
                for dx in [-0.21, 0.21] as [CGFloat] { for dz in [-0.19, 0.19] as [CGFloat] {
                    kit.box("chair leg", 0.04, 0.57, 0.04, x + dx, ground + 0.285, chairZ + dz, M.black, chamfer: 0.005)
                } }
                stands.append((SIMD2(Float(x), Float(z + side * 0.87)), SIMD3(Float(x), Float(ground + 0.98), Float(z + side * 0.3))))
            }
            kit.plant(x + (x > 0 ? 1.1 : -1.1), z + 1.8, height: 1.3, base: ground, pot: t % 2 == 0 ? M.white : M.terracotta, seed: t)
        }
        // A reception desk and sofas out front, beside the lobby door.
        kit.box("reception desk", 3.4, 1.0, 0.9, -6.5, ground + 0.5, 11.2, M.white, chamfer: 0.06)
        kit.box("reception top", 3.5, 0.05, 1.0, -6.5, ground + 1.02, 11.2, M.oak, chamfer: 0.02)
        kit.box("reception band", 3.42, 0.16, 0.02, -6.5, ground + 0.62, 11.66, M.accent(OfficeLayout.sage))
        for x in [6.2, 9.2] as [CGFloat] {
            kit.box("sofa base", 2.2, 0.42, 0.9, x, ground + 0.21, 11.4, M.accent(OfficeLayout.sky), chamfer: 0.12)
            kit.box("sofa back", 2.2, 0.5, 0.25, x, ground + 0.62, 11.75, M.accent(OfficeLayout.sky), chamfer: 0.1)
        }
        kit.plant(-9, 10.6, height: 1.6, base: ground, pot: M.terracotta, seed: 4)
        kit.plant(11.4, 10.6, height: 1.6, base: ground, seed: 5)
        template = root
        // Nearest the demo table first, as the restaurant numbers them.
        seats = stands.sorted { simd_length_squared($0.0 - SIMD2(6.9, 7.0)) < simd_length_squared($1.0 - SIMD2(6.9, 7.0)) }
            .enumerated().map { SceneSeat(id: String(format: "%02d", $0.offset + 1), stand: $0.element.0, dish: $0.element.1) }
    }

    func make() -> SCNNode { template.clone() }

    /// Towers beyond the window wall at golden hour: warm stone, lavender and slate, their windows
    /// lit amber, receding into a haze.
    private static func skyline() -> SCNNode {
        let city = SCNNode(); city.name = "skyline"
        let kit = OfficeBuilder(city)
        var random = SplitMix(seed: 0xC17)
        let tones = [NSColor(srgbRed: 0.80, green: 0.68, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.66, green: 0.62, blue: 0.74, alpha: 1),
                     NSColor(srgbRed: 0.56, green: 0.60, blue: 0.70, alpha: 1), NSColor(srgbRed: 0.88, green: 0.76, blue: 0.64, alpha: 1)]
        let facades = tones.map(facade)
        for row in 0..<3 {
            let z = -19.0 - Double(row) * 9
            var x = -40.0 + random.next(in: 0...3)
            while x < 40 {
                let w = random.next(in: 3...6), d = random.next(in: 3...5)
                let h = random.next(in: 3...7) + Double(row) * 5 + (abs(x) < 10 ? random.next(in: 0...5) : 0)
                let tower = kit.box("tower", CGFloat(w), CGFloat(h), CGFloat(d), CGFloat(x + w / 2), CGFloat(h / 2), CGFloat(z - d / 2),
                                    facades[Int(random.next() % UInt64(facades.count))], chamfer: 0)
                tower.castsShadow = false
                if random.next(in: 0...1) < 0.3 {
                    kit.box("tower crown", CGFloat(w * 0.6), 0.8, CGFloat(d * 0.6), CGFloat(x + w / 2), CGFloat(h + 0.4), CGFloat(z - d / 2), facades[0], chamfer: 0).castsShadow = false
                }
                x += w + random.next(in: 0.4...1.6)
            }
        }
        return city
    }
    /// A facade: rows of windows, some lit.
    private static func facade(_ tone: NSColor) -> SCNMaterial {
        let image = NSImage(size: NSSize(width: 128, height: 256))
        image.lockFocus()
        tone.setFill(); NSRect(x: 0, y: 0, width: 128, height: 256).fill()
        var random = SplitMix(seed: UInt64(tone.redComponent * 1000))
        for row in 0..<16 { for column in 0..<6 {
            let lit = random.next(in: 0...1) < 0.35
            (lit ? NSColor(srgbRed: 1, green: 0.84, blue: 0.55, alpha: 1) : tone.blended(withFraction: 0.35, of: NSColor(srgbRed: 0.25, green: 0.27, blue: 0.36, alpha: 1)) ?? tone).setFill()
            NSRect(x: 8 + CGFloat(column) * 20, y: 6 + CGFloat(row) * 16, width: 13, height: 9).fill()
        } }
        image.unlockFocus()
        let material = OfficeMaterials.matte(.white, roughness: 0.8)
        material.diffuse.contents = image
        material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 2, 1)
        material.emission.contents = image; material.emission.intensity = 0.25
        return material
    }
}

private extension Dictionary {
    func mapKeys(_ transform: (Key) -> Key) -> [Key: Value] { Dictionary(uniqueKeysWithValues: map { (transform($0.key), $0.value) }) }
}
