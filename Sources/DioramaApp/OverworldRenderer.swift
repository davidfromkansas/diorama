import SwiftUI
import simd

/// One building in the overworld: its project, lot and massing.
struct OverworldBuildingModel {
    let project: SpatialProject
    let lot: OverworldLayout.Lot
    let massing: PortfolioMassing
    var id: String { project.id }
    var summary: SpatialSummary { project.summary }
}

/// Paints the overworld city in the same golden-hour (or dusk) light as the buildings: water,
/// district islands with their street grids, bridges, parks, buildings back to front, then pins,
/// name plates and district banners on top.
struct OverworldRenderer {
    typealias RGB = SIMD3<Double>
    typealias Drawing = PortfolioBuildingDrawing
    let graphics: GraphicsContext
    let projection: OverworldProjection
    let layout: OverworldLayout
    let dark: Bool
    let viewport: CGRect

    var detail: Drawing.Detail { projection.unit >= 9 ? .full : projection.unit >= 4 ? .reduced : .minimal }
    /// World-space drawing helpers: a lot-sized drawing anchored at the world origin.
    var world: Drawing { Drawing(graphics: graphics, unit: projection.unit, origin: projection.origin, dark: dark) }
    var ink: Color { world.ink }
    func color(_ value: RGB, _ opacity: Double = 1) -> Color { Drawing.color(value, opacity) }
    func quad(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ z: Double = 0) -> Path {
        world.polygon([RGB(x0, y0, z), RGB(x1, y0, z), RGB(x1, y1, z), RGB(x0, y1, z)])
    }

    // MARK: Ground

    func drawGround() {
        // The harbour fills the whole view; the districts are islands in it.
        let water = dark ? RGB(0.08, 0.12, 0.19) : RGB(0.56, 0.72, 0.79)
        graphics.fill(Path(viewport), with: .color(color(water)))
        let corners = [CGPoint(x: viewport.minX, y: viewport.minY), CGPoint(x: viewport.maxX, y: viewport.minY),
                       CGPoint(x: viewport.maxX, y: viewport.maxY), CGPoint(x: viewport.minX, y: viewport.maxY)].map(projection.ground)
        let low = SIMD2(corners.map(\.x).min()!, corners.map(\.y).min()!), high = SIMD2(corners.map(\.x).max()!, corners.map(\.y).max()!)
        drawWaves(low: low, high: high)
        for (index, district) in layout.districts.enumerated() {
            if index + 1 < layout.districts.count { drawBridge(from: district.maxX, to: layout.districts[index + 1].originX) }
            drawIsland(district)
        }
        for lot in layout.lots where lot.projectID == nil { drawPark(lot) }
    }

    /// A few soft ripples so the water reads as water.
    func drawWaves(low: SIMD2<Double>, high: SIMD2<Double>) {
        guard detail >= .reduced, (high.x - low.x) * (high.y - low.y) < 40_000 else { return }
        var waves = Path()
        var y = low.y + 2
        while y < high.y {
            var x = low.x + (y.truncatingRemainder(dividingBy: 7))
            while x < high.x {
                waves.move(to: projection.screen(x, y)); waves.addLine(to: projection.screen(x + 1.2, y))
                x += 6
            }
            y += 3.2
        }
        graphics.stroke(waves, with: .color(Color.white.opacity(dark ? 0.08 : 0.35)), lineWidth: 0.8)
    }

    func drawIsland(_ district: OverworldLayout.District) {
        let x0 = district.originX, x1 = district.maxX, y1 = district.depth
        let sidewalk = dark ? RGB(0.30, 0.30, 0.33) : RGB(0.87, 0.84, 0.78)
        let asphalt = dark ? RGB(0.15, 0.16, 0.19) : RGB(0.36, 0.36, 0.38)
        let soil = dark ? RGB(0.20, 0.19, 0.21) : RGB(0.62, 0.56, 0.48)
        // Island sides, a little thicker than a tile's slab.
        let down = max(4, projection.unit * 0.7)
        func lowered(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y + down) }
        let left = [projection.screen(x0, y1), projection.screen(x1, y1)], right = [projection.screen(x1, y1), projection.screen(x1, 0)]
        graphics.fill(Path { $0.addLines(left + left.reversed().map(lowered)); $0.closeSubpath() }, with: .color(color(soil)))
        graphics.fill(Path { $0.addLines(right + right.reversed().map(lowered)); $0.closeSubpath() }, with: .color(color(soil * 0.78)))
        graphics.fill(quad(x0, 0, x1, y1), with: .color(color(sidewalk)))

        // The street grid: rows run along x, columns along y; row 0 is the avenue.
        let pitch = OverworldLayout.pitch, street = OverworldLayout.street
        var roads = Path()
        for row in 0...district.rows { roads.addPath(quad(x0, Double(row) * pitch, x1, Double(row) * pitch + street)) }
        for column in 0...OverworldLayout.columns {
            let x = x0 + Double(column) * pitch
            roads.addPath(quad(x, 0, x + street, y1))
        }
        graphics.fill(roads, with: .color(color(asphalt)))

        // Granite curbs around every block.
        var curbs = Path()
        for lot in layout.lots where layout.districts[lot.district] == district {
            curbs.addPath(quad(lot.origin.x, lot.origin.y, lot.origin.x + PortfolioMassing.block, lot.origin.y + PortfolioMassing.block))
        }
        graphics.stroke(curbs, with: .color(color(sidewalk * 1.08)), lineWidth: max(0.6, projection.unit * 0.1))

        guard detail >= .reduced else { return }
        drawLanes(district)
        if detail == .full { drawCrosswalks(district) }
    }

    /// Double yellow on the avenue, dashed white on side streets, stopping short of crossings.
    func drawLanes(_ district: OverworldLayout.District) {
        let pitch = OverworldLayout.pitch, street = OverworldLayout.street, block = PortfolioMassing.block
        var avenue = Path(), side = Path()
        for row in 0...district.rows {
            let y = Double(row) * pitch + street / 2
            for column in 0..<OverworldLayout.columns {
                let a = district.originX + Double(column) * pitch + street + 0.7, b = a + block - 1.4
                if row == 0 {
                    for offset in [-0.06, 0.06] {
                        avenue.move(to: projection.screen(a, y + offset)); avenue.addLine(to: projection.screen(b, y + offset))
                    }
                } else {
                    side.move(to: projection.screen(a, y)); side.addLine(to: projection.screen(b, y))
                }
            }
        }
        for column in 0...OverworldLayout.columns {
            let x = district.originX + Double(column) * pitch + street / 2
            for row in 0..<district.rows {
                let a = Double(row) * pitch + street + 0.7, b = a + block - 1.4
                side.move(to: projection.screen(x, a)); side.addLine(to: projection.screen(x, b))
            }
        }
        graphics.stroke(avenue, with: .color(color(RGB(0.95, 0.76, 0.28), dark ? 0.6 : 0.9)), lineWidth: 0.7)
        graphics.stroke(side, with: .color(Color.white.opacity(dark ? 0.3 : 0.6)), style: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
    }

    /// Zebra crossings on every approach to every intersection.
    func drawCrosswalks(_ district: OverworldLayout.District) {
        let pitch = OverworldLayout.pitch, street = OverworldLayout.street
        let stripes = 5, gap = street / Double(stripes)
        var paint = Path()
        for row in 0...district.rows {
            for column in 0...OverworldLayout.columns {
                let ix = district.originX + Double(column) * pitch, iy = Double(row) * pitch
                for index in 0..<stripes {
                    let a = gap * (Double(index) + 0.25), b = a + gap * 0.5
                    if column > 0 { paint.addPath(quad(ix - 0.6, iy + a, ix - 0.15, iy + b)) }
                    if column < OverworldLayout.columns { paint.addPath(quad(ix + street + 0.15, iy + a, ix + street + 0.6, iy + b)) }
                    if row > 0 { paint.addPath(quad(ix + a, iy - 0.6, ix + b, iy - 0.15)) }
                    if row < district.rows { paint.addPath(quad(ix + a, iy + street + 0.15, ix + b, iy + street + 0.6)) }
                }
            }
        }
        graphics.fill(paint, with: .color(color(RGB(0.96, 0.95, 0.92), dark ? 0.45 : 0.8)))
    }

    /// The avenue crossing the water to the next district.
    func drawBridge(from x0: Double, to x1: Double) {
        let street = OverworldLayout.street
        let deck = dark ? RGB(0.22, 0.22, 0.25) : RGB(0.58, 0.55, 0.52)
        let down = max(3, projection.unit * 0.4)
        let front = [projection.screen(x0, street), projection.screen(x1, street)]
        graphics.fill(Path { $0.addLines(front + front.reversed().map { CGPoint(x: $0.x, y: $0.y + down) }); $0.closeSubpath() },
                      with: .color(color(deck * 0.75)))
        graphics.fill(quad(x0, 0, x1, street), with: .color(color(deck)))
        var rails = Path()
        for y in [0.05, street - 0.05] {
            rails.move(to: projection.screen(x0, y, 0.35)); rails.addLine(to: projection.screen(x1, y, 0.35))
        }
        graphics.stroke(rails, with: .color(ink.opacity(0.7)), lineWidth: 0.8)
    }

    /// A free lot: a small green with trees.
    func drawPark(_ lot: OverworldLayout.Lot) {
        let block = PortfolioMassing.block, inset = PortfolioMassing.margin
        let grass = dark ? RGB(0.16, 0.24, 0.16) : RGB(0.55, 0.70, 0.42)
        graphics.fill(quad(lot.origin.x + inset, lot.origin.y + inset, lot.origin.x + block - inset, lot.origin.y + block - inset), with: .color(color(grass)))
        guard detail >= .reduced else { return }
        var drawing = world
        drawing.detail = detail
        for spot in [SIMD2(0.3, 0.35), SIMD2(0.68, 0.3), SIMD2(0.45, 0.72)] {
            drawing.drawTree(projection.screen(lot.origin.x + block * spot.x, lot.origin.y + block * spot.y))
        }
    }

    // MARK: Buildings

    func isVisible(_ model: OverworldBuildingModel) -> Bool {
        let block = PortfolioMassing.block, o = model.lot.origin
        let corners = [projection.screen(o.x, o.y), projection.screen(o.x + block, o.y),
                       projection.screen(o.x + block, o.y + block), projection.screen(o.x, o.y + block),
                       projection.screen(o.x, o.y, model.massing.peak.z)]
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        return rect.intersects(viewport.insetBy(dx: -40, dy: -40))
    }

    /// One building at its lot; `rise` below 1 while it rises into place.
    func drawBuilding(_ model: OverworldBuildingModel, animate: Bool, tick: Int, rise: Double = 1, faded: Bool = false, ground: Bool = true) {
        var context = graphics
        if faded { context.opacity = 0.28 }
        var drawing = Drawing(graphics: context, unit: projection.unit, origin: projection.screen(model.lot.origin), dark: dark)
        drawing.detail = detail
        drawing.zScale = rise
        drawing.ground = ground
        drawing.streetLife = ground
        drawing.streetTrees = false
        drawing.beacon = false
        drawing.shadowExtent = OverworldLayout.pitch
        drawing.draw(model.massing, projectID: model.id, summary: model.summary, animate: animate, tick: tick)
    }

    func drawOutline(_ model: OverworldBuildingModel) {
        let outline = OverworldHit.silhouette(model.massing, at: model.lot, projection)
        graphics.stroke(Path { $0.addLines(outline); $0.closeSubpath() }, with: .color(Color.white.opacity(0.9)), lineWidth: 2)
    }

    func peakPoint(_ model: OverworldBuildingModel) -> CGPoint {
        let peak = model.massing.peak
        return projection.screen(model.lot.origin.x + peak.x, model.lot.origin.y + peak.y, peak.z)
    }

    // MARK: Markers

    /// Map pins that stay the same size at any zoom: amber when an agent needs input, red on a
    /// failure, a green pip when zoomed out over a working building.
    func drawPin(_ model: OverworldBuildingModel, blinkOff: Bool) {
        let summary = model.summary
        let top = peakPoint(model)
        if summary.attention > 0 || summary.failed > 0 {
            let fill: Color = summary.attention > 0 ? .orange : .red
            let center = CGPoint(x: top.x, y: top.y - 16)
            let radius = 9.0
            if !blinkOff {
                graphics.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(fill))
                }
            }
            var pin = Path()
            pin.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            pin.move(to: CGPoint(x: center.x - 4, y: center.y + radius - 2))
            pin.addLine(to: CGPoint(x: center.x, y: center.y + radius + 6))
            pin.addLine(to: CGPoint(x: center.x + 4, y: center.y + radius - 2))
            graphics.fill(pin, with: .color(fill.opacity(blinkOff ? 0.55 : 1)))
            graphics.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(.white), lineWidth: 1.5)
            graphics.draw(Text("!").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white), at: center, anchor: .center)
        } else if summary.working > 0 && detail != .full {
            let r = 4.0
            graphics.fill(Path(ellipseIn: CGRect(x: top.x - r, y: top.y - 10 - r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.3, green: 0.85, blue: 0.45)))
        }
    }

    /// The project's name on a small plate in front of its building.
    func drawPlate(_ model: OverworldBuildingModel) {
        let text = graphics.resolve(Text(model.project.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
        let size = text.measure(in: CGSize(width: 220, height: 30))
        let at = projection.screen(model.lot.door)
        let rect = CGRect(x: at.x - size.width / 2 - 7, y: at.y - size.height / 2 - 3, width: size.width + 14, height: size.height + 6)
        graphics.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(Color.black.opacity(dark ? 0.6 : 0.55)))
        graphics.draw(text, at: at, anchor: .center)
    }

    /// Each district's sign stands on the water in front of it, like an Overcooked world banner.
    func drawBanners() {
        for district in layout.districts {
            let base = projection.screen(district.originX + district.width / 2, district.depth + 4)
            let label = district.key.title + " · " + String(district.projects)
            let text = graphics.resolve(Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Color(red: 0.25, green: 0.16, blue: 0.08)))
            let size = text.measure(in: CGSize(width: 300, height: 40))
            let rect = CGRect(x: base.x - size.width / 2 - 12, y: base.y - size.height - 26, width: size.width + 24, height: size.height + 10)
            var post = Path()
            post.move(to: CGPoint(x: base.x - 8, y: base.y)); post.addLine(to: CGPoint(x: base.x - 8, y: rect.maxY))
            post.move(to: CGPoint(x: base.x + 8, y: base.y)); post.addLine(to: CGPoint(x: base.x + 8, y: rect.maxY))
            graphics.stroke(post, with: .color(Color(red: 0.36, green: 0.25, blue: 0.16)), lineWidth: 2.5)
            let board = Path(roundedRect: rect, cornerRadius: 6)
            graphics.fill(board.offsetBy(dx: 0, dy: 2.5), with: .color(Color(red: 0.55, green: 0.34, blue: 0.16)))
            graphics.fill(board, with: .color(Color(red: 0.98, green: 0.84, blue: 0.48)))
            graphics.stroke(board, with: .color(Color(red: 0.55, green: 0.34, blue: 0.16)), lineWidth: 1.5)
            graphics.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    // MARK: The bus

    /// A red-and-cream city bus with a lit roof sign, driving along `heading`.
    func drawBus(at point: SIMD2<Double>, heading: SIMD2<Double>) {
        let along = abs(heading.x) >= abs(heading.y)
        let length = 1.9, width = 0.85
        let hx = along ? length / 2 : width / 2, hy = along ? width / 2 : length / 2
        let x0 = point.x - hx, x1 = point.x + hx, y0 = point.y - hy, y1 = point.y + hy
        let drawing = world
        graphics.fill(quad(x0 + 0.1, y0 + 0.15, x1 + 0.25, y1 + 0.2), with: .color(Color.black.opacity(dark ? 0.4 : 0.25)))
        let red = drawing.tones(RGB(0.84, 0.20, 0.16)), cream = drawing.tones(RGB(0.97, 0.90, 0.74))
        func block(_ z0: Double, _ z1: Double, _ light: (top: RGB, sun: RGB, shade: RGB), inset: Double = 0) {
            let a = x0 + inset, b = x1 - inset, c = y0 + inset, d = y1 - inset
            drawing.face([RGB(a, c, z1), RGB(b, c, z1), RGB(b, d, z1), RGB(a, d, z1)], light.top, wall: false)
            drawing.face([RGB(a, d, z0), RGB(b, d, z0), RGB(b, d, z1), RGB(a, d, z1)], light.sun, wall: false)
            drawing.face([RGB(b, c, z0), RGB(b, d, z0), RGB(b, d, z1), RGB(b, c, z1)], light.shade, wall: false)
        }
        block(0.12, 0.55, red)
        block(0.55, 1.0, cream)
        // Window band on both visible sides.
        let glass = dark ? RGB(0.95, 0.8, 0.5) : RGB(0.28, 0.36, 0.46)
        graphics.fill(world.polygon([RGB(x0 + 0.12, y1, 0.62), RGB(x1 - 0.12, y1, 0.62), RGB(x1 - 0.12, y1, 0.88), RGB(x0 + 0.12, y1, 0.88)]), with: .color(color(glass)))
        graphics.fill(world.polygon([RGB(x1, y0 + 0.1, 0.62), RGB(x1, y1 - 0.1, 0.62), RGB(x1, y1 - 0.1, 0.88), RGB(x1, y0 + 0.1, 0.88)]), with: .color(color(glass * 0.85)))
        // Roof sign.
        let sign = drawing.tones(RGB(1.0, 0.82, 0.25))
        let sx = along ? 0.45 : 0.18, sy = along ? 0.18 : 0.45
        drawing.face([RGB(point.x - sx, point.y - sy, 1.18), RGB(point.x + sx, point.y - sy, 1.18), RGB(point.x + sx, point.y + sy, 1.18), RGB(point.x - sx, point.y + sy, 1.18)], sign.top, wall: false)
        drawing.face([RGB(point.x - sx, point.y + sy, 1.0), RGB(point.x + sx, point.y + sy, 1.0), RGB(point.x + sx, point.y + sy, 1.18), RGB(point.x - sx, point.y + sy, 1.18)], sign.sun, wall: false)
        drawing.face([RGB(point.x + sx, point.y - sy, 1.0), RGB(point.x + sx, point.y + sy, 1.0), RGB(point.x + sx, point.y + sy, 1.18), RGB(point.x + sx, point.y - sy, 1.18)], sign.shade, wall: false)
        // Wheels.
        let r = projection.unit * 0.18
        for wheel in along ? [RGB(x0 + 0.4, y1, 0.12), RGB(x1 - 0.4, y1, 0.12)] : [RGB(x1, y0 + 0.4, 0.12), RGB(x1, y1 - 0.4, 0.12)] {
            let p = world.point(wheel)
            graphics.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.12)))
        }
    }

    /// Buildings standing between the camera and the bus, redrawn over it.
    func occludes(_ model: OverworldBuildingModel, bus point: SIMD2<Double>) -> Bool {
        let o = model.lot.origin, block = PortfolioMassing.block
        return (o.x >= point.x - 1 && o.y + block > point.y) || (o.y >= point.y - 0.5 && o.x + block > point.x)
    }
}
