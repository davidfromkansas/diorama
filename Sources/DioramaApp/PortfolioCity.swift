import SwiftUI
import DioramaCore

/// Building proportions for the home city layout. Footprint follows how many conversations a
/// project has; height follows reported all-time tokens on a log scale so one large project
/// cannot dwarf the rest. Every building shares one scale, so sizes compare across tiles.
struct PortfolioBuildingMetrics: Equatable {
    static let maxFloors = 9
    var width: Int
    var depth: Int
    var floors: Int
    init(width: Int, depth: Int, floors: Int) { self.width = width; self.depth = depth; self.floors = floors }
    init(conversations: Int, tokens: Int64?) {
        switch conversations {
        case ..<3: (width, depth) = (2, 2)
        case ..<6: (width, depth) = (3, 2)
        case ..<10: (width, depth) = (3, 3)
        case ..<20: (width, depth) = (4, 3)
        default: (width, depth) = (4, 4)
        }
        guard let tokens, tokens > 0 else { floors = 2; return }
        // 1K → 2 floors, 1M → 5, 1B → 8.
        floors = min(Self.maxFloors, max(2, Int(log10(Double(tokens))) - 1))
    }
    /// Height of the main mass in lot units; roofs, crowns and spires sit above it. The base keeps
    /// low-rises readable next to towers while taller still means bigger.
    var height: Double { 3 + Double(floors) * 1.15 }
    var isTower: Bool { floors > 3 }
}

/// New York silhouettes, each a hand-written recipe. Small projects take a low-rise and larger
/// ones a landmark tower, chosen from the project ID so a project keeps its building.
enum PortfolioBuildingStyle: CaseIterable {
    case walkup, brownstone, twinTanks, castIronLoft, tenement, cornerShop, mansardHotel, rooftopGarden, decoLowRise, theater, chapel, glassStudio
    case empire, chrysler, woolworth, rockefeller, glassCurtain, freedom, pencil, plaza, municipal, weddingCake, citicorp, hearst

    static let lowRises: [Self] = [.walkup, .brownstone, .twinTanks, .castIronLoft, .tenement, .cornerShop, .mansardHotel, .rooftopGarden, .decoLowRise, .theater, .chapel, .glassStudio]
    static let towers: [Self] = [.empire, .chrysler, .woolworth, .rockefeller, .glassCurtain, .freedom, .pencil, .plaza, .municipal, .weddingCake, .citicorp, .hearst]
    static func of(projectID: String, metrics: PortfolioBuildingMetrics) -> Self {
        let options = metrics.isTower ? towers : lowRises
        return options[Int(PortfolioBuilding.hash(projectID, 0) % UInt64(options.count))]
    }
}

/// Building materials as their colour in neutral daylight; the drawing applies the light.
enum PortfolioMaterial {
    case stone, cream, brick, sootBrick, brownstone, castIron, painted, glass, darkGlass, metal, copper, slate, garden, wood, signal
    var rgb: SIMD3<Double> {
        switch self {
        case .stone: SIMD3(0.84, 0.80, 0.72) // Indiana limestone
        case .cream: SIMD3(0.90, 0.82, 0.66) // glazed terracotta
        case .brick: SIMD3(0.66, 0.33, 0.24)
        case .sootBrick: SIMD3(0.48, 0.29, 0.23)
        case .brownstone: SIMD3(0.47, 0.32, 0.25)
        case .castIron: SIMD3(0.80, 0.78, 0.72) // painted SoHo cast iron
        case .painted: SIMD3(0.72, 0.80, 0.72)
        case .glass: SIMD3(0.56, 0.69, 0.80)
        case .darkGlass: SIMD3(0.30, 0.38, 0.46)
        case .metal: SIMD3(0.78, 0.80, 0.82) // stainless and aluminium
        case .copper: SIMD3(0.42, 0.64, 0.56) // weathered copper patina
        case .slate: SIMD3(0.36, 0.38, 0.42)
        case .garden: SIMD3(0.40, 0.60, 0.30)
        case .wood: SIMD3(0.55, 0.40, 0.28) // cedar water tank
        case .signal: SIMD3(0.78, 0.18, 0.16)
        }
    }
    var isGlass: Bool { self == .glass || self == .darkGlass }
}

enum PortfolioWindows { case strips, wide, grid, bands, none }
enum PortfolioRoof: Equatable { case flat, pyramid(Double), mansard(Double), dome, gable(Double), slant(Double) }

/// Isometric boxes, roof and rooftop details for one building, in lot units.
struct PortfolioMassing {
    struct Box {
        var x0, y0, x1, y1, z0, z1: Double
        var material: PortfolioMaterial
        var windows: PortfolioWindows
        var cornice = false
        var width: Double { x1 - x0 }
        var depth: Double { y1 - y0 }
    }
    var boxes: [Box] = []
    var roof = PortfolioRoof.flat
    var roofMaterial = PortfolioMaterial.copper
    var spire: Double?
    var antennas = 0
    /// Positions as fractions of the roof.
    var waterTowers: [SIMD2<Double>] = []
    var chimneys: [Double] = []
    var bulkhead = false
    var garden = false
    var awning: PortfolioMaterial?
    var fireEscape = false

    static let waterTowerHeight = 2.3
    static let antennaHeight = 1.4
    var roofRise: Double {
        switch roof {
        case .flat: 0
        case .pyramid(let rise), .mansard(let rise), .gable(let rise), .slant(let rise): rise
        case .dome: domeRadius * 0.95
        }
    }
    var domeRadius: Double { boxes.last.map { min($0.width, $0.depth) / 2 } ?? 0 }
    /// The highest point drawn above the roof's centre, where a warning light or map pin sits.
    var peak: SIMD3<Double> {
        guard let roof = boxes.last else { return .zero }
        var z = roof.z1 + roofRise
        if !waterTowers.isEmpty { z = max(z, roof.z1 + Self.waterTowerHeight) }
        if let spire { z = max(z, roof.z1 + roofRise + spire) }
        if antennas > 0 { z = max(z, roof.z1 + Self.antennaHeight) }
        return SIMD3((roof.x0 + roof.x1) / 2, (roof.y0 + roof.y1) / 2, z)
    }

    /// Height on screen, in lot units, from the plot's front corner to the highest point drawn.
    /// The back corner of a roof sits higher on screen than its centre, so both are measured.
    var extent: Double {
        let front = 2 * Self.slab
        func height(_ x: Double, _ y: Double, _ z: Double) -> Double { (front - x - y) * 0.5 + z }
        var result = boxes.map { height($0.x0, $0.y0, $0.z1) }.max() ?? 0
        guard let roof = boxes.last else { return result }
        let cx = (roof.x0 + roof.x1) / 2, cy = (roof.y0 + roof.y1) / 2, t = roof.z1
        switch self.roof {
        case .flat, .pyramid, .dome: break
        case .mansard(let up):
            let m = min(roof.width, roof.depth) * 0.22
            result = max(result, height(roof.x0 + m, roof.y0 + m, t + up))
        case .gable(let up): result = max(result, height(roof.x0, cy, t + up))
        case .slant(let up): result = max(result, height(roof.x0, roof.y0, t + up))
        }
        result = max(result, height(cx, cy, t + roofRise + max(spire ?? 0, antennas > 0 ? Self.antennaHeight : 0)))
        if bulkhead || !chimneys.isEmpty { result = max(result, height(roof.x0, roof.y0, t + 0.7)) }
        for at in waterTowers {
            result = max(result, height(roof.x0 + roof.width * at.x, roof.y0 + roof.depth * at.y, t + Self.waterTowerHeight))
        }
        return result
    }

    /// Widens footprints relative to height so buildings fill a short, wide tile.
    static let footprintScale = 1.5
    /// Paving between a building and the curb.
    static let margin = 0.35
    /// Every building stands on a city block of the same size, centred, so tiles line up.
    static let block = 4 * footprintScale + 2 * margin
    static let street = 1.5
    /// The diorama slab: the block, the two streets in front of it, and the far curbs.
    static let slab = block + street + 0.4

    init(_ style: PortfolioBuildingStyle, metrics: PortfolioBuildingMetrics) {
        let w = Double(metrics.width) * Self.footprintScale, d = Double(metrics.depth) * Self.footprintScale, h = metrics.height
        let x0 = (Self.block - w) / 2, y0 = (Self.block - d) / 2
        // Setbacks scale with the footprint, so narrow towers stay buildable.
        let scale = min(w, d) / 4
        func tier(_ inset: Double, _ z0: Double, _ z1: Double, _ material: PortfolioMaterial, _ windows: PortfolioWindows,
                  depth: Double? = nil, cornice: Bool = false) -> Box {
            let ix = inset * scale, iy = (depth ?? inset) * scale
            return Box(x0: x0 + ix, y0: y0 + iy, x1: x0 + w - ix, y1: y0 + d - iy, z0: z0, z1: z1, material: material, windows: windows, cornice: cornice)
        }
        switch style {
        // Low-rises
        case .walkup:
            boxes = [tier(0, 0, h, .brick, .strips, cornice: true)]
            waterTowers = [SIMD2(0.3, 0.3)]; fireEscape = true
        case .brownstone:
            boxes = [tier(0, 0, h, .brownstone, .strips, cornice: true)]
            chimneys = [0.2, 0.75]
        case .twinTanks:
            boxes = [tier(0, 0, h, .cream, .strips, cornice: true)]
            waterTowers = [SIMD2(0.25, 0.25), SIMD2(0.72, 0.3)]
        case .castIronLoft:
            boxes = [tier(0, 0, h, .castIron, .wide, cornice: true)]
            bulkhead = true
        case .tenement:
            boxes = [tier(0, 0, h, .sootBrick, .strips, cornice: true)]
            fireEscape = true; bulkhead = true; waterTowers = [SIMD2(0.28, 0.6)]
        case .cornerShop:
            boxes = [tier(0, 0, h, .painted, .strips, cornice: true)]
            awning = .garden; waterTowers = [SIMD2(0.3, 0.3)]
        case .mansardHotel:
            boxes = [tier(0, 0, h - 1, .cream, .strips, cornice: true)]
            roof = .mansard(1.3); roofMaterial = .slate
        case .rooftopGarden:
            boxes = [tier(0, 0, h, .stone, .wide, cornice: true)]
            garden = true
        case .decoLowRise:
            boxes = [tier(0, 0, h * 0.7, .stone, .strips, cornice: true), tier(0.6, h * 0.7, h, .stone, .strips)]
            spire = 1.0
        case .theater:
            boxes = [tier(0, 0, h, .cream, .wide, cornice: true)]
            awning = .signal; spire = 1.3
        case .chapel:
            boxes = [tier(0, 0, h - 1.5, .stone, .wide)]
            roof = .gable(1.8); roofMaterial = .slate; spire = 1.8
        case .glassStudio:
            boxes = [tier(0, 0, h, .glass, .bands)]
            antennas = 1
        // Towers
        case .empire: // Three setbacks, a metal cap and a mast.
            boxes = [tier(0, 0, h * 0.3, .stone, .strips, cornice: true), tier(0.4, h * 0.3, h * 0.8, .stone, .strips),
                     tier(0.8, h * 0.8, h, .stone, .strips), tier(1.15, h, h + 0.9, .metal, .none)]
            spire = 2.4
        case .chrysler: // A stepped metal crown under a needle.
            boxes = [tier(0, 0, h * 0.3, .stone, .strips, cornice: true), tier(0.45, h * 0.3, h, .stone, .strips),
                     tier(0.65, h, h + 1.0, .metal, .none), tier(0.9, h + 1.0, h + 1.8, .metal, .none), tier(1.12, h + 1.8, h + 2.4, .metal, .none)]
            spire = 2.4
        case .woolworth: // A gothic tower under a copper pyramid.
            boxes = [tier(0, 0, h * 0.4, .stone, .strips, cornice: true), tier(0.5, h * 0.4, h, .stone, .strips)]
            roof = .pyramid(2.6); spire = 0.8
        case .rockefeller: // A thin slab with side setbacks.
            boxes = [tier(0, 0, h * 0.35, .stone, .strips, cornice: true), tier(0.25, h * 0.35, h * 0.75, .stone, .strips, depth: 0.9),
                     tier(0.65, h * 0.75, h, .stone, .strips, depth: 1.0)]
            antennas = 1
        case .glassCurtain: // A plain modernist box in dark glass.
            boxes = [tier(0, 0, h, .darkGlass, .bands)]
            bulkhead = true; antennas = 2
        case .freedom: // A metal podium, a glass shaft and a tall spire.
            boxes = [tier(0, 0, h * 0.15, .metal, .none), tier(0.3, h * 0.15, h, .glass, .bands)]
            spire = 3.0
        case .pencil: // A super-slender residential tower.
            boxes = [tier(1.2, 0, h, .cream, .grid, cornice: true)]
        case .plaza: // A château-style hotel under a mansard roof.
            boxes = [tier(0, 0, h * 0.85, .cream, .strips, cornice: true)]
            roof = .mansard(1.8); spire = 0.6
        case .municipal: // Tiers under a copper dome and a statue.
            boxes = [tier(0, 0, h * 0.6, .stone, .strips, cornice: true), tier(0.6, h * 0.6, h, .stone, .strips)]
            roof = .dome; spire = 1.4
        case .weddingCake: // Zoning-law setbacks all the way up.
            let steps: [(Double, Double, Double)] = [(0, 0, 0.35), (0.3, 0.35, 0.55), (0.6, 0.55, 0.7), (0.9, 0.7, 0.85), (1.15, 0.85, 1)]
            boxes = steps.enumerated().map { index, step in tier(step.0, h * step.1, h * step.2, .stone, .strips, cornice: index == 0) }
            antennas = 1
        case .citicorp: // Banded aluminium on a recessed base under a slanted crown.
            boxes = [tier(0.3, 0, h * 0.12, .metal, .none), tier(0, h * 0.12, h, .metal, .bands)]
            roof = .slant(2.6); roofMaterial = .metal
        case .hearst: // A stone base with a glass tower rising out of it.
            boxes = [tier(0, 0, h * 0.3, .stone, .wide, cornice: true), tier(0.35, h * 0.3, h, .darkGlass, .grid)]
            bulkhead = true
        }
    }
}

/// One project drawn as an isometric NYC building on its lot. Each working agent lights a floor;
/// the warning light on top marks agents that need input (amber) or reported failures (red).
struct PortfolioBuilding: View {
    let projectID: String
    let metrics: PortfolioBuildingMetrics
    let summary: SpatialSummary
    var animate = false
    /// Overrides the style chosen from the project ID.
    var style: PortfolioBuildingStyle?
    /// Tallest building on screen, as a massing `extent`. Every tile fits this one, so they share
    /// a scale without reserving room for a tower nobody has.
    var skyline = PortfolioBuilding.maxExtent
    @Environment(\.colorScheme) private var scheme
    /// Tallest possible building on screen, from the slab's front corner to the tip of its spire.
    static let maxExtent = 25.0
    private static let interval = 0.6
    private var signalling: Bool { summary.working > 0 || summary.attention > 0 || summary.failed > 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.interval, paused: !animate || !signalling)) { context in
            let tick = animate ? Int(context.date.timeIntervalSinceReferenceDate / Self.interval) : 0
            Canvas { graphics, size in
                let massing = PortfolioMassing(style ?? .of(projectID: projectID, metrics: metrics), metrics: metrics)
                let drawing = PortfolioBuildingDrawing(graphics: graphics, size: size, massing: massing, skyline: skyline, dark: scheme == .dark)
                drawing.drawCorner()
                drawing.draw(massing, projectID: projectID, summary: summary, animate: animate, tick: tick)
            }
        }.accessibilityHidden(true)
    }

    /// The skyline for a set of projects: the tallest of their buildings, with a floor so a street
    /// of walk-ups does not zoom in until one fills the tile.
    static func skyline(_ buildings: [(id: String, metrics: PortfolioBuildingMetrics)]) -> Double {
        let tallest = buildings.map { PortfolioMassing(.of(projectID: $0.id, metrics: $0.metrics), metrics: $0.metrics).extent }.max() ?? maxExtent
        return min(maxExtent, max(minimumSkyline, tallest))
    }
    static let minimumSkyline = 12.0

    /// FNV-1a; Swift's `Hasher` is seeded per launch and would reshuffle styles and lit floors.
    static func hash(_ seed: String, _ value: Int) -> UInt64 {
        var result: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 { result = (result ^ UInt64(byte)) &* 0x100000001b3 }
        var remaining = UInt64(bitPattern: Int64(value))
        for _ in 0..<8 { result = (result ^ (remaining & 0xff)) &* 0x100000001b3; remaining >>= 8 }
        return result
    }
}

/// Paints a building as a lit miniature: golden-hour sun on the front-left faces and cool sky in
/// the shade by day, dusk in dark mode. Edges come from light, not outlines. Draws one lot at
/// `origin`, so the same code paints a single tile or a lot anywhere in the overworld city.
struct PortfolioBuildingDrawing {
    typealias RGB = SIMD3<Double>
    /// How much a building draws: everything up close, less as the map zooms out.
    enum Detail: Comparable { case minimal, reduced, full }
    let graphics: GraphicsContext
    let unit: Double
    let origin: CGPoint
    let dark: Bool
    /// Iron and fine detail: spires, antennas, fire escapes.
    let ink: Color
    var detail = Detail.full
    /// Vertical scale, below 1 while a newly added building rises into place.
    var zScale = 1.0
    /// Shadows and the building's own paving; off when redrawing a building over the bus.
    var ground = true
    var streetLife = true
    /// Trees and lamps on the far curbs; off in the city, where the next block stands there.
    var streetTrees = true
    var beacon = true
    /// Shadows stay inside this square of the lot.
    var shadowExtent = PortfolioMassing.slab
    static let slabThickness = 5.0
    static let glow = RGB(1.0, 0.76, 0.38)

    init(graphics: GraphicsContext, unit: Double, origin: CGPoint, dark: Bool) {
        self.graphics = graphics
        self.unit = unit
        self.origin = origin
        self.dark = dark
        ink = dark ? Color(red: 0.55, green: 0.54, blue: 0.56) : Color(red: 0.26, green: 0.23, blue: 0.21)
    }

    /// One tile: the slab's front corner on the bottom edge, scaled so the skyline fits.
    init(graphics: GraphicsContext, size: CGSize, massing: PortfolioMassing, skyline: Double, dark: Bool) {
        let slab = PortfolioMassing.slab, bottom = size.height - Self.slabThickness - 1
        let unit = min(size.width * 0.96 / (2 * slab * 0.866), (bottom - 2) / (skyline + 0.9))
        self.init(graphics: graphics, unit: unit, origin: CGPoint(x: size.width / 2, y: bottom - slab * unit), dark: dark)
    }

    // MARK: Geometry and light

    func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        CGPoint(x: origin.x + (x - y) * unit * 0.866, y: origin.y + (x + y) * unit * 0.5 - z * unit * zScale)
    }
    func point(_ p: RGB) -> CGPoint { point(p.x, p.y, p.z) }
    func polygon(_ corners: [RGB]) -> Path {
        Path { path in path.addLines(corners.map(point)); path.closeSubpath() }
    }
    static func color(_ value: RGB, _ opacity: Double = 1) -> Color {
        let v = value.clamped(lowerBound: RGB(repeating: 0), upperBound: RGB(repeating: 1))
        return Color(red: v.x, green: v.y, blue: v.z).opacity(opacity)
    }
    /// A material under the scene's light: the roof, the sunlit front-left face and the shaded front-right face.
    func tones(_ rgb: RGB) -> (top: RGB, sun: RGB, shade: RGB) {
        if dark {
            let dusk = rgb * RGB(0.40, 0.42, 0.54)
            return (dusk * 1.15 + RGB(0.02, 0.02, 0.05), dusk * RGB(1.3, 1.08, 0.92), dusk * 0.7)
        }
        return (rgb * RGB(1.03, 1.02, 0.99) + (RGB(repeating: 1) - rgb) * 0.1,
                rgb * RGB(1.06, 0.98, 0.86) + RGB(0.04, 0.025, 0),
                rgb * RGB(0.64, 0.68, 0.80))
    }
    /// Fills a face; walls darken towards the ground. A hairline of the face's own colour keeps
    /// the edge crisp without drawing an outline.
    func face(_ corners: [RGB], _ tone: RGB, wall: Bool = true) {
        let path = polygon(corners)
        if wall, corners.count == 4 {
            let top = mid(point(corners[2]), point(corners[3])), bottom = mid(point(corners[0]), point(corners[1]))
            graphics.fill(path, with: .linearGradient(Gradient(colors: [Self.color(tone), Self.color(tone * 0.8)]), startPoint: top, endPoint: bottom))
        } else {
            graphics.fill(path, with: .color(Self.color(tone)))
        }
        graphics.stroke(path, with: .color(Self.color(tone * 0.7, 0.6)), style: StrokeStyle(lineWidth: 0.5, lineJoin: .round))
    }
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ material: PortfolioMaterial) {
        let light = tones(material.rgb)
        face([RGB(x0, y0, z1), RGB(x1, y0, z1), RGB(x1, y1, z1), RGB(x0, y1, z1)], light.top, wall: false)
        face([RGB(x0, y1, z0), RGB(x1, y1, z0), RGB(x1, y1, z1), RGB(x0, y1, z1)], light.sun)
        face([RGB(x1, y0, z0), RGB(x1, y1, z0), RGB(x1, y1, z1), RGB(x1, y0, z1)], light.shade)
    }
    func fraction(_ seed: String, _ value: Int) -> Double { Double(PortfolioBuilding.hash(seed, value) % 1000) / 1000 }

    // MARK: Windows

    struct Pane { let path: Path; let sunlit: Bool }
    /// Window rows on the two visible faces, one array per floor.
    func floors(_ b: PortfolioMassing.Box) -> [[Pane]] {
        let pitch: Double, width: Double, height: Double, row: Double
        switch b.windows {
        case .none: return []
        case .strips: (pitch, width, height, row) = (0.5, 0.24, 0.55, 0.9)
        case .wide: (pitch, width, height, row) = (0.62, 0.4, 0.6, 0.9)
        case .grid: (pitch, width, height, row) = (0.42, 0.28, 0.32, 0.6)
        case .bands: (pitch, width, height, row) = (0, 0, 0.5, 0.9)
        }
        func pane(front: Bool, _ a: Double, _ c: Double, _ z: Double) -> Pane {
            let corners = front ? [RGB(a, b.y1, z), RGB(c, b.y1, z), RGB(c, b.y1, z + height), RGB(a, b.y1, z + height)]
                : [RGB(b.x1, a, z), RGB(b.x1, c, z), RGB(b.x1, c, z + height), RGB(b.x1, a, z + height)]
            return Pane(path: polygon(corners), sunlit: front)
        }
        var result: [[Pane]] = []
        var z = b.z0 + 0.35
        while z + height <= b.z1 - 0.2 {
            var floor: [Pane] = []
            for (front, start, end) in [(true, b.x0, b.x1), (false, b.y0, b.y1)] {
                let span = end - start
                if pitch == 0 {
                    floor.append(pane(front: front, start + 0.06, end - 0.06, z))
                } else {
                    let columns = max(1, Int(span / pitch))
                    for column in 0..<columns {
                        let middle = start + span * (Double(column) + 0.5) / Double(columns)
                        floor.append(pane(front: front, middle - width / 2, middle + width / 2, z))
                    }
                }
            }
            result.append(floor)
            z += row
        }
        return result
    }
    /// Unlit glass: the sky reflected by day, dark interiors at dusk, varied like blinds and curtains.
    func glass(_ pane: Pane, variation: Double, curtainWall: Bool) -> Color {
        let shift = 0.86 + variation * 0.28
        if dark { return Self.color(RGB(0.12, 0.14, 0.20) * shift * (pane.sunlit ? 1.1 : 0.9)) }
        let sky = curtainWall ? RGB(0.62, 0.72, 0.82) : RGB(0.33, 0.37, 0.43)
        return Self.color(sky * shift * (pane.sunlit ? 1.05 : 0.72))
    }

    // MARK: Building

    func draw(_ massing: PortfolioMassing, projectID: String, summary: SpatialSummary, animate: Bool, tick: Int) {
        if ground { drawShadows(massing) }
        if ground, let base = massing.boxes.first {
            // The building's own paving, a shade warmer than the sidewalk.
            let m = PortfolioMassing.margin * 0.6
            let plot = polygon([RGB(base.x0 - m, base.y0 - m, 0), RGB(base.x1 + m, base.y0 - m, 0), RGB(base.x1 + m, base.y1 + m, 0), RGB(base.x0 - m, base.y1 + m, 0)])
            graphics.fill(plot, with: .color(Self.color(dark ? RGB(0.26, 0.25, 0.27) : RGB(0.80, 0.76, 0.70))))
        }

        let tiers = massing.boxes.map(floors)
        let total = tiers.reduce(0) { $0 + $1.count }
        // Each working agent lights one whole floor. Stable per project, so the same floors stay lit.
        let litFloors = Set((0..<total).sorted { PortfolioBuilding.hash(projectID, $0) < PortfolioBuilding.hash(projectID, $1) }.prefix(summary.working))
        var lit = Path()
        var floorIndex = 0, windowIndex = 0
        // Bottom tier first: each setback then covers the roof of the tier below it.
        for (b, tierFloors) in zip(massing.boxes, tiers) {
            box(b.x0, b.y0, b.x1, b.y1, b.z0, b.z1, b.material)
            if b.cornice { box(b.x0 - 0.1, b.y0 - 0.1, b.x1 + 0.1, b.y1 + 0.1, b.z1 - 0.2, b.z1, b.material) }
            for floor in tierFloors {
                let on = litFloors.contains(floorIndex)
                for pane in floor {
                    if on {
                        let flickering = animate && PortfolioBuilding.hash(projectID, windowIndex &* 31 &+ tick) % 6 == 0
                        graphics.fill(pane.path, with: .color(Self.color(Self.glow * (pane.sunlit ? 1 : 0.9), flickering ? 0.55 : 1)))
                        lit.addPath(pane.path)
                    } else if detail == .full {
                        graphics.fill(pane.path, with: .color(glass(pane, variation: fraction(projectID, windowIndex), curtainWall: b.material.isGlass)))
                    } else if detail == .reduced {
                        graphics.fill(pane.path, with: .color(glass(pane, variation: 0.5, curtainWall: b.material.isGlass)))
                    }
                    windowIndex += 1
                }
                floorIndex += 1
            }
        }
        // Warm light spilling from working floors.
        if !lit.isEmpty && detail == .full {
            graphics.drawLayer { layer in
                layer.addFilter(.blur(radius: unit * (dark ? 0.45 : 0.3)))
                layer.fill(lit, with: .color(Self.color(Self.glow, dark ? 0.9 : 0.35)))
            }
        }

        guard let base = massing.boxes.first, let roof = massing.boxes.last else { return }
        if detail >= .reduced, let awning = massing.awning { drawAwning(base, awning) }
        if detail == .full && massing.fireEscape { drawFireEscape(base) }

        let cx = (roof.x0 + roof.x1) / 2, cy = (roof.y0 + roof.y1) / 2
        drawRoof(massing, roof)
        var peak = roof.z1 + massing.roofRise
        if massing.garden { drawGarden(roof) }
        for (index, at) in massing.chimneys.enumerated() {
            let x = roof.x0 + roof.width * at, y = roof.y0 + 0.2 + Double(index % 2) * 0.1
            box(x, y, x + 0.28, y + 0.28, roof.z1, roof.z1 + 0.7, .sootBrick)
        }
        if massing.bulkhead {
            box(roof.x0 + roof.width * 0.5, roof.y0 + roof.depth * 0.18, roof.x0 + roof.width * 0.85, roof.y0 + roof.depth * 0.5, roof.z1, roof.z1 + 0.7, roof.material)
        }
        for at in massing.waterTowers {
            drawWaterTower(point(roof.x0 + roof.width * at.x, roof.y0 + roof.depth * at.y, roof.z1))
            peak = max(peak, roof.z1 + PortfolioMassing.waterTowerHeight)
        }
        if let length = massing.spire {
            drawSpire(foot: point(cx, cy, roof.z1 + massing.roofRise), tip: point(cx, cy, roof.z1 + massing.roofRise + length))
            peak = max(peak, roof.z1 + massing.roofRise + length)
        }
        for index in 0..<massing.antennas {
            let offset = massing.antennas == 1 ? 0 : (Double(index) - 0.5) * roof.width * 0.4
            let foot = point(cx + offset, cy, roof.z1), tip = point(cx + offset, cy, roof.z1 + PortfolioMassing.antennaHeight)
            graphics.stroke(Path { $0.move(to: foot); $0.addLine(to: tip) }, with: .color(ink), lineWidth: 1)
            peak = max(peak, roof.z1 + PortfolioMassing.antennaHeight)
        }

        if streetLife && detail == .full { drawStreetLife(projectID) }

        if beacon && (summary.attention > 0 || summary.failed > 0) {
            let tip = point(cx, cy, peak)
            let color = summary.attention > 0 ? Color.orange : Color.red
            let radius = unit * 0.32
            let light = Path(ellipseIn: CGRect(x: tip.x - radius, y: tip.y - radius * 2.2, width: radius * 2, height: radius * 2))
            let on = !(animate && tick % 2 == 1)
            if on {
                graphics.drawLayer { layer in
                    layer.addFilter(.blur(radius: radius * 1.2))
                    layer.fill(light, with: .color(color))
                }
            }
            graphics.fill(light, with: .color(color.opacity(on ? 1 : 0.4)))
        }
    }

    /// Soft shadows cast back and to the right by the late sun, kept on the slab.
    func drawShadows(_ massing: PortfolioMassing) {
        let slab = shadowExtent
        let cast = SIMD2<Double>(0.32, -0.62)
        var shadows = Path()
        for b in massing.boxes {
            var points: [CGPoint] = []
            for z in [b.z0, b.z1] {
                for (x, y) in [(b.x0, b.y0), (b.x1, b.y0), (b.x1, b.y1), (b.x0, b.y1)] {
                    points.append(point(x + z * cast.x, y + z * cast.y, 0))
                }
            }
            let hull = Self.hull(points)
            shadows.addLines(hull); shadows.closeSubpath()
        }
        var ground = graphics
        ground.clip(to: polygon([RGB(0, 0, 0), RGB(slab, 0, 0), RGB(slab, slab, 0), RGB(0, slab, 0)]))
        ground.fill(shadows, with: .color(Color(red: 0.1, green: 0.08, blue: 0.16).opacity(dark ? 0.35 : 0.2)))
    }
    /// Convex hull (monotone chain), counter-clockwise, so overlapping shadows fill once.
    static func hull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    // MARK: Roofs and rooftops

    func drawRoof(_ massing: PortfolioMassing, _ b: PortfolioMassing.Box) {
        let light = tones(massing.roofMaterial.rgb)
        let t = b.z1, cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2
        switch massing.roof {
        case .flat: break
        case .pyramid(let rise):
            let apex = RGB(cx, cy, t + rise)
            face([RGB(b.x0, b.y1, t), RGB(b.x1, b.y1, t), apex], light.sun, wall: false)
            face([RGB(b.x1, b.y0, t), RGB(b.x1, b.y1, t), apex], light.shade, wall: false)
        case .mansard(let rise):
            let m = min(b.width, b.depth) * 0.22
            let a = RGB(b.x0 + m, b.y0 + m, t + rise), c = RGB(b.x1 - m, b.y0 + m, t + rise)
            let e = RGB(b.x1 - m, b.y1 - m, t + rise), f = RGB(b.x0 + m, b.y1 - m, t + rise)
            face([RGB(b.x0, b.y1, t), RGB(b.x1, b.y1, t), e, f], light.sun, wall: false)
            face([RGB(b.x1, b.y0, t), RGB(b.x1, b.y1, t), e, c], light.shade, wall: false)
            face([a, c, e, f], light.top, wall: false)
            // Dormers with warm-lit glass.
            let dormers = max(1, Int(b.width / 0.9))
            for index in 0..<dormers {
                let middle = b.x0 + m + (b.width - 2 * m) * (Double(index) + 0.5) / Double(dormers)
                let z = t + rise * 0.3, y = b.y1 - m * 0.3
                graphics.fill(polygon([RGB(middle - 0.12, y, z), RGB(middle + 0.12, y, z), RGB(middle + 0.12, y, z + 0.4), RGB(middle - 0.12, y, z + 0.4)]),
                              with: .color(Self.color(dark ? RGB(0.16, 0.17, 0.22) : RGB(0.40, 0.46, 0.54))))
            }
        case .gable(let rise):
            let ridge0 = RGB(b.x0, cy, t + rise), ridge1 = RGB(b.x1, cy, t + rise)
            face([RGB(b.x0, b.y0, t), RGB(b.x1, b.y0, t), ridge1, ridge0], light.top, wall: false)
            face([RGB(b.x1, b.y0, t), RGB(b.x1, b.y1, t), ridge1], tones(b.material.rgb).shade, wall: false)
            face([RGB(b.x0, b.y1, t), RGB(b.x1, b.y1, t), ridge1, ridge0], light.sun, wall: false)
        case .slant(let rise):
            face([RGB(b.x1, b.y0, t), RGB(b.x1, b.y1, t), RGB(b.x1, b.y0, t + rise)], light.shade, wall: false)
            face([RGB(b.x0, b.y0, t + rise), RGB(b.x1, b.y0, t + rise), RGB(b.x1, b.y1, t), RGB(b.x0, b.y1, t)], light.top, wall: false)
        case .dome:
            let radius = massing.domeRadius, rise = massing.roofRise * unit
            let c = point(cx, cy, t)
            // A circle of this radius on the roof projects to an ellipse a wide and depth tall.
            let a = 1.2247 * radius * unit, depth = 0.707 * radius * unit
            let dome = Path { p in
                p.move(to: CGPoint(x: c.x - a, y: c.y))
                p.addCurve(to: CGPoint(x: c.x, y: c.y - rise), control1: CGPoint(x: c.x - a, y: c.y - rise * 0.55), control2: CGPoint(x: c.x - a * 0.55, y: c.y - rise))
                p.addCurve(to: CGPoint(x: c.x + a, y: c.y), control1: CGPoint(x: c.x + a * 0.55, y: c.y - rise), control2: CGPoint(x: c.x + a, y: c.y - rise * 0.55))
                p.addCurve(to: CGPoint(x: c.x - a, y: c.y), control1: CGPoint(x: c.x + a, y: c.y + depth * 1.33), control2: CGPoint(x: c.x - a, y: c.y + depth * 1.33))
                p.closeSubpath()
            }
            // Lit from the left, rounding into shade on the right.
            graphics.fill(dome, with: .linearGradient(Gradient(colors: [Self.color(light.sun * 1.08), Self.color(light.sun), Self.color(light.shade * 0.9)]),
                                                      startPoint: CGPoint(x: c.x - a, y: c.y - rise), endPoint: CGPoint(x: c.x + a, y: c.y)))
            for share in [-0.5, 0.0, 0.5] {
                let rib = Path { p in
                    p.move(to: CGPoint(x: c.x + a * share, y: c.y + depth * (1 - share * share).squareRoot()))
                    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - rise), control: CGPoint(x: c.x + a * share, y: c.y - rise * 0.8))
                }
                graphics.stroke(rib, with: .color(Self.color(light.shade * 0.8, 0.6)), lineWidth: 0.5)
            }
        }
    }

    /// A needle in stainless steel: its left half catches the sun.
    func drawSpire(foot: CGPoint, tip: CGPoint) {
        let half = unit * 0.16
        let steel = tones(PortfolioMaterial.metal.rgb)
        graphics.fill(Path { $0.addLines([CGPoint(x: foot.x - half, y: foot.y), foot, tip]); $0.closeSubpath() }, with: .color(Self.color(steel.sun)))
        graphics.fill(Path { $0.addLines([foot, CGPoint(x: foot.x + half, y: foot.y), tip]); $0.closeSubpath() }, with: .color(Self.color(steel.shade)))
    }

    func drawAwning(_ b: PortfolioMassing.Box, _ material: PortfolioMaterial) {
        let light = tones(material.rgb)
        let a = b.x0 + 0.15, c = b.x1 - 0.15
        face([RGB(a, b.y1, 1.3), RGB(c, b.y1, 1.3), RGB(c, b.y1 + 0.4, 0.95), RGB(a, b.y1 + 0.4, 0.95)], light.sun, wall: false)
        face([RGB(c, b.y1, 1.3), RGB(c, b.y1 + 0.4, 0.95), RGB(c, b.y1 + 0.4, 0.8), RGB(c, b.y1, 0.8)], light.shade, wall: false)
        // Shop light under the awning.
        graphics.fill(polygon([RGB(a + 0.1, b.y1, 0.15), RGB(c - 0.1, b.y1, 0.15), RGB(c - 0.1, b.y1, 0.85), RGB(a + 0.1, b.y1, 0.85)]),
                      with: .color(Self.color(RGB(1.0, 0.82, 0.55), dark ? 0.9 : 0.55)))
    }

    func drawFireEscape(_ b: PortfolioMassing.Box) {
        let a = b.x0 + 0.2, c = min(b.x1 - 0.2, a + 1.3), out = b.y1 + 0.28
        var z = 1.25, flip = false
        while z + 0.5 < b.z1 {
            let landing = polygon([RGB(a, b.y1, z), RGB(c, b.y1, z), RGB(c, out, z), RGB(a, out, z)])
            graphics.fill(landing, with: .color(ink.opacity(0.35)))
            let rail = Path { p in
                p.addLines([point(a, b.y1, z), point(a, out, z), point(c, out, z), point(c, b.y1, z)])
                p.move(to: point(a, out, z + 0.3)); p.addLine(to: point(c, out, z + 0.3))
            }
            graphics.stroke(rail, with: .color(ink), lineWidth: 0.8)
            if z + 1.4 < b.z1 {
                let ladder = Path { p in
                    p.move(to: point(flip ? c - 0.1 : a + 0.1, b.y1 + 0.14, z))
                    p.addLine(to: point(flip ? a + 0.1 : c - 0.1, b.y1 + 0.14, z + 0.9))
                }
                graphics.stroke(ladder, with: .color(ink), lineWidth: 0.6)
            }
            z += 0.9; flip.toggle()
        }
    }

    func drawGarden(_ b: PortfolioMassing.Box) {
        box(b.x0 + 0.15, b.y0 + 0.15, b.x1 - 0.15, b.y1 - 0.15, b.z1, b.z1 + 0.18, .garden)
        for spot in [SIMD2(0.3, 0.3), SIMD2(0.7, 0.35), SIMD2(0.4, 0.72)] {
            drawCanopy(point(b.x0 + b.width * spot.x, b.y0 + b.depth * spot.y, b.z1 + 0.5), radius: unit * 0.34)
        }
    }

    /// A cedar water tank on a steel frame, rounded by the light.
    func drawWaterTower(_ at: CGPoint) {
        let r = unit * 0.45, legs = unit * 0.6, tank = unit * 1.0
        for dx in [-r * 0.7, 0, r * 0.7] {
            graphics.stroke(Path { $0.move(to: CGPoint(x: at.x + dx, y: at.y)); $0.addLine(to: CGPoint(x: at.x + dx, y: at.y - legs)) }, with: .color(ink), lineWidth: 0.7)
        }
        let wood = tones(PortfolioMaterial.wood.rgb)
        let bottom = at.y - legs, top = bottom - tank
        let body = Path { p in
            p.addRect(CGRect(x: at.x - r, y: top, width: r * 2, height: tank))
            p.addEllipse(in: CGRect(x: at.x - r, y: bottom - r * 0.35, width: r * 2, height: r * 0.7))
        }
        graphics.fill(body, with: .linearGradient(Gradient(colors: [Self.color(wood.sun * 1.05), Self.color(wood.sun), Self.color(wood.shade)]),
                                                  startPoint: CGPoint(x: at.x - r, y: top), endPoint: CGPoint(x: at.x + r, y: top)))
        for band in [0.2, 0.5, 0.8] {
            let hoop = Path { $0.move(to: CGPoint(x: at.x - r, y: top + tank * band)); $0.addLine(to: CGPoint(x: at.x + r, y: top + tank * band)) }
            graphics.stroke(hoop, with: .color(ink.opacity(0.55)), lineWidth: 0.5)
        }
        let cone = Path { $0.addLines([CGPoint(x: at.x - r * 1.1, y: top), CGPoint(x: at.x + r * 1.1, y: top), CGPoint(x: at.x, y: top - r * 1.2)]); $0.closeSubpath() }
        graphics.fill(cone, with: .linearGradient(Gradient(colors: [Self.color(wood.sun * 0.9), Self.color(wood.shade * 0.85)]),
                                                  startPoint: CGPoint(x: at.x - r, y: top), endPoint: CGPoint(x: at.x + r, y: top)))
    }

    // MARK: The street corner

    /// The diorama base: a slab holding the block, two streets along the building's front faces
    /// meeting at an intersection with crosswalks.
    func drawCorner() {
        let block = PortfolioMassing.block, street = PortfolioMassing.street, slab = PortfolioMassing.slab
        let near = block + street
        let sidewalk = dark ? RGB(0.30, 0.30, 0.33) : RGB(0.87, 0.84, 0.78)
        let asphalt = dark ? RGB(0.15, 0.16, 0.19) : RGB(0.36, 0.36, 0.38)
        let soil = dark ? RGB(0.20, 0.19, 0.21) : RGB(0.62, 0.56, 0.48)

        // Slab sides, then its top.
        let down = Self.slabThickness
        func lowered(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y + down) }
        let left = [point(0, slab, 0), point(slab, slab, 0)], right = [point(slab, slab, 0), point(slab, 0, 0)]
        graphics.fill(Path { $0.addLines(left + left.reversed().map(lowered)); $0.closeSubpath() }, with: .color(Self.color(soil)))
        graphics.fill(Path { $0.addLines(right + right.reversed().map(lowered)); $0.closeSubpath() }, with: .color(Self.color(soil * 0.78)))
        graphics.fill(polygon([RGB(0, 0, 0), RGB(slab, 0, 0), RGB(slab, slab, 0), RGB(0, slab, 0)]), with: .color(Self.color(sidewalk)))

        // Paving joints on the sidewalks.
        let joints = Path { p in
            var at = 0.75
            while at < block {
                p.move(to: point(at, block - PortfolioMassing.margin, 0)); p.addLine(to: point(at, block, 0))
                p.move(to: point(block - PortfolioMassing.margin, at, 0)); p.addLine(to: point(block, at, 0))
                at += 0.75
            }
        }
        graphics.stroke(joints, with: .color(Self.color(sidewalk * 0.85)), lineWidth: 0.5)

        // Streets along both front faces; they overlap at the intersection.
        let roads = [polygon([RGB(0, block, 0), RGB(slab, block, 0), RGB(slab, near, 0), RGB(0, near, 0)]),
                     polygon([RGB(block, 0, 0), RGB(near, 0, 0), RGB(near, slab, 0), RGB(block, slab, 0)])]
        for road in roads { graphics.fill(road, with: .color(Self.color(asphalt))) }
        // Curbs: a bright granite edge where sidewalk meets road.
        let curbs = Path { p in
            for (a, b) in [(SIMD2(0, block), SIMD2(block, block)), (SIMD2(block, 0), SIMD2(block, block)),
                           (SIMD2(0, near), SIMD2(block, near)), (SIMD2(near, near), SIMD2(slab, near)),
                           (SIMD2(near, 0), SIMD2(near, block)), (SIMD2(near, near), SIMD2(near, slab))] {
                p.move(to: point(a.x, a.y, 0)); p.addLine(to: point(b.x, b.y, 0))
            }
        }
        graphics.stroke(curbs, with: .color(Self.color(sidewalk * 1.08)), lineWidth: 1.1)

        // Double yellow centre lines stop short of the crosswalks.
        let middle = block + street / 2
        let lanes = Path { p in
            for offset in [-0.05, 0.05] {
                p.move(to: point(0, middle + offset, 0)); p.addLine(to: point(block - 0.8, middle + offset, 0))
                p.move(to: point(middle + offset, 0, 0)); p.addLine(to: point(middle + offset, block - 0.8, 0))
            }
        }
        graphics.stroke(lanes, with: .color(Self.color(RGB(0.95, 0.76, 0.28), dark ? 0.6 : 0.9)), lineWidth: 0.6)

        // Zebra crossings where each street meets the intersection.
        let paint = Self.color(RGB(0.96, 0.95, 0.92), dark ? 0.5 : 0.85)
        let stripes = 5, gap = street / Double(stripes)
        for index in 0..<stripes {
            let a = block + gap * (Double(index) + 0.25), b = a + gap * 0.5
            graphics.fill(polygon([RGB(block - 0.6, a, 0), RGB(block - 0.15, a, 0), RGB(block - 0.15, b, 0), RGB(block - 0.6, b, 0)]), with: .color(paint))
            graphics.fill(polygon([RGB(a, block - 0.6, 0), RGB(b, block - 0.6, 0), RGB(b, block - 0.15, 0), RGB(a, block - 0.15, 0)]), with: .color(paint))
        }
    }

    /// Yellow cabs on the streets, and street trees and lamps along the far curbs.
    func drawStreetLife(_ seed: String) {
        let block = PortfolioMassing.block, street = PortfolioMassing.street, near = block + street
        let lane = (block + street * 0.55, block + street * 0.92)
        let pick = PortfolioBuilding.hash(seed, 7)
        if pick % 3 != 0 {
            let x = 0.5 + fraction(seed, 8) * (block - 2.4)
            drawCar(x0: x, y0: lane.0, x1: x + 1.0, y1: lane.1, taxi: pick % 5 != 0)
        }
        if pick % 2 == 0 {
            let y = 0.5 + fraction(seed, 9) * (block - 2.4)
            drawCar(x0: lane.0, y0: y, x1: lane.1, y1: y + 1.0, taxi: pick % 7 != 0)
        }
        guard streetTrees else { return }
        let curb = near + 0.2
        for at in [1.3, 4.6] { drawTree(point(at, curb, 0)) }
        drawLamp(point(3.0, curb, 0))
        for at in [1.3, 4.6] { drawTree(point(curb, at, 0)) }
        drawLamp(point(curb, 3.0, 0))
    }

    func drawCar(x0: Double, y0: Double, x1: Double, y1: Double, taxi: Bool) {
        let paint: PortfolioMaterial = taxi ? .cream : .slate
        let body = taxi ? RGB(0.98, 0.76, 0.14) : paint.rgb
        let shadow = polygon([RGB(x0 + 0.05, y0 + 0.05, 0), RGB(x1 + 0.12, y0 + 0.05, 0), RGB(x1 + 0.12, y1 + 0.1, 0), RGB(x0 + 0.05, y1 + 0.1, 0)])
        graphics.fill(shadow, with: .color(Color.black.opacity(dark ? 0.35 : 0.22)))
        let light = tones(body)
        let z = 0.32
        face([RGB(x0, y0, z), RGB(x1, y0, z), RGB(x1, y1, z), RGB(x0, y1, z)], light.top, wall: false)
        face([RGB(x0, y1, 0.06), RGB(x1, y1, 0.06), RGB(x1, y1, z), RGB(x0, y1, z)], light.sun, wall: false)
        face([RGB(x1, y0, 0.06), RGB(x1, y1, 0.06), RGB(x1, y1, z), RGB(x1, y0, z)], light.shade, wall: false)
        // Cabin with glass.
        let along = x1 - x0 > y1 - y0
        let (cx0, cy0, cx1, cy1) = along ? (x0 + 0.25, y0 + 0.05, x1 - 0.3, y1 - 0.05) : (x0 + 0.05, y0 + 0.25, x1 - 0.05, y1 - 0.3)
        let cabin = tones(dark ? RGB(0.10, 0.12, 0.16) : RGB(0.30, 0.36, 0.44))
        let top = 0.52
        face([RGB(cx0, cy1, z), RGB(cx1, cy1, z), RGB(cx1, cy1, top), RGB(cx0, cy1, top)], cabin.sun, wall: false)
        face([RGB(cx1, cy0, z), RGB(cx1, cy1, z), RGB(cx1, cy1, top), RGB(cx1, cy0, top)], cabin.shade, wall: false)
        face([RGB(cx0, cy0, top), RGB(cx1, cy0, top), RGB(cx1, cy1, top), RGB(cx0, cy1, top)], light.top, wall: false)
        if dark {
            // Headlights pointing down the street.
            let front = along ? point(x1, (y0 + y1) / 2, 0.2) : point((x0 + x1) / 2, y1, 0.2)
            graphics.drawLayer { layer in
                layer.addFilter(.blur(radius: unit * 0.25))
                layer.fill(Path(ellipseIn: CGRect(x: front.x - unit * 0.2, y: front.y - unit * 0.12, width: unit * 0.4, height: unit * 0.24)),
                           with: .color(Self.color(RGB(1.0, 0.92, 0.7))))
            }
        }
    }

    func drawTree(_ foot: CGPoint) {
        graphics.fill(Path(ellipseIn: CGRect(x: foot.x - unit * 0.1, y: foot.y - unit * 0.18, width: unit * 0.9, height: unit * 0.36)),
                      with: .color(Color.black.opacity(dark ? 0.3 : 0.16)))
        let trunkTop = CGPoint(x: foot.x, y: foot.y - unit * 0.8)
        graphics.stroke(Path { $0.move(to: foot); $0.addLine(to: trunkTop) }, with: .color(Self.color(RGB(0.36, 0.27, 0.2) * (dark ? 0.6 : 1))), lineWidth: 1.2)
        drawCanopy(CGPoint(x: foot.x, y: foot.y - unit * 1.15), radius: unit * 0.48)
    }

    /// A rounded crown of leaves, brighter where the sun reaches it.
    func drawCanopy(_ center: CGPoint, radius r: Double) {
        let leaf = dark ? RGB(0.16, 0.26, 0.17) : RGB(0.36, 0.56, 0.26)
        let blobs: [(Double, Double, Double)] = [(-0.45, 0.15, 0.7), (0.45, 0.2, 0.7), (0, -0.25, 0.8), (0, 0.15, 0.85)]
        for (dx, dy, scale) in blobs {
            let rr = r * scale
            graphics.fill(Path(ellipseIn: CGRect(x: center.x + dx * r - rr, y: center.y + dy * r - rr, width: rr * 2, height: rr * 2)), with: .color(Self.color(leaf)))
        }
        let sunlit = r * 0.5
        graphics.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.55 - sunlit, y: center.y - r * 0.35 - sunlit, width: sunlit * 2, height: sunlit * 2)),
                      with: .color(Self.color(leaf * RGB(1.35, 1.3, 1.1), 0.8)))
    }

    /// A cast-iron street lamp; at dusk it pools warm light on the sidewalk.
    func drawLamp(_ foot: CGPoint) {
        let head = CGPoint(x: foot.x, y: foot.y - unit * 1.5)
        if dark {
            graphics.drawLayer { layer in
                layer.addFilter(.blur(radius: unit * 0.5))
                layer.fill(Path(ellipseIn: CGRect(x: foot.x - unit * 0.9, y: foot.y - unit * 0.35, width: unit * 1.8, height: unit * 0.7)),
                           with: .color(Self.color(Self.glow, 0.45)))
                layer.fill(Path(ellipseIn: CGRect(x: head.x - unit * 0.3, y: head.y - unit * 0.3, width: unit * 0.6, height: unit * 0.6)),
                           with: .color(Self.color(Self.glow, 0.9)))
            }
        }
        graphics.stroke(Path { $0.move(to: foot); $0.addLine(to: head) }, with: .color(ink), lineWidth: 1)
        let r = unit * 0.14
        graphics.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                      with: .color(dark ? Self.color(RGB(1.0, 0.9, 0.7)) : ink))
    }
}
