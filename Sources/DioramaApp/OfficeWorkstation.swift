import AppKit
import SceneKit
import ModelIO
import SceneKit.ModelIO
import simd

/// Shared immutable meshes; cloned nodes retain the manufacturer's actual metre proportions.
enum OfficeFurnitureAssets {
    static let loaded = loadModels(suffix: "")
    static let low = loadModels(suffix: "Low")
    static let lowAvatar: WorkspaceCapybaraAsset? = {
        let bundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Diorama_DioramaApp.bundle")) } ?? Bundle.module
        guard let url = bundle.url(forResource: "CapybaraOfficeLow", withExtension: "glb", subdirectory: "OfficeFurniture") else { return nil }
        return try? WorkspaceCapybaraAsset(data: Data(contentsOf: url))
    }()
    private static func loadModels(suffix: String) -> Result<(chair: SCNNode, desk: SCNNode), Error> { Result {
        let bundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Diorama_DioramaApp.bundle")) } ?? Bundle.module
        func load(_ name: String) throws -> SCNNode {
            guard let url = bundle.url(forResource: name, withExtension: "obj", subdirectory: "OfficeFurniture") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let asset = MDLAsset(url: url)
            for mesh in asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? [] {
                mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
            }
            let root = SCNScene(mdlAsset: asset).rootNode
            root.enumerateChildNodes { node, _ in
                if let geometry = node.geometry, geometry.materials.isEmpty { geometry.materials = [SCNMaterial()] }
                node.geometry?.materials = node.geometry?.materials.map { $0.copy() as! SCNMaterial } ?? []
                for material in node.geometry?.materials ?? [] {
                    // ModelIO handles Blender's MTL ambient defaults differently from the
                    // source OBJ. Apply one neutral finish consistently at both detail levels.
                    let part = material.name ?? node.name ?? ""
                    if name.hasPrefix("Aeron") {
                        material.diffuse.contents = NSColor(white: part.contains("FABRIC") ? 0.22 : 0.13, alpha: 1)
                    } else {
                        // White laminate top, silver-gray base, dark leveling glides.
                        let white: CGFloat = part.contains("TOP") ? 0.94 : part.contains("GLIDES") ? 0.12 : 0.62
                        material.diffuse.contents = NSColor(srgbRed: white, green: white, blue: white, alpha: 1)
                    }
                    material.emission.contents = NSColor.black
                    material.lightingModel = .lambert
                    material.ambient.contents = material.diffuse.contents
                    material.locksAmbientWithDiffuse = true
                    material.isDoubleSided = true
                }
            }
            return root
        }
        return (try load("AeronESD" + suffix), try load("NeviC" + suffix))
    }
    }
}

/// Empty capacity has furniture only: no agent, activity indicator, or navigation target.
final class EmptyOfficeDesk {
    let root = SCNNode()
    private let low = SCNNode()
    private var high: SCNNode?
    init() {
        if case .success(let models) = OfficeFurnitureAssets.low {
            let chair = models.chair.clone(); chair.position.z = -0.275
            low.addChildNode(chair); low.addChildNode(models.desk.clone()); root.addChildNode(low)
        }
    }
    func setDistant(_ distant: Bool) {
        if !distant && high == nil, case .success(let models) = OfficeFurnitureAssets.loaded {
            let node = SCNNode(), chair = models.chair.clone(); chair.position.z = -0.275
            node.addChildNode(chair); node.addChildNode(models.desk.clone()); high = node; root.addChildNode(node)
        }
        low.isHidden = !distant && high != nil; high?.isHidden = distant
    }
}

/// Office-only seated pose. It doesn't change the avatar used in other Diorama surfaces.
final class OfficeWorkstation {
    let root = SCNNode()
    let avatar: WorkspaceAvatar
    let monitor = SCNNode()
    let label = SCNNode()
    private let selection = SCNNode()
    private let lowFurniture = SCNNode()
    private var lastLabel = ""
    private var lastScreenState: Int?
    private var armRest: [(SCNNode, simd_quatf)] = []
    private(set) var animating = false
    private(set) var assetsAvailable = false
    private let screen = WorkspaceAvatarFactory.material(.darkGray, constant: true)
    let chair: SCNNode?
    let desk: SCNNode?
    var animationChanged: (() -> Void)?

    init(id: String) {
        root.name = "agent:" + id
        avatar = WorkspaceAvatarFactory.capybara(height: 1.17, asset: OfficeFurnitureAssets.lowAvatar)
        // 30% larger uniformly, anchored around the chair seat rather than the feet.
        avatar.root.position = SCNVector3(0, 0.2364, -0.10)
        root.addChildNode(avatar.root)
        switch OfficeFurnitureAssets.loaded {
        case .success(let models):
            let chairNode = models.chair.clone(), deskNode = models.desk.clone()
            chairNode.name = "Aeron ESD · C size · height-adjustable arms"
            deskNode.name = "Nevi · C foot"
            chairNode.position.z = -0.275
            root.addChildNode(chairNode); root.addChildNode(deskNode)
            chair = chairNode; desk = deskNode; assetsAvailable = true
        case .failure:
            chair = nil; desk = nil
        }
        if case .success(let models) = OfficeFurnitureAssets.low {
            let chair = models.chair.clone(); chair.position.z = -0.275
            lowFurniture.addChildNode(chair); lowFurniture.addChildNode(models.desk.clone())
            root.addChildNode(lowFurniture); lowFurniture.isHidden = true
        }
        let steel = WorkspaceAvatarFactory.material(NSColor(white: 0.12, alpha: 1))
        let keys = WorkspaceAvatarFactory.material(NSColor(white: 0.36, alpha: 1))
        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: Double, _ y: Double, _ z: Double, _ material: SCNMaterial) -> SCNNode {
            WorkspaceAvatarFactory.box(w, h, d, at: SCNVector3(x,y,z), material: material, bevel: 0.007)
        }
        root.addChildNode(box(0.34,0.018,0.12,0,0.737,0.045,steel))
        for row in 0..<3 { root.addChildNode(box(0.30,0.004,0.009,0,0.748,0.01+Double(row)*0.03,keys)) }
        root.addChildNode(box(0.20,0.018,0.15,0,0.736,0.51,steel))
        root.addChildNode(box(0.04,0.14,0.04,0,0.81,0.53,steel))
        monitor.name = "screen:" + id
        monitor.addChildNode(box(0.49,0.30,0.025,0,0.98,0.53,steel))
        monitor.addChildNode(box(0.46,0.27,0.004,0,0.98,0.515,screen))
        root.addChildNode(monitor)
        let ring = SCNTorus(ringRadius: 0.53, pipeRadius: 0.013)
        ring.materials = [WorkspaceAvatarFactory.material(.systemTeal, constant: true)]
        selection.geometry = ring; selection.position = SCNVector3(0,0.02,-0.25)
        root.addChildNode(selection)
        label.position = SCNVector3(0,1.55,0.1)
        label.constraints = [SCNBillboardConstraint()]
        root.addChildNode(label)
        fitPaws()
    }

    /// Two-bone reach uses authored bone lengths, never stretched limbs or a distorted avatar.
    private func fitPaws() {
        guard let rig = avatar.capybaraRig else { return }
        for side in ["L", "R"] {
            guard let upper = rig.bone("upper_arm." + side), let lower = rig.bone("lower_arm." + side),
                  let hand = rig.bone("hand." + side) else { continue }
            let start = upper.simdWorldPosition
            let a = simd_length(lower.simdWorldPosition-start), b = simd_length(hand.simdWorldPosition-lower.simdWorldPosition)
            let target = SIMD3<Float>(side == "L" ? 0.125 : -0.125, 0.765, 0.015)
            let delta = target-start, direction = simd_normalize(delta)
            let distance = min(a+b-0.0001, max(abs(a-b)+0.0001, simd_length(delta)))
            let along = (a*a-b*b+distance*distance)/(2*distance)
            let bend = simd_normalize(simd_cross(direction,SIMD3<Float>(0,0,side == "L" ? 1 : -1)))
            let elbow = start + direction*along + bend*sqrt(max(0,a*a-along*along))
            upper.simdWorldOrientation = simd_quatf(from: simd_normalize(lower.simdWorldPosition-start), to: simd_normalize(elbow-start)) * upper.simdWorldOrientation
            let wrist = start + direction*distance
            lower.simdWorldOrientation = simd_quatf(from: simd_normalize(hand.simdWorldPosition-lower.simdWorldPosition), to: simd_normalize(wrist-lower.simdWorldPosition)) * lower.simdWorldOrientation
            armRest.append((upper,upper.simdOrientation))
        }
    }

    func update(_ occupant: OfficeOccupant, selected: Bool, reduced: Bool, active: Bool, distant: Bool) {
        selection.isHidden = !selected
        let useLow = distant && !selected && !lowFurniture.childNodes.isEmpty
        chair?.isHidden = useLow; desk?.isHidden = useLow; lowFurniture.isHidden = !useLow
        let agent = occupant.agent.value
        let screenState = agent.isWorking ? 1 : occupant.agent.needsAttention ? 2 : 0
        if lastScreenState != screenState {
            lastScreenState = screenState
            screen.diffuse.contents = screenState == 1 ? NSColor.systemTeal : screenState == 2 ? NSColor.systemOrange : NSColor(white:0.22,alpha:1)
        }
        let text = occupant.assignment + "\n" + agent.name + " · " + agent.statusLabel
        if text != lastLabel {
            lastLabel = text
            label.geometry = Self.labelGeometry(title: occupant.assignment, status: assetsAvailable ? Self.stateLabel(agent) : "Furniture assets unavailable")
        }
        label.isHidden = distant && !selected && !occupant.agent.needsAttention
        let shouldAnimate = active && !reduced && agent.isWorking
        guard shouldAnimate != animating else { return }
        animating = shouldAnimate
        for (index,pair) in armRest.enumerated() {
            let (node,rest) = pair
            node.removeAllActions(); node.simdOrientation = rest
            if shouldAnimate {
                func pose(_ angle: Float) -> SCNAction {
                    let q = rest * simd_quatf(angle: angle, axis: SIMD3(1,0,0))
                    return .rotate(toAxisAngle: SCNVector4(q.axis.x,q.axis.y,q.axis.z,q.angle), duration: 0.325)
                }
                let sign: Float = index == 0 ? 1 : -1
                node.runAction(.repeatForever(.sequence([pose(sign * 0.025),pose(-sign * 0.025)])),forKey:"seatedTyping")
            }
        }
        animationChanged?()
    }
    func suspend() {
        animating = false
        for (node,rest) in armRest { node.removeAllActions(); node.simdOrientation = rest }
    }
    private static func stateLabel(_ agent: WorkspaceAgent) -> String {
        if ![.live,.recentlyObserved].contains(agent.freshness) { return "◷ " + agent.statusLabel }
        switch agent.status {
        case .working: return "● Working"
        case .waiting: return agent.attentionReason == .approval ? "! Approval needed" : agent.attentionReason == .input ? "? Input needed" : "◷ Waiting"
        case .failed: return "! Failed"
        case .done: return "✓ Turn finished"
        default: return "– " + agent.statusLabel
        }
    }
    private static func labelGeometry(title: String, status: String) -> SCNGeometry {
        let image = NSImage(size: NSSize(width:480,height:112)); image.lockFocus()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect:NSRect(x:0,y:0,width:480,height:112),xRadius:12,yRadius:12).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in:NSRect(x:12,y:57,width:456,height:43),withAttributes:[.font:NSFont.systemFont(ofSize:29,weight:.semibold),.foregroundColor:NSColor.darkGray,.paragraphStyle:paragraph])
        (status as NSString).draw(in:NSRect(x:12,y:10,width:456,height:38),withAttributes:[.font:NSFont.systemFont(ofSize:26),.foregroundColor:NSColor.darkGray,.paragraphStyle:paragraph])
        image.unlockFocus()
        let plane = SCNPlane(width:1.65,height:0.385)
        let material = WorkspaceAvatarFactory.material(.white,constant:true); material.diffuse.contents=image;material.isDoubleSided=true
        plane.materials=[material]; return plane
    }
}
