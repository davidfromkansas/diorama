import SwiftUI
import simd
import Foundation
import DioramaCore

/// The overworld city on Home: projects as buildings on permanent lots, grouped into districts by
/// GitHub owner, joined by one avenue. Everything here is pure so placement is testable and stable.

/// A district: one GitHub owner, or the local district for projects without a GitHub remote.
enum OverworldDistrictKey: Hashable, Codable, Sendable {
    case github(owner: String)
    case local

    static func of(remote: String?) -> Self {
        guard let remote, let repository = GitHubRepository.parse(remote), repository.host.contains("github"),
              let owner = repository.name.split(separator: "/").first else { return .local }
        return .github(owner: owner.lowercased())
    }
    var title: String {
        switch self {
        case .github(let owner): owner
        case .local: "Local"
        }
    }
}

/// Which lot each project owns. Saved, so a project keeps its place across launches; new projects
/// take the lowest free lot in their district and never move anyone else.
struct OverworldLotLedger: Codable, Equatable, Sendable {
    struct Lot: Codable, Equatable, Sendable {
        var district: OverworldDistrictKey
        var index: Int
    }
    var districts: [OverworldDistrictKey] = []
    var lots: [String: Lot] = [:]

    /// The ledger after `projects` (in registration order) are placed.
    func assigning(_ projects: [(id: String, district: OverworldDistrictKey)]) -> Self {
        var next = self
        let present = Set(projects.map(\.id))
        next.lots = lots.filter { present.contains($0.key) }
        for project in projects {
            if let lot = next.lots[project.id], lot.district == project.district { continue }
            next.lots[project.id] = nil
            let taken = Set(next.lots.values.filter { $0.district == project.district }.map(\.index))
            var index = 0
            while taken.contains(index) { index += 1 }
            next.lots[project.id] = Lot(district: project.district, index: index)
        }
        // Districts keep their order; new ones join the end, and Local is always last.
        let used = Set(next.lots.values.map(\.district))
        var order = districts.filter { used.contains($0) }
        for project in projects where !order.contains(project.district) { order.append(project.district) }
        if let local = order.firstIndex(of: .local) { order.append(order.remove(at: local)) }
        next.districts = order
        return next
    }
}

struct OverworldLayout: Equatable {
    static let columns = 3
    static let pitch = PortfolioMassing.block + PortfolioMassing.street
    /// Water between districts, crossed by the avenue's bridges.
    static let gap = 4.0
    static var street: Double { PortfolioMassing.street }

    struct District: Equatable {
        let key: OverworldDistrictKey
        let originX: Double
        let rows: Int
        let projects: Int
        var width: Double { Double(OverworldLayout.columns) * OverworldLayout.pitch + OverworldLayout.street }
        var depth: Double { Double(rows) * OverworldLayout.pitch + OverworldLayout.street }
        var maxX: Double { originX + width }
    }
    struct Lot: Equatable {
        /// Nil for a free lot, drawn as a small park.
        let projectID: String?
        let district: Int
        let column: Int
        let row: Int
        /// The block's back corner; a building's massing is drawn from here.
        let origin: SIMD2<Double>
        /// The point on the street in front of the building's sunlit face.
        var door: SIMD2<Double> {
            SIMD2(origin.x + PortfolioMassing.block / 2, origin.y + PortfolioMassing.block + OverworldLayout.street / 2)
        }
        /// Painter's order: further back first.
        var depth: Double { origin.x + origin.y }
    }

    let districts: [District]
    /// Every lot, occupied or free, in painter's order.
    let lots: [Lot]

    init(ledger: OverworldLotLedger) {
        var districts: [District] = []
        var lots: [Lot] = []
        var x = 0.0
        for (index, key) in ledger.districts.enumerated() {
            let owners = ledger.lots.filter { $0.value.district == key }
            let highest = owners.map(\.value.index).max() ?? 0
            let rows = max(1, highest / Self.columns + 1)
            let district = District(key: key, originX: x, rows: rows, projects: owners.count)
            districts.append(district)
            let byIndex = Dictionary(owners.map { ($0.value.index, $0.key) }, uniquingKeysWith: min)
            for slot in 0..<(rows * Self.columns) {
                let column = slot % Self.columns, row = slot / Self.columns
                let origin = SIMD2(x + Self.street + Double(column) * Self.pitch, Self.street + Double(row) * Self.pitch)
                lots.append(Lot(projectID: byIndex[slot], district: index, column: column, row: row, origin: origin))
            }
            x = district.maxX + Self.gap
        }
        self.districts = districts
        self.lots = lots.sorted { $0.depth == $1.depth ? $0.origin.x < $1.origin.x : $0.depth < $1.depth }
    }

    func lot(for projectID: String) -> Lot? { lots.first { $0.projectID == projectID } }
    /// The ground the city covers, from the first district's back corner to the far curbs.
    var bounds: (min: SIMD2<Double>, max: SIMD2<Double>) {
        let width = districts.last?.maxX ?? Self.pitch
        let depth = districts.map(\.depth).max() ?? Self.pitch
        return (SIMD2(0, 0), SIMD2(width, depth))
    }

    // MARK: Streets

    /// An intersection: district, street column (0...columns) and street row (0...rows).
    struct Node: Hashable {
        let district: Int
        let column: Int
        let row: Int
    }
    func position(_ node: Node) -> SIMD2<Double> {
        let originX = districts[node.district].originX
        return SIMD2(originX + Double(node.column) * Self.pitch + Self.street / 2, Double(node.row) * Self.pitch + Self.street / 2)
    }
    var nodes: [Node] {
        districts.indices.flatMap { d in
            (0...districts[d].rows).flatMap { row in (0...Self.columns).map { Node(district: d, column: $0, row: row) } }
        }
    }
    func neighbours(_ node: Node) -> [Node] {
        var result: [Node] = []
        let rows = districts[node.district].rows
        if node.column > 0 { result.append(Node(district: node.district, column: node.column - 1, row: node.row)) }
        if node.column < Self.columns { result.append(Node(district: node.district, column: node.column + 1, row: node.row)) }
        if node.row > 0 { result.append(Node(district: node.district, column: node.column, row: node.row - 1)) }
        if node.row < rows { result.append(Node(district: node.district, column: node.column, row: node.row + 1)) }
        // The avenue (row 0) crosses the water between districts.
        if node.row == 0 && node.column == Self.columns && node.district + 1 < districts.count {
            result.append(Node(district: node.district + 1, column: 0, row: 0))
        }
        if node.row == 0 && node.column == 0 && node.district > 0 {
            result.append(Node(district: node.district - 1, column: Self.columns, row: 0))
        }
        return result
    }
    func nearestNode(to point: SIMD2<Double>, among candidates: [Node]? = nil) -> Node? {
        (candidates ?? nodes).min { simd_distance(position($0), point) < simd_distance(position($1), point) }
    }

    /// A drive along the streets from `start` to the door of `lot`. Every segment runs along a
    /// street, so it moves in one of the city's four directions.
    func route(from start: SIMD2<Double>, to lot: Lot) -> [SIMD2<Double>] {
        let goal = Node(district: lot.district, column: lot.column, row: lot.row + 1)
        guard let first = nearestNode(to: start) else { return [start, lot.door] }
        var previous: [Node: Node] = [:]
        var queue = [first], seen: Set<Node> = [first], head = 0
        while head < queue.count {
            let node = queue[head]; head += 1
            if node == goal { break }
            for next in neighbours(node) where seen.insert(next).inserted {
                previous[next] = node
                queue.append(next)
            }
        }
        var chain = [goal]
        while let back = previous[chain[0]] { chain.insert(back, at: 0) }
        guard chain.first == first else { return [start, lot.door] }
        var points = [start]
        // Join the street grid along the street the start is on.
        let entry = position(first)
        if abs(start.x - entry.x) > 1e-9 && abs(start.y - entry.y) > 1e-9 { points.append(SIMD2(entry.x, start.y)) }
        points += chain.map(position)
        points.append(lot.door)
        return points.enumerated().filter { $0.offset == 0 || simd_distance($0.element, points[$0.offset - 1]) > 1e-9 }.map(\.element)
    }
}

/// The isometric projection for a camera: world ground units to screen points and back.
struct OverworldProjection: Equatable {
    var unit: Double
    var origin: CGPoint

    func screen(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint {
        CGPoint(x: origin.x + (x - y) * unit * 0.866, y: origin.y + (x + y) * unit * 0.5 - z * unit)
    }
    func screen(_ p: SIMD2<Double>, _ z: Double = 0) -> CGPoint { screen(p.x, p.y, z) }
    /// The ground point under a screen point.
    func ground(_ point: CGPoint) -> SIMD2<Double> {
        let u = (point.x - origin.x) / (unit * 0.866), v = (point.y - origin.y) / (unit * 0.5)
        return SIMD2((v + u) / 2, (v - u) / 2)
    }
}

/// Where the map looks: the ground point at the centre of the view and the zoom.
struct OverworldCamera: Codable, Equatable, Sendable {
    var center: SIMD2<Double>
    var unit: Double
    static let maxUnit = 40.0

    func projection(size: CGSize) -> OverworldProjection {
        let x = size.width / 2 - (center.x - center.y) * unit * 0.866
        let y = size.height / 2 - (center.x + center.y) * unit * 0.5
        return OverworldProjection(unit: unit, origin: CGPoint(x: x, y: y))
    }

    /// Frames the whole city, buildings included, in the view.
    static func fit(_ layout: OverworldLayout, height: Double, size: CGSize) -> Self {
        let (low, high) = layout.bounds
        let unitProjection = OverworldProjection(unit: 1, origin: .zero)
        var points: [CGPoint] = []
        for corner in [SIMD2(low.x, low.y), SIMD2(high.x, low.y), SIMD2(high.x, high.y), SIMD2(low.x, high.y)] {
            points.append(unitProjection.screen(corner))
            points.append(unitProjection.screen(corner, height))
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let spanX = max(1, xs.max()! - xs.min()!), spanY = max(1, ys.max()! - ys.min()!)
        let unit = min(maxUnit, max(0.5, min(size.width * 0.92 / spanX, size.height * 0.9 / spanY)))
        let middle = CGPoint(x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
        let projection = OverworldProjection(unit: unit, origin: CGPoint(x: size.width / 2 - middle.x * unit, y: size.height / 2 - middle.y * unit))
        return Self(center: projection.ground(CGPoint(x: size.width / 2, y: size.height / 2)), unit: unit)
    }

    func panned(by translation: CGSize, size: CGSize) -> Self {
        var projection = projection(size: size)
        projection.origin.x += translation.width
        projection.origin.y += translation.height
        return Self(center: projection.ground(CGPoint(x: size.width / 2, y: size.height / 2)), unit: unit)
    }

    /// Zooms by `factor`, keeping the ground under `anchor` in place.
    func zoomed(by factor: Double, anchor: CGPoint, size: CGSize, minUnit: Double) -> Self {
        let before = projection(size: size)
        let held = before.ground(anchor)
        let unit = min(Self.maxUnit, max(minUnit, unit * factor))
        let after = OverworldProjection(unit: unit, origin: .zero)
        let offset = after.screen(held)
        let projection = OverworldProjection(unit: unit, origin: CGPoint(x: anchor.x - offset.x, y: anchor.y - offset.y))
        return Self(center: projection.ground(CGPoint(x: size.width / 2, y: size.height / 2)), unit: unit)
    }

    /// Keeps the view on the city.
    func clamped(to layout: OverworldLayout) -> Self {
        let (low, high) = layout.bounds
        return Self(center: SIMD2(min(max(center.x, low.x), high.x), min(max(center.y, low.y), high.y)), unit: unit)
    }
}

/// The bus that drives you to a project: eased along its street path, briefly.
struct OverworldBus: Equatable {
    let path: [SIMD2<Double>]
    let start: Date
    let target: String
    static let speed = 26.0

    var length: Double { zip(path, path.dropFirst()).reduce(0) { $0 + simd_distance($1.0, $1.1) } }
    var duration: Double { min(1.2, max(0.45, length / Self.speed)) }

    /// Position and travel direction after `elapsed` seconds.
    func position(after elapsed: Double) -> (point: SIMD2<Double>, heading: SIMD2<Double>) {
        guard path.count > 1 else { return (path.first ?? .zero, SIMD2(1, 0)) }
        let t = min(1, max(0, elapsed / duration))
        let eased = t * t * (3 - 2 * t)
        var remaining = eased * length
        for (a, b) in zip(path, path.dropFirst()) {
            let segment = simd_distance(a, b)
            if remaining <= segment || b == path.last {
                let fraction = segment > 0 ? min(1, remaining / segment) : 1
                return (a + (b - a) * fraction, segment > 0 ? (b - a) / segment : SIMD2(1, 0))
            }
            remaining -= segment
        }
        return (path.last!, SIMD2(1, 0))
    }
    func finished(at date: Date) -> Bool { date.timeIntervalSince(start) >= duration }
}

/// What a building looks like from the camera, for clicks and hover.
enum OverworldHit {
    /// The building's outline on screen: the hull of its boxes and its peak.
    static func silhouette(_ massing: PortfolioMassing, at lot: OverworldLayout.Lot, _ projection: OverworldProjection) -> [CGPoint] {
        var points: [CGPoint] = []
        for b in massing.boxes {
            for (x, y) in [(b.x0, b.y0), (b.x1, b.y0), (b.x1, b.y1), (b.x0, b.y1)] {
                points.append(projection.screen(lot.origin.x + x, lot.origin.y + y, b.z0))
                points.append(projection.screen(lot.origin.x + x, lot.origin.y + y, b.z1 + massing.roofRise))
            }
        }
        let peak = massing.peak
        points.append(projection.screen(lot.origin.x + peak.x, lot.origin.y + peak.y, peak.z))
        return PortfolioBuildingDrawing.hull(points)
    }

    /// The project under `point`: buildings nearest the camera win; otherwise the lot underfoot.
    static func project(at point: CGPoint, layout: OverworldLayout, massings: [String: PortfolioMassing], _ projection: OverworldProjection) -> String? {
        for lot in layout.lots.reversed() {
            guard let id = lot.projectID, let massing = massings[id] else { continue }
            let outline = silhouette(massing, at: lot, projection)
            if Path({ $0.addLines(outline); $0.closeSubpath() }).contains(point) { return id }
        }
        let ground = projection.ground(point)
        let block = PortfolioMassing.block
        return layout.lots.first {
            $0.projectID != nil && ground.x >= $0.origin.x && ground.x <= $0.origin.x + block && ground.y >= $0.origin.y && ground.y <= $0.origin.y + block
        }?.projectID
    }
}
