import AppKit
import ModelIO
import SceneKit
import SceneKit.ModelIO

/// Shared, static meshes. Placement nodes are retained when the floor expands.
enum OfficeLoungeAssets {
    nonisolated(unsafe) private static let models: [String: SCNNode] = {
        var result: [String: SCNNode] = [:]
        if let tv = OfficeArcade.load("LoungeTV") { result["LoungeTV"] = tv }
        if let table = OfficeArcade.load("Foosball") { result["Foosball"] = table }
        let bundle = OfficeAssetResources.bundle
        for name in ["LuvaCorner", "EamesLounge"] {
            guard let url = bundle.url(forResource: name + "Low", withExtension: "obj", subdirectory: "OfficeFurniture") else { continue }
            let root = SCNScene(mdlAsset: MDLAsset(url: url)).rootNode
            root.enumerateChildNodes { node, _ in
                node.geometry?.materials = node.geometry?.materials.map { source in
                    let material = SCNMaterial()
                    let part = source.name ?? node.name ?? ""
                    let upholstery = part.contains("FABRIC")
                    let shell = part.contains("SHELL")
                    material.name = part
                    material.lightingModel = .physicallyBased
                    material.diffuse.contents = shell ? NSColor(srgbRed: 0.34, green: 0.20, blue: 0.10, alpha: 1) :
                        (name == "LuvaCorner" && upholstery ? NSColor(srgbRed: 0.86, green: 0.82, blue: 0.74, alpha: 1) : NSColor(white: 0.07, alpha: 1))
                    material.roughness.contents = upholstery ? 0.92 : 0.65
                    material.metalness.contents = (!upholstery && !shell) ? 0.3 : 0
                    material.isDoubleSided = true
                    return material
                } ?? []
            }
            result[name] = root
        }
        return result
    }()

    nonisolated static func preloadMeshes() { _ = models }
    /// The shared template for a bundled lounge model (callers clone it).
    static func template(_ name: String) -> SCNNode? {
        OfficeAssetResources.prepare()
        return models[name]
    }

    static func make() -> SCNNode {
        OfficeAssetResources.prepare()
        let group = SCNNode(); group.name = "officeLeisureFurniture"
        for game in [OfficeArcade.make(wallX: 10), OfficeArcade.makePinball(wallX: 10)].compactMap({ $0 }) { OfficeBakedLayout.apply(to: game); group.addChildNode(game) }
        let lounge = SCNNode(); lounge.name = "officeTVLounge"
        for placement in OfficeLeisureLayout.standard.placements {
            guard let asset = models[placement.asset]?.clone() else { continue }
            let node = SCNNode(); node.name = placement.id
            if placement.asset == "LoungeTV" {
                let scale = OfficeLeisureLayout.tvScale
                asset.scale = SCNVector3(scale, scale, scale)
            }
            asset.eulerAngles.y = placement.yaw
            node.addChildNode(asset)
            node.position = SCNVector3(placement.x, -Double(asset.boundingBox.min.y), placement.z)
            OfficeBakedLayout.apply(to: node)
            lounge.addChildNode(node)
        }
        group.addChildNode(lounge)
        return group
    }
}

/// Only detached, immutable template meshes are initialized on the worker. Scene placement
/// and clones remain on the main actor. Swift static initialization synchronizes publication.
enum OfficeAssetPreparation {
    static let ready: Task<Void, Never> = {
        OfficeAssetResources.prepare()
        return Task.detached(priority: .userInitiated) {
            OfficeFurnitureAssets.preloadMeshes()
            OfficeArcade.preloadMeshes()
            OfficeLoungeAssets.preloadMeshes()
        }
    }()
}

/// Published once on the main actor before any worker can read it. Template callers
/// also prepare resources, so direct rendering tests use SwiftPM's actual bundle.
enum OfficeAssetResources {
    nonisolated(unsafe) private static var prepared: Bundle?
    static func prepare() {
        guard prepared == nil else { return }
        prepared = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Diorama_DioramaApp.bundle")) } ?? Bundle.module
    }
    nonisolated static var bundle: Bundle {
        guard let prepared else { preconditionFailure("Prepare office resources before starting the asset worker") }
        return prepared
    }
}
