import AppKit
import ModelIO
import SceneKit
import SceneKit.ModelIO

/// Static decorative furniture, shared across offices. Screen faces into the room.
enum OfficeArcade {
    nonisolated(unsafe) private static let model = load("Starcade")
    nonisolated(unsafe) private static let pinball = load("OctopusPinball")

    nonisolated static func load(_ assetName: String) -> SCNNode? {
        let bundle = OfficeAssetResources.bundle
        guard let url = bundle.url(forResource: assetName, withExtension: "obj", subdirectory: "OfficeFurniture") else { return nil }
        let root = SCNScene(mdlAsset: MDLAsset(url: url)).rootNode
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        func texture(_ suffix: String) -> NSImage? {
            bundle.url(forResource: assetName + suffix, withExtension: "jpg", subdirectory: "OfficeFurniture").flatMap { NSImage(contentsOf: $0) }
        }
        material.diffuse.contents = texture("Color")
        material.normal.contents = texture("Normal")
        material.roughness.contents = texture("MetalRough")
        material.roughness.textureComponents = .green
        material.metalness.contents = texture("MetalRough")
        material.metalness.textureComponents = .blue
        for property in [material.diffuse, material.normal, material.roughness, material.metalness] {
            property.mipFilter = .linear
            property.maxAnisotropy = 4
        }
        root.enumerateChildNodes { node, _ in node.geometry?.materials = [material] }
        return root
    }

    nonisolated static func preloadMeshes() { _ = model; _ = pinball }

    static func make(wallX: Double, z: Double = 7) -> SCNNode? {
        OfficeAssetResources.prepare()
        return make(model: model, name: "officeArcade", wallX: wallX, z: z)
    }

    static func makePinball(wallX: Double) -> SCNNode? {
        OfficeAssetResources.prepare()
        return make(model: pinball, name: "officePinball", wallX: wallX, z: 8.3)
    }

    private static func make(model: SCNNode?, name: String, wallX: Double, z: Double) -> SCNNode? {
        guard let cabinet = model?.clone() else { return nil }
        let bounds = cabinet.boundingBox
        let root = SCNNode()
        root.name = name
        cabinet.eulerAngles.y = -.pi / 2
        // Back (+world X after rotation) touches the walnut rail with 2 mm clearance.
        root.position = SCNVector3(wallX - OfficeWall.thickness - 0.010 + Double(bounds.min.z), -Double(bounds.min.y), z)
        root.addChildNode(cabinet)
        return root
    }
}
