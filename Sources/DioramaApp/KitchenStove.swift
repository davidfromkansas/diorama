import SceneKit
import simd

/// The kitchen's range (`assets/kitchen`, built in Blender): an Italian metalwork cooker in sage
/// enamel and brass that replaces the stove counter. Loaded once; each kitchen clones it. Its
/// `burner_N` anchors (left to right) are where the burner flames light.
@MainActor final class KitchenStove {
    static let shared: KitchenStove? = try? KitchenStove()
    let template: SCNNode
    /// Each burner crown's centre, in the model's own space (origin: footprint centre, on the floor).
    let burners: [SIMD3<Float>]

    init(roots: [String: SCNNode]) throws {
        guard let root = roots["stove"] else { throw WorkspaceCapybaraAsset.AssetError.invalid("Stove model has no root") }
        template = root
        var anchors: [Int: SIMD3<Float>] = [:]
        root.enumerateChildNodes { node, _ in
            if let name = node.name, name.hasPrefix("burner_"), let index = Int(name.dropFirst(7)) { anchors[index] = node.simdPosition }
        }
        burners = anchors.keys.sorted().compactMap { anchors[$0] }
        guard burners.count == 6 else { throw WorkspaceCapybaraAsset.AssetError.invalid("Stove model needs six burner anchors") }
    }
    convenience init() throws {
        try self.init(roots: GLBStaticMeshes.load("stove", subdirectory: "KitchenStations"))
    }

    /// Where it stands in the kitchen: the stove footprint's centre, on the floor.
    static var origin: SIMD3<Float> {
        let area = KitchenLayout.areas.first { $0.id == "stove" }
        return SIMD3(Float(area?.footprint.midX ?? 0), Float(KitchenLayout.floorTop), Float(area?.footprint.midY ?? 0))
    }
    /// A fresh copy for one kitchen (geometry and materials are shared), placed and named like the
    /// station it replaces.
    func make() -> SCNNode {
        let node = template.clone()
        node.name = "stove"
        node.simdPosition = Self.origin
        return node
    }
    /// Burner `index`'s crown in kitchen space.
    func burner(_ index: Int) -> SIMD3<Float>? { burners.indices.contains(index) ? Self.origin + burners[index] : nil }
}
