import SceneKit
import simd

/// The kitchen's cooking island (`assets/kitchen`, built in Blender), French industrial: a
/// Carrara marble top on a blackened-steel frame with bronze fittings and open oak shelves.
/// Loaded once; each kitchen clones it. Its `board_N` anchors (left to right) are where the
/// cutting boards sit, so the boards and the chopping around them work as on the old counter.
@MainActor final class KitchenIsland {
    static let shared: KitchenIsland? = try? KitchenIsland()
    let template: SCNNode
    /// Each board's centre on the marble, in the model's own space (origin: footprint centre, on the floor).
    let boards: [SIMD3<Float>]
    /// A board's size in kitchen units, as on the old counter.
    static let board = SIMD3<Float>(0.9, 0.035, 0.55)

    init(roots: [String: SCNNode]) throws {
        guard let root = roots["island"] else { throw WorkspaceCapybaraAsset.AssetError.invalid("Island model has no root") }
        template = root
        var anchors: [Int: SIMD3<Float>] = [:]
        root.enumerateChildNodes { node, _ in
            if let name = node.name, name.hasPrefix("board_"), let index = Int(name.dropFirst(6)) { anchors[index] = node.simdPosition }
        }
        boards = anchors.keys.sorted().compactMap { anchors[$0] }
        guard boards.count == 6 else { throw WorkspaceCapybaraAsset.AssetError.invalid("Island model needs six board anchors") }
    }
    convenience init() throws {
        try self.init(roots: GLBStaticMeshes.load("island", subdirectory: "KitchenStations"))
    }

    /// The cooking station: the island at its footprint's centre on the floor, with a plain oak
    /// cutting board (`"cutting board"`, as the kitchen's board logic expects) on each anchor.
    func make(_ area: KitchenArea) -> SCNNode {
        let root = SCNNode()
        root.name = area.id
        root.simdPosition = SIMD3(Float(area.footprint.midX), Float(KitchenLayout.floorTop), Float(area.footprint.midY))
        root.addChildNode(template.clone())
        // The old counter's board oak.
        let oak = SCNMaterial(); oak.lightingModel = .physicallyBased
        oak.diffuse.contents = NSColor(red: 0.43, green: 0.26, blue: 0.13, alpha: 1); oak.roughness.contents = 0.62
        for anchor in boards {
            let geometry = SCNBox(width: CGFloat(Self.board.x), height: CGFloat(Self.board.y), length: CGFloat(Self.board.z), chamferRadius: 0.008)
            geometry.materials = [oak]
            let board = SCNNode(geometry: geometry); board.name = "cutting board"
            board.simdPosition = anchor + SIMD3(0, Self.board.y / 2, 0)
            root.addChildNode(board)
        }
        return root
    }
}
