import Foundation
import SceneKit

/// The dishes chefs prepare: every `Food/*.glb` in the app bundle, normalized by
/// `assets/food/build.sh` (centred, base at 0, widest side 1.0). Adding a dish needs no code.
@MainActor enum KitchenFood {
    /// Dish templates by id (file name), loaded once; chefs clone them.
    static let templates: [String: SCNNode] = load()
    /// Dish ids in a stable order, so a task always gets the same dish.
    static var ids: [String] { templates.keys.sorted() }

    /// The dish for a task, with equal odds per dish. Stable across launches (FNV-1a plus a finalizer, not
    /// Swift's per-process seeded hasher); a new task key rolls again.
    static func dish(for key: String) -> String? { dish(for: key, among: ids) }
    nonisolated static func dish(for key: String, among ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        // FNV's low bits mix poorly for similar keys; finalize (MurmurHash3 fmix64) so the
        // remainder is even across dishes.
        hash ^= hash >> 33; hash &*= 0xff51afd7ed558ccd
        hash ^= hash >> 33; hash &*= 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        return ids[Int(hash % UInt64(ids.count))]
    }

    private static func load() -> [String: SCNNode] {
        let bundle = WorkspaceCapybaraAsset.resourceBundle
        guard let folder = bundle.resourceURL?.appendingPathComponent("Food"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: SCNNode] = [:]
        for file in files where file.pathExtension == "glb" {
            // An unreadable dish is skipped rather than breaking the kitchen.
            guard let data = try? Data(contentsOf: file), let roots = try? GLBStaticMeshes.read(data), !roots.isEmpty else { continue }
            let id = file.deletingPathExtension().lastPathComponent
            let dish = SCNNode(); dish.name = "dish:" + id
            for root in roots.values { dish.addChildNode(root) }
            result[id] = dish
        }
        return result
    }
}
