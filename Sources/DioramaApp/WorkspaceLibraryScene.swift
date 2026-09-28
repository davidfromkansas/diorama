import AppKit
import SceneKit
import SwiftUI
import DioramaCore

/// Authored in Blender; shared by the workspace and the catalogue's compact preview.
@MainActor enum WorkspaceLibraryArtwork {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.53, green: 0.66, blue: 0.55, alpha: 1),
        NSColor(srgbRed: 0.48, green: 0.63, blue: 0.75, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.55, blue: 0.46, alpha: 1),
        NSColor(srgbRed: 0.66, green: 0.53, blue: 0.69, alpha: 1),
        NSColor(srgbRed: 0.78, green: 0.64, blue: 0.36, alpha: 1)
    ]
    private static var templates: [String: SCNNode] = [:]
    private static var resourceBundle: Bundle? {
        // SwiftPM's generated accessor searches the .app root, whereas macOS bundles
        // store resource bundles under Contents/Resources. Never fall back to a developer
        // checkout for a packaged app.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Diorama_DioramaApp.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        if Bundle.main.bundleURL.pathExtension == "app" { return nil }
        return Bundle.module
    }
    static func asset(_ name: String) -> SCNNode? {
        if templates[name] == nil {
            guard let url = resourceBundle?.url(forResource: name, withExtension: "usdz", subdirectory: "Library"),
                  let scene = try? SCNScene(url: url, options: nil) else { return nil }
            let root = SCNNode()
            for node in scene.rootNode.childNodes { root.addChildNode(node.clone()) }
            templates[name] = root
        }
        guard let root = templates[name]?.clone() else { return nil }
        root.enumerateChildNodes { node, _ in
            node.geometry = node.geometry?.copy() as? SCNGeometry
            node.geometry?.materials = node.geometry?.materials.compactMap { $0.copy() as? SCNMaterial } ?? []
            for material in node.geometry?.materials ?? [] { material.lightingModel = .lambert }
        }
        return root
    }
    static let previewImage: NSImage = {
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 800, height: 360))
        view.scene = previewScene(); view.antialiasingMode = .multisampling4X
        return view.snapshot()
    }()
    static func alcove() -> SCNNode {
        let root = asset("ChibiLibrary") ?? SCNNode()
        root.name = "library"
        if root.childNodes.isEmpty {
            // A failed asset should not remove the in-world entry point.
            let material = WorkspaceAvatarFactory.material(colors[0])
            root.addChildNode(WorkspaceAvatarFactory.box(4, 2, 1, at: SCNVector3(0, 1, 0), material: material, bevel: 0.2))
        }
        let text = SCNText(string: "Little Library", extrusionDepth: 0.008)
        text.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        text.flatness = 0.1
        text.materials = [WorkspaceAvatarFactory.material(NSColor(srgbRed: 0.36, green: 0.24, blue: 0.17, alpha: 1))]
        let label = SCNNode(geometry: text)
        label.scale = SCNVector3(0.02, 0.02, 0.02)
        label.pivot = SCNMatrix4MakeTranslation(text.boundingBox.min.x, text.boundingBox.min.y, 0)
        label.position = SCNVector3(-0.74, 3.32, 0.16)
        root.addChildNode(WorkspaceAvatarFactory.box(2.1, 0.5, 0.1, at: SCNVector3(0.1, 3.45, 0.08), material: WorkspaceAvatarFactory.material(NSColor(srgbRed: 0.96, green: 0.87, blue: 0.68, alpha: 1)), bevel: 0.10))
        root.addChildNode(label)
        return root
    }
    static func book(_ item: CapabilityLibraryItem) -> SCNNode {
        let root = asset("ClosedBook") ?? SCNNode()
        root.name = "selectedLibraryBook"
        let color = colors[item.coverIndex]
        root.enumerateChildNodes { node, _ in
            var ancestor: SCNNode? = node
            var isCover = false
            while let current = ancestor, current !== root {
                if current.name?.contains("cover") == true || current.name?.contains("spine") == true { isCover = true }
                ancestor = current.parent
            }
            if isCover {
                node.geometry = node.geometry?.copy() as? SCNGeometry
                node.geometry?.materials = [WorkspaceAvatarFactory.material(color)]
            }
        }
        // Face the front cover toward the workspace camera.
        root.eulerAngles.y = .pi / 2
        let symbol = SCNPlane(width: 0.27, height: 0.27)
        let material = SCNMaterial(); material.lightingModel = .constant
        let icon = NSImage(systemSymbolName: item.emblem, accessibilityDescription: item.name)?
            .withSymbolConfiguration(.init(pointSize: 64, weight: .medium))
        let tinted = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            icon?.draw(in: rect)
            NSColor(srgbRed: 1, green: 0.96, blue: 0.84, alpha: 1).setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        material.diffuse.contents = tinted
        material.isDoubleSided = true
        symbol.materials = [material]
        let emblem = SCNNode(geometry: symbol)
        emblem.position = SCNVector3(-0.367, 0.53, 0)
        emblem.eulerAngles.y = -.pi / 2
        root.addChildNode(emblem)
        return root
    }
    static func previewScene() -> SCNScene {
        let scene = SCNScene(); scene.background.contents = NSColor(srgbRed: 0.95, green: 0.92, blue: 0.86, alpha: 1)
        scene.rootNode.addChildNode(alcove())
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 4.1
        camera.position = SCNVector3(7, 6, 10); camera.look(at: SCNVector3(0, 1.3, 0)); scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 700; scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 800
        key.eulerAngles = SCNVector3(-0.7, -0.5, 0); scene.rootNode.addChildNode(key)
        return scene
    }
}
