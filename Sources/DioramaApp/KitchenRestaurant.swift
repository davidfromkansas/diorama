import SceneKit
import simd

/// The Mediterranean restaurant around the kitchen (`assets/restaurant`, built in Blender):
/// a checkered dining terrace in front of the serving window, walkways, a terracotta roof
/// behind the back wall, and a canal with lily pads. Loaded once; each kitchen clones it.
/// Diners sit at its `seat_NN` anchors and are served at the matching `dish_NN`.
@MainActor final class KitchenRestaurant {
    struct Seat: Equatable {
        let id: String
        /// Where a seated diner's root stands, and the plate spot on the table in front of it.
        let stand: SIMD2<Float>
        let dish: SIMD3<Float>
        /// Facing the table (yaw, `x += sin`, `z += cos`, as chefs use).
        var facing: Float { atan2(dish.x - stand.x, dish.z - stand.y) }
    }
    static let shared: KitchenRestaurant? = try? KitchenRestaurant()
    let template: SCNNode
    /// Nearest the serving pass first.
    let seats: [Seat]

    init(roots: [String: SCNNode]) throws {
        guard let root = roots["restaurant"] else { throw WorkspaceCapybaraAsset.AssetError.invalid("Restaurant model has no root") }
        template = root
        var stands: [String: SIMD3<Float>] = [:], dishes: [String: SIMD3<Float>] = [:]
        root.enumerateChildNodes { node, _ in
            guard let name = node.name else { return }
            if name.hasPrefix("seat_") { stands[String(name.dropFirst(5))] = node.simdWorldPosition }
            if name.hasPrefix("dish_") { dishes[String(name.dropFirst(5))] = node.simdWorldPosition }
            if name == "water" { node.geometry?.materials.forEach(Self.shimmer) }
            node.castsShadow = name != "water" && !name.hasPrefix("lily")
        }
        seats = stands.keys.sorted().compactMap { id in
            guard let stand = stands[id], let dish = dishes[id] else { return nil }
            return Seat(id: id, stand: SIMD2(stand.x, stand.z), dish: dish)
        }
    }
    convenience init() throws {
        try self.init(roots: GLBStaticMeshes.load("restaurant", subdirectory: "Restaurant"))
    }

    /// A fresh copy for one kitchen (geometry and materials are shared).
    func make() -> SCNNode { template.clone() }

    /// Gentle ripples of light on the canal; moves only while the kitchen is redrawing anyway.
    private static func shimmer(_ material: SCNMaterial) {
        material.lightingModel = .physicallyBased
        material.shaderModifiers = [.surface: """
        float2 p = _surface.diffuseTexcoord * 140.0; // the canal plane is 140 units across
        float t = scn_frame.time;
        float wave = sin(p.x * 0.9 + t * 0.8) * sin(p.y * 0.7 - t * 0.6) + 0.5 * sin((p.x + p.y) * 1.7 + t * 1.3);
        _surface.diffuse.rgb *= 0.94 + 0.08 * wave;
        _surface.diffuse.rgb += float3(0.05, 0.08, 0.08) * smoothstep(0.9, 1.4, wave);
        """]
        material.roughness.contents = 0.38
        material.metalness.contents = 0.0
    }
}
