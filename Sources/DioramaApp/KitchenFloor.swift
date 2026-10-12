import AppKit
import SceneKit

/// The kitchen's floor: French limestone octagons set with blue-grey clover cabochons, framed by
/// a border band with an interlaced rope, like an old Paris hôtel's kitchen. Textures come from
/// `assets/kitchen/floor/make_floor.py`; if they're missing the floor is plain stone. The break
/// room is a salon instead: oak parquet laid point de Hongrie, with a green wool rug under the
/// lounge chairs (`make_lounge.py`).
@MainActor enum KitchenFloor {
    /// One limestone tile, in kitchen units (a chef is about 2.7 tall).
    static let tile: CGFloat = 0.8
    /// The border band's width; its texture repeats every two stones along its length.
    static let band: CGFloat = 0.8
    /// The floor's top, where the oak boards' top was.
    static let top: CGFloat = 0.119
    private static let thickness: CGFloat = 0.018

    static func make() -> SCNNode {
        let root = SCNNode(); root.name = "kitchen floor stone"
        // Limestone everywhere inside the back wall and the low side walls.
        slab(inner, material("floor_field", repeat: (inner.width / (tile * 4), inner.height / (tile * 4))), in: root, name: "stone field", lift: 0)
        // The border, laid like a rug's edge along the furniture around the kitchen.
        let (runs, corners) = borderLayout()
        for run in runs {
            let sideways = run.height > run.width
            let length = sideways ? run.height : run.width
            slab(run, material("floor_border", repeat: (length / (band * 2), 1)), in: root, name: "stone border", sideways: sideways, lift: 0.0015)
        }
        let corner = material("floor_border", repeat: (0.5, 1))
        for square in corners {
            slab(CGRect(x: square.x, y: square.y, width: band, height: band), corner, in: root, name: "stone border corner", lift: 0.002)
        }
        let lounge = breakRoom
        slab(lounge, material("floor_parquet", repeat: (lounge.width / parquet.width, lounge.height / parquet.height), roughness: 0.45),
             in: root, name: "break room parquet", lift: 0.001)
        slab(rug, material("floor_rug", repeat: (1, 1), roughness: 0.95), in: root, name: "break room rug", lift: 0.006)
        return root
    }

    /// The break room's floor, inside its low walls: x/z from the left wall to the short wall,
    /// and from the long wall to the open front.
    static var breakRoom: CGRect {
        guard let long = KitchenLayout.breakRoomWalls.first, let short = KitchenLayout.breakRoomWalls.last else { return .zero }
        return CGRect(x: inner.minX, y: long.maxY, width: short.minX - inner.minX, height: inner.maxY - long.maxY)
    }
    /// One repeat of the parquet texture: two chevron columns, four plank strides (make_lounge.py).
    static let parquet = CGSize(width: 8 * 0.11 * 2.squareRoot(), height: 4 * 0.11 * 2.squareRoot())
    /// The rug (make_lounge.py's RUG_W x RUG_H): under the standing circles and the lounge chairs,
    /// clear of the machines along the far and left walls.
    static let rug = CGRect(x: -10.6, y: 4.5, width: 6.8, height: 3.3)

    /// The floor inside the back wall and the low side walls (open at the front).
    static var inner: CGRect {
        let floor = KitchenLayout.floor
        return CGRect(x: floor.minX + 0.28, y: floor.minY + 0.24, width: floor.width - 0.56, height: floor.height - 0.24)
    }
    /// The border's runs (x/z rects) and the corners where they turn (each corner square's
    /// minimum x/z). It follows the open floor's edge: in front of the back counters and the
    /// elevator, the tasting side, around the serving window, along the open front, around the
    /// break room's walls, and against the left wall behind the pantry.
    static func borderLayout() -> (runs: [CGRect], corners: [CGPoint]) {
        let areas = Dictionary(uniqueKeysWithValues: KitchenLayout.areas.map { ($0.id, $0.footprint) })
        guard let order = areas["order"], let elevator = areas["elevator"],
              let tasting = areas["tasting"], let serving = areas["serving"],
              let breakTop = KitchenLayout.breakRoomWalls.first, let breakSide = KitchenLayout.breakRoomWalls.last else { return ([], []) }
        let b = band
        let back = order.maxY                       // front of the back counters
        let left = inner.minX                       // the left wall (the pantry stands on the border)
        let right = tasting.minX                    // front of the tasting side
        let breakFront = breakTop.minY              // kitchen side of the break room's long wall
        let breakEdge = breakSide.maxX              // kitchen side of its short wall
        let front = KitchenLayout.floor.maxY        // the open front edge
        let serveFront = serving.minY, serveLeft = serving.minX
        let runs = [
            // In front of the back counters, from the elevator to the tasting side.
            CGRect(x: elevator.maxX, y: back, width: right - b - elevator.maxX, height: b),
            // Down the tasting side to the serving window.
            CGRect(x: right - b, y: back + b, width: b, height: serveFront - b - back - b),
            // In front of the serving window, then down its left end to the open front.
            CGRect(x: serveLeft, y: serveFront - b, width: right - b - serveLeft, height: b),
            CGRect(x: serveLeft - b, y: serveFront, width: b, height: front - b - serveFront),
            // Along the open front to the break room.
            CGRect(x: breakEdge + b, y: front - b, width: serveLeft - b - breakEdge - b, height: b),
            // Up the break room's short wall, along its long wall, and up the left wall.
            CGRect(x: breakEdge, y: breakFront, width: b, height: front - b - breakFront),
            CGRect(x: left + b, y: breakFront - b, width: breakEdge - left - b, height: b),
            CGRect(x: left, y: elevator.maxY, width: b, height: breakFront - b - elevator.maxY),
        ]
        let corners = [
            CGPoint(x: right - b, y: back), CGPoint(x: right - b, y: serveFront - b),
            CGPoint(x: serveLeft - b, y: serveFront - b), CGPoint(x: serveLeft - b, y: front - b),
            CGPoint(x: breakEdge, y: front - b), CGPoint(x: breakEdge, y: breakFront - b),
            CGPoint(x: left, y: breakFront - b),
        ]
        return (runs, corners)
    }

    /// A thin slab over `rect` (x/z on the floor) with its top at `top`. `sideways` turns the
    /// texture's length along z.
    private static func slab(_ rect: CGRect, _ material: SCNMaterial, in parent: SCNNode, name: String, sideways: Bool = false, lift: CGFloat) {
        let (w, d) = sideways ? (rect.height, rect.width) : (rect.width, rect.height)
        let box = SCNBox(width: w, height: thickness, length: d, chamferRadius: 0)
        box.materials = [material]
        let node = SCNNode(geometry: box); node.name = name
        node.position = SCNVector3(rect.midX, top - thickness / 2 + lift, rect.midY)
        if sideways { node.eulerAngles.y = .pi / 2 }
        parent.addChildNode(node)
    }

    private static var images: [String: NSImage] = [:]
    private static func image(_ name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        let found = WorkspaceCapybaraAsset.resourceBundle.url(forResource: name, withExtension: "jpg", subdirectory: "KitchenStations").flatMap(NSImage.init(contentsOf:))
        images[name] = found
        return found
    }

    private static func material(_ texture: String, repeat count: (CGFloat, CGFloat), roughness: CGFloat = 0.58) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.roughness.contents = roughness                              // honed limestone by default
        if let color = image(texture) {
            m.diffuse.contents = color
            m.normal.contents = image(texture + "_normal")
            m.normal.intensity = 0.8
            let scale = SCNMatrix4MakeScale(count.0, count.1, 1)
            for property in [m.diffuse, m.normal] {
                property.contentsTransform = scale
                property.wrapS = .repeat; property.wrapT = .repeat
                property.mipFilter = .linear; property.maxAnisotropy = 8
            }
        } else {
            m.diffuse.contents = NSColor(red: 0.86, green: 0.82, blue: 0.72, alpha: 1)
        }
        return m
    }
}
