import AppKit
import SceneKit

/// The office's palette: light oak, warm white, matte black, pastel accents and glass.
@MainActor enum OfficeMaterials {
    static func matte(_ color: NSColor, roughness: CGFloat = 0.7) -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .physicallyBased
        material.diffuse.contents = color; material.roughness.contents = roughness; material.metalness.contents = 0
        return material
    }
    static func metal(_ color: NSColor, roughness: CGFloat = 0.35) -> SCNMaterial {
        let material = matte(color, roughness: roughness); material.metalness.contents = 0.75
        return material
    }
    /// Lit from within (screens, status lights, lit windows): unaffected by the scene's light.
    static func glow(_ color: NSColor, strength: CGFloat = 1) -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = color; material.emission.contents = color.withAlphaComponent(strength)
        return material
    }
    static func glass(_ tint: NSColor = NSColor(srgbRed: 0.80, green: 0.90, blue: 0.95, alpha: 1), transparency: CGFloat = 0.32) -> SCNMaterial {
        let material = matte(tint, roughness: 0.08); material.transparency = transparency
        material.isDoubleSided = true; material.writesToDepthBuffer = false
        return material
    }
    static let oak = matte(NSColor(srgbRed: 0.84, green: 0.70, blue: 0.52, alpha: 1), roughness: 0.55)
    static let oakEdge = matte(NSColor(srgbRed: 0.72, green: 0.57, blue: 0.40, alpha: 1), roughness: 0.6)
    static let white = matte(NSColor(srgbRed: 0.95, green: 0.94, blue: 0.91, alpha: 1), roughness: 0.75)
    static let plaster = matte(NSColor(srgbRed: 0.93, green: 0.90, blue: 0.85, alpha: 1), roughness: 0.85)
    static let black = matte(NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1), roughness: 0.5)
    static let graphite = matte(NSColor(srgbRed: 0.24, green: 0.25, blue: 0.28, alpha: 1), roughness: 0.45)
    static let aluminium = metal(NSColor(srgbRed: 0.78, green: 0.79, blue: 0.80, alpha: 1))
    static let brass = metal(NSColor(srgbRed: 0.83, green: 0.64, blue: 0.32, alpha: 1), roughness: 0.28)
    static let cork = matte(NSColor(srgbRed: 0.76, green: 0.58, blue: 0.40, alpha: 1), roughness: 0.95)
    static let leaf = matte(NSColor(srgbRed: 0.35, green: 0.58, blue: 0.36, alpha: 1), roughness: 0.8)
    static let leafLight = matte(NSColor(srgbRed: 0.50, green: 0.70, blue: 0.42, alpha: 1), roughness: 0.8)
    static let terracotta = matte(NSColor(srgbRed: 0.80, green: 0.50, blue: 0.36, alpha: 1), roughness: 0.85)
    static let paper = matte(NSColor(srgbRed: 0.99, green: 0.98, blue: 0.95, alpha: 1), roughness: 0.9)
    static func accent(_ color: NSColor) -> SCNMaterial { matte(color, roughness: 0.6) }
}

/// Adds simple shapes to a node, positioned in its local space (y up, +z toward the room).
@MainActor struct OfficeBuilder {
    let root: SCNNode
    init(_ root: SCNNode) { self.root = root }
    init(named name: String) { root = SCNNode(); root.name = name }

    @discardableResult func box(_ name: String, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                                _ material: SCNMaterial, chamfer: CGFloat? = nil, in parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNBox(width: w, height: h, length: d, chamferRadius: chamfer ?? min(0.03, min(w, min(h, d)) / 4))
        shape.materials = [material]
        let node = SCNNode(geometry: shape); node.name = name; node.position = SCNVector3(x, y, z)
        (parent ?? root).addChildNode(node); return node
    }
    @discardableResult func cylinder(_ name: String, _ radius: CGFloat, _ h: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                                     _ material: SCNMaterial, segments: Int = 20, in parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNCylinder(radius: radius, height: h); shape.radialSegmentCount = segments; shape.materials = [material]
        let node = SCNNode(geometry: shape); node.name = name; node.position = SCNVector3(x, y, z)
        (parent ?? root).addChildNode(node); return node
    }
    @discardableResult func cone(_ name: String, top: CGFloat, bottom: CGFloat, _ h: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                                 _ material: SCNMaterial, in parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNCone(topRadius: top, bottomRadius: bottom, height: h); shape.radialSegmentCount = 18; shape.materials = [material]
        let node = SCNNode(geometry: shape); node.name = name; node.position = SCNVector3(x, y, z)
        (parent ?? root).addChildNode(node); return node
    }
    @discardableResult func sphere(_ name: String, _ radius: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                                   _ material: SCNMaterial, segments: Int = 14, in parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNSphere(radius: radius); shape.segmentCount = segments; shape.materials = [material]
        let node = SCNNode(geometry: shape); node.name = name; node.position = SCNVector3(x, y, z)
        (parent ?? root).addChildNode(node); return node
    }

    /// A potted plant: a pot and a cluster of leafy spheres, about `height` tall.
    @discardableResult func plant(_ x: CGFloat, _ z: CGFloat, height: CGFloat = 1.2, base y: CGFloat = 0, pot: SCNMaterial = OfficeMaterials.white, seed: Int = 0) -> SCNNode {
        let group = SCNNode(); group.name = "plant"; group.position = SCNVector3(x, y, z); root.addChildNode(group)
        let inner = OfficeBuilder(group)
        let potHeight = height * 0.32, radius = height * 0.17
        inner.cone("plant pot", top: radius, bottom: radius * 0.78, potHeight, 0, potHeight / 2, 0, pot)
        inner.cylinder("plant soil", radius * 0.92, 0.02, 0, potHeight - 0.01, 0, OfficeMaterials.matte(NSColor(srgbRed: 0.27, green: 0.20, blue: 0.15, alpha: 1)))
        let leaves = [OfficeMaterials.leaf, OfficeMaterials.leafLight]
        for i in 0..<5 {
            let angle = CGFloat(i + seed) * 2.4, spread = radius * (i == 0 ? 0 : 0.75)
            let size = height * (i == 0 ? 0.24 : 0.17)
            inner.sphere("plant leaves", size, cos(angle) * spread, potHeight + height * (i == 0 ? 0.42 : 0.28 + 0.08 * CGFloat(i % 2)), sin(angle) * spread,
                         leaves[(i + seed) % 2], segments: 10)
        }
        return group
    }
}
