import AppKit
import SceneKit
import simd

/// Model-local origin is at the feet, +Y is up, +Z is forward, height is about 2.5 units.
/// Replacing this factory with an asset loader doesn't affect selection, labels or activity.
struct WorkspaceAvatar {
    let root: SCNNode
    let body: SCNNode?
    let head: SCNNode?
    let leftArm: SCNNode?
    let rightArm: SCNNode?
    var workingAnchors: [SCNNode] { [leftArm, rightArm].compactMap { $0 } }
    var poseAnchors: [SCNNode] { [body, head, leftArm, rightArm].compactMap { $0 } }
    var capybaraRig: WorkspaceCapybaraAsset.Instance? = nil
    var bindings: [ObjectIdentifier: Binding] = [:]
    struct Binding {
        let local: simd_quatf
        let world: simd_quatf
        let parentWorld: simd_quatf
        let direction: SIMD3<Float>
    }
    func orientation(for node: SCNNode, x: Double = 0, y: Double = 0, z: Double = 0) -> simd_quatf {
        guard let binding = bindings[ObjectIdentifier(node)] else {
            return simd_quatf(angle: Float(y), axis: SIMD3(0,1,0)) * simd_quatf(angle: Float(x), axis: SIMD3(1,0,0)) * simd_quatf(angle: Float(z), axis: SIMD3(0,0,1))
        }
        if node === leftArm || node === rightArm {
            let side: Float = node === leftArm ? 1 : -1
            let direction = simd_normalize(SIMD3(side * 0.25 + Float(z) * 0.45,
                                                -sin(Float(x)) * 0.94 - cos(Float(x)) * 0.40,
                                                cos(Float(x)) * 0.88))
            return binding.parentWorld.inverse * simd_quatf(from: binding.direction, to: direction) * binding.world
        }
        let yaw = Float(node === body ? min(0.45, max(-0.45, y)) : y)
        return binding.local * simd_quatf(angle: yaw, axis: SIMD3(0,1,0))
            * simd_quatf(angle: Float(x), axis: SIMD3(1,0,0)) * simd_quatf(angle: Float(z), axis: SIMD3(0,0,1))
    }
    // Semantic rotations are mapped onto each bone's authored bind orientation.
    let neutralRotation = SCNVector3Zero
}

enum WorkspaceAvatarFactory {
    static func capybara() -> WorkspaceAvatar {
        do {
            let instance = try WorkspaceCapybaraAsset.shared.get().makeInstance()
            instance.root.simdScale = SIMD3(repeating: 2.5)
            instance.apply(instance.pose("idle", time: 0))
            // Seat the short legs on the existing chair; keep shins and paws hanging naturally.
            for side in ["L", "R"] {
                if let thigh = instance.bone("upper_leg." + side),
                   let shin = instance.bone("lower_leg." + side), let foot = instance.bone("foot." + side) {
                    let shinOrientation = shin.simdWorldOrientation, footOrientation = foot.simdWorldOrientation
                    let direction = simd_normalize(shin.simdWorldPosition - thigh.simdWorldPosition)
                    thigh.simdWorldOrientation = simd_quatf(from: direction, to: simd_normalize(SIMD3(0,-0.28,1))) * thigh.simdWorldOrientation
                    shin.simdWorldOrientation = shinOrientation; foot.simdWorldOrientation = footOrientation
                }
            }
            var avatar = WorkspaceAvatar(root: instance.root, body: instance.bone("chest"), head: instance.bone("head"),
                                         leftArm: instance.bone("upper_arm.L"), rightArm: instance.bone("upper_arm.R"), capybaraRig: instance)
            for node in avatar.poseAnchors {
                let child = node.childNodes.first
                let direction = child.map { simd_normalize($0.simdWorldPosition - node.simdWorldPosition) } ?? SIMD3<Float>(0,1,0)
                avatar.bindings[ObjectIdentifier(node)] = .init(local: node.simdOrientation, world: node.simdWorldOrientation,
                    parentWorld: node.parent?.simdWorldOrientation ?? simd_quatf(angle: 0, axis: SIMD3(0,1,0)), direction: direction)
            }
            return avatar
        } catch {
            // Keep asset failures visible rather than silently bringing back the old character.
            let root = SCNNode()
            let text = SCNText(string: "Capybara unavailable", extrusionDepth: 0)
            text.font = .systemFont(ofSize: 12); text.materials = [material(.systemOrange, constant: true)]
            let label = SCNNode(geometry: text);label.scale = SCNVector3(0.025,0.025,0.025);label.position.y = 1
            root.addChildNode(label)
            return WorkspaceAvatar(root: root, body: nil, head: nil, leftArm: nil, rightArm: nil)
        }
    }

    static func material(_ color: NSColor, constant: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = constant ? .constant : .lambert
        return material
    }

    static func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, at position: SCNVector3,
                    material: SCNMaterial, bevel: CGFloat = 0) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: bevel)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }
}

final class WorkspaceWorkstation {
    let root = SCNNode()
    let avatar: WorkspaceAvatar
    private let screen = WorkspaceAvatarFactory.material(.systemTeal, constant: true)
    private let label = SCNNode()
    private let selection = SCNNode()
    private var lastAgent: WorkspaceAgent?
    let motion = WorkspaceAvatarMotion()
    var animating: Bool { motion.animating }
    var animationChanged: (() -> Void)? {
        get { motion.animationChanged }
        set { motion.animationChanged = newValue }
    }

    init(id: String, index: Int) {
        root.name = "agent:" + id
        let palette: [NSColor] = [
            .init(srgbRed: 0.69, green: 0.47, blue: 0.91, alpha: 1),
            .init(srgbRed: 0.29, green: 0.76, blue: 0.69, alpha: 1),
            .init(srgbRed: 0.94, green: 0.63, blue: 0.33, alpha: 1),
            .init(srgbRed: 0.39, green: 0.65, blue: 0.94, alpha: 1),
            .init(srgbRed: 0.89, green: 0.46, blue: 0.64, alpha: 1)
        ]
        let color = palette[index % palette.count]
        avatar = WorkspaceAvatarFactory.capybara()
        avatar.root.position = SCNVector3(0, 0.2, -0.95)
        root.addChildNode(avatar.root)
        let wood = WorkspaceAvatarFactory.material(NSColor(srgbRed: 0.38, green: 0.29, blue: 0.24, alpha: 1))
        let steel = WorkspaceAvatarFactory.material(NSColor(white: 0.16, alpha: 1))
        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: Double, _ y: Double, _ z: Double,
                 _ material: SCNMaterial, bevel: CGFloat = 0.03) {
            root.addChildNode(WorkspaceAvatarFactory.box(w, h, d, at: SCNVector3(x, y, z), material: material, bevel: bevel))
        }
        box(3.4, 0.18, 1.65, 0, 1.27, 0.4, wood, bevel: 0.06)
        for x in [-1.4, 1.4] {
            for z in [-0.18, 0.98] { box(0.13, 1.15, 0.13, x, 0.59, z, steel) }
        }
        // Seat and back support behind the capybara.
        box(1.1, 0.17, 1.05, 0, 0.82, -0.95, steel, bevel: 0.08)
        box(0.17, 0.8, 0.17, 0, 0.4, -0.95, steel)
        box(1.1, 0.8, 0.14, 0, 1.32, -1.5, steel, bevel: 0.08)
        box(1.15, 0.055, 0.36, 0, 1.39, -0.35, steel)
        let keys = WorkspaceAvatarFactory.material(NSColor(white: 0.40, alpha: 1))
        for row in 0..<3 {
            box(0.86, 0.012, 0.022, 0, 1.424, -0.46 + Double(row) * 0.1, keys, bevel: 0)
        }
        box(0.38, 0.07, 0.4, -0.91, 1.4, 0.83, steel)
        box(0.10, 0.32, 0.10, -0.91, 1.57, 0.83, steel)
        box(1.20, 0.79, 0.13, -0.91, 1.98, 0.83, steel, bevel: 0.05)
        box(1.06, 0.65, 0.015, -0.91, 1.98, 0.755, screen, bevel: 0.02)
        // Rear indicator remains visible when the camera sees the back of the monitor.
        box(0.18, 0.045, 0.02, -0.47, 1.70, 0.91, screen, bevel: 0.01)

        let ring = SCNTorus(ringRadius: 1.9, pipeRadius: 0.035)
        ring.materials = [WorkspaceAvatarFactory.material(color, constant: true)]
        selection.geometry = ring
        selection.position.y = 0.055
        selection.isHidden = true
        root.addChildNode(selection)

        label.position = SCNVector3(0, 4.0, 0)
        label.constraints = [SCNBillboardConstraint()]
        root.addChildNode(label)
    }

    func update(_ agent: WorkspaceAgent, selected: Bool, reduceMotion: Bool, active: Bool,
                cameraYaw: Double = 0) {
        selection.isHidden = !selected
        if lastAgent != agent {
            lastAgent = agent
            let live = (agent.freshness == .live || agent.freshness == .recentlyObserved)
            screen.diffuse.contents = agent.isWorking ? NSColor.systemTeal
                : live && agent.status == .failed ? NSColor.systemRed
                : live && agent.status == .waiting ? NSColor.systemOrange : NSColor(white: 0.22, alpha: 1)
            let plane = SCNPlane(width: 5.2, height: agent.overheadMessage == nil ? 0.78 : 1.5)
            let material = SCNMaterial()
            material.diffuse.contents = Self.labelImage(agent)
            material.lightingModel = .constant
            material.isDoubleSided = true
            plane.materials = [material]
            label.geometry = plane
        }
        motion.update(agent, avatar: avatar, reduceMotion: reduceMotion, active: active, cameraYaw: cameraYaw)
    }

    func setMovementLab(_ enabled: Bool) { label.isHidden = enabled }

    private static func labelImage(_ agent: WorkspaceAgent) -> NSImage {
        let size = NSSize(width: 600, height: agent.overheadMessage == nil ? 90 : 174)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: 0.08, green: 0.075, blue: 0.09, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 18, yRadius: 18).fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        func line(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
            (text as NSString).draw(in: NSRect(x: 20, y: y, width: 560, height: 76),
                                   withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        }
        line(agent.name, y: agent.overheadMessage == nil ? 6 : 90, font: .systemFont(ofSize: 64, weight: .semibold), color: .white)
        let color: NSColor = agent.status == .failed ? .systemRed : agent.status == .waiting ? .systemOrange : .lightGray
        if let message = agent.overheadMessage {
            line(message, y: 10, font: .systemFont(ofSize: 44, weight: .medium),
                 color: (agent.freshness == .live || agent.freshness == .recentlyObserved) ? color : .lightGray)
        }
        image.unlockFocus()
        return image
    }
}
