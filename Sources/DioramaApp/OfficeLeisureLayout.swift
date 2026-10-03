import Foundation

struct LeisureBounds: Equatable {
    var minX: Double
    var maxX: Double
    var minZ: Double
    var maxZ: Double
    func contains(x: Double, z: Double, clearance: Double = 0) -> Bool {
        x >= minX - clearance && x <= maxX + clearance && z >= minZ - clearance && z <= maxZ + clearance
    }
    func overlaps(_ other: Self) -> Bool {
        minX < other.maxX && maxX > other.minX && minZ < other.maxZ && maxZ > other.minZ
    }
}

/// One source of truth for visible furniture, access aisles, floor sizing, and idle positions.
struct OfficeLeisureLayout {
    struct Placement: Identifiable {
        let id: String
        let asset: String
        let x: Double
        let z: Double
        let yaw: Double
        let bounds: LeisureBounds
        init(id: String, asset: String, x: Double, z: Double, yaw: Double, dimensions: [Double]) {
            self.id = id; self.asset = asset; self.x = x; self.z = z; self.yaw = yaw
            let w = abs(cos(yaw)) * dimensions[0] + abs(sin(yaw)) * dimensions[2]
            let d = abs(sin(yaw)) * dimensions[0] + abs(cos(yaw)) * dimensions[2]
            bounds = .init(minX: x-w/2, maxX: x+w/2, minZ: z-d/2, maxZ: z+d/2)
        }
    }
    static let tvScale = 2.0
    static let aisle = 1.2
    static let standard = OfficeLeisureLayout()
    let placements: [Placement]
    let seatingZone: LeisureBounds
    let floorMaxZ: Double
    let centerZ: Double

    init() {
        let bundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Diorama_DioramaApp.bundle")) } ?? Bundle.module
        let dimensions = bundle.url(forResource: "LoungeDimensions", withExtension: "json", subdirectory: "OfficeFurniture")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: [Double]].self, from: $0) } ?? [:]
        // Last-resort authored bounds keep layout stable if a resource is unavailable.
        let sofa = dimensions["LuvaCorner"] ?? [2.94918, 0.72307, 2.94980]
        let chair = dimensions["EamesLounge"] ?? [0.85852, 0.89433, 0.87165]
        let tv = (dimensions["LoungeTV"] ?? [1.9, 1.23438, 0.52828]).map { $0 * Self.tvScale }
        let side = max(sofa[0], sofa[2])
        let startZ = 10.5 // beyond the pinball's operating area
        centerZ = startZ + side + Self.aisle / 2
        let sofaX = 2.0
        let frontOfSofas = sofaX + side / 2
        let chairAngle = Double.pi / 12
        let chairDepth = cos(chairAngle) * chair[2] + sin(chairAngle) * chair[0]
        let chairWidth = cos(chairAngle) * chair[0] + sin(chairAngle) * chair[2]
        let chairX = frontOfSofas + Self.aisle + chairDepth / 2
        var values: [Placement] = []
        values.append(.init(id: "loungeTV", asset: "LoungeTV", x: 10 - 0.65 - tv[2]/2, z: centerZ, yaw: -.pi/2, dimensions: tv))
        for sideIndex in 0..<2 {
            let sign = sideIndex == 0 ? -1.0 : 1.0
            // Both sectionals open toward +X and the central aisle; rotations only, no mirroring.
            values.append(.init(id: "loungeSofa\(sideIndex)", asset: "LuvaCorner", x: sofaX,
                                z: centerZ + sign * (side/2 + Self.aisle/2), yaw: sideIndex == 0 ? 0 : .pi/2, dimensions: sofa))
            for index in 0..<2 {
                let offset = Self.aisle/2 + chairWidth/2 + Double(index) * (chairWidth + 0.3)
                values.append(.init(id: "loungeChair\(sideIndex)-\(index)", asset: "EamesLounge", x: chairX,
                                    z: centerZ + sign * offset, yaw: .pi/2 + sign * chairAngle, dimensions: chair))
            }
        }
        let table = dimensions["Foosball"] ?? [2.7020428, 0.9, 2.065196]
        let tableZ = values.map(\.bounds.maxZ).max()! + Self.aisle + table[2]/2
        values.append(.init(id: "loungeFoosball", asset: "Foosball", x: 4, z: tableZ, yaw: 0, dimensions: table))
        placements = values
        seatingZone = .init(minX: values.map(\.bounds.minX).min()! - Self.aisle, maxX: 10,
                            minZ: startZ - Self.aisle/2, maxZ: values.map(\.bounds.maxZ).max()! + Self.aisle)
        floorMaxZ = max(seatingZone.maxZ, 23.1)
    }

    func standingPosition(slot: Int) -> OfficeDeskAssignment {
        if slot < 8 {
            return .init(slot: slot, x: 7 - Double(slot/2)*2, z: 6 + Double(slot%2)*2, yaw: 0)
        }
        // Extra agents use the clear corridor to the left of the lounge, never its seating or aisles.
        return .init(slot: slot, x: -2 - Double((slot-8)%4)*2, z: 6 + Double((slot-8)/4)*2, yaw: 0)
    }
}
