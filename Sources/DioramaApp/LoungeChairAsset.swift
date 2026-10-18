import AppKit
import ModelIO
import SceneKit
import SceneKit.ModelIO

/// The break room's Eames lounge chair (`Resources/BreakRoom/EamesLoungeLow.obj`). The chef
/// sitting clips are tuned to its seat height, so every scene's lounge reuses it.
enum LoungeChairAsset {
    private static var cached: SCNNode??
    /// The shared template (callers clone it), or nil when the model isn't bundled.
    static func template() -> SCNNode? {
        if let cached { return cached }
        let root = SkinnedGLBAsset.resourceBundle
            .url(forResource: "EamesLoungeLow", withExtension: "obj", subdirectory: "BreakRoom")
            .map { SCNScene(mdlAsset: MDLAsset(url: $0)).rootNode }
        root?.enumerateChildNodes { node, _ in
            node.geometry?.materials = node.geometry?.materials.map { source in
                let part = source.name ?? node.name ?? ""
                let upholstery = part.contains("FABRIC"), shell = part.contains("SHELL")
                let material = SCNMaterial()
                material.name = part
                material.lightingModel = .physicallyBased
                material.diffuse.contents = shell ? NSColor(srgbRed: 0.34, green: 0.20, blue: 0.10, alpha: 1) : NSColor(white: 0.07, alpha: 1)
                material.roughness.contents = upholstery ? 0.92 : 0.65
                material.metalness.contents = (!upholstery && !shell) ? 0.3 : 0
                material.isDoubleSided = true
                return material
            } ?? []
        }
        cached = .some(root)
        return root
    }
}
