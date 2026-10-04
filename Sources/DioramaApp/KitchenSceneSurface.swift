import SceneKit
import SwiftUI

enum WorkspaceSceneKind: String, CaseIterable { case office = "Office", kitchen = "Kitchen" }

struct KitchenArea: Identifiable {
    let id: String
    let label: String
    let footprint: CGRect // X/Z coordinates on the floor.
    let accent: NSColor
    var center: SCNVector3 { SCNVector3(footprint.midX, 0.6, footprint.midY) }
}
enum KitchenLayout {
    static let floor = CGRect(x: -8, y: -6, width: 16, height: 12)
    // Connect the working stations without crossing the island's circulation aisle.
    static let connectors: [CGRect] = [
        .init(x: -2.1, y: -5.1, width: 3.3, height: 1.4),
        .init(x: -6.9, y: -3.7, width: 1.4, height: 7.4),
        .init(x: 6, y: -5.1, width: 1.05, height: 1.4),
        .init(x: 5.55, y: -3.7, width: 1.5, height: 2.2),
        .init(x: 5.55, y: 1.5, width: 1.5, height: 2.2),
        .init(x: 5.85, y: 3.7, width: 1.2, height: 1.4),
        .init(x: -6.9, y: 3.7, width: 0.4, height: 1.4)
    ]
    static let areas: [KitchenArea] = [
        .init(id: "context", label: "Context Storage", footprint: .init(x: -6.9, y: -5.1, width: 4.8, height: 1.4), accent: .init(red: 0.56, green: 0.67, blue: 0.61, alpha: 1)),
        .init(id: "build", label: "Builds / Commands", footprint: .init(x: 1.2, y: -5.1, width: 4.8, height: 1.4), accent: .init(red: 0.69, green: 0.59, blue: 0.47, alpha: 1)),
        .init(id: "prep", label: "Prep / Planning / Editing", footprint: .init(x: -2.5, y: -1.25, width: 5, height: 2.5), accent: .init(red: 0.57, green: 0.64, blue: 0.72, alpha: 1)),
        .init(id: "test", label: "Test / QA", footprint: .init(x: 5.55, y: -1.5, width: 1.5, height: 3), accent: .init(red: 0.64, green: 0.59, blue: 0.72, alpha: 1)),
        .init(id: "attention", label: "Human Attention", footprint: .init(x: -6.5, y: 3.7, width: 3.6, height: 1.4), accent: .init(red: 0.75, green: 0.58, blue: 0.47, alpha: 1)),
        .init(id: "review", label: "Ready for Review", footprint: .init(x: 1.35, y: 3.7, width: 4.5, height: 1.4), accent: .init(red: 0.51, green: 0.67, blue: 0.66, alpha: 1))
    ]
}
struct KitchenSceneSurface: NSViewRepresentable {
    var agents: [SpatialAgent] = []
    var active = false
    var reducedMotion = false
    var select: (SpatialFocus) -> Void = { _ in }
    func makeNSView(context: Context) -> KitchenSceneView { KitchenSceneView() }
    func updateNSView(_ view: KitchenSceneView, context: Context) {
        view.select = select
        view.apply(agents: agents, active: active, reducedMotion: reducedMotion)
        view.fitFloor()
    }
    static func dismantleNSView(_ view: KitchenSceneView, coordinator: ()) { view.tearDown() }
}
@MainActor private final class KitchenFrameDriver: NSObject {
    weak var view: KitchenSceneView?
    @objc func frame(_ link: CADisplayLink) { view?.frameStep(at: link.targetTimestamp) }
}
private final class KitchenLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Kitchen workspace: the focused project's agents appear as chefs working at the station that
/// matches their state. It only observes agent state; it never controls provider execution.
final class KitchenSceneView: SCNView {
    static let maxChefs = 12
    let floorSize = SIMD3<Float>(16, 0.2, 12)
    var select: ((SpatialFocus) -> Void)?
    private(set) var chefs: [String: ChefAvatar] = [:]
    private var chefAgents: [String: SpatialAgent] = [:]
    private var chefLabels: [String: NSTextField] = [:]
    private var slots: [String: ChefStation] = [:]
    private let navigation = KitchenLayout.chefNavigation
    private var active = false
    private var reduced = false
    private var frameLink: CADisplayLink?
    private var frameDriver: KitchenFrameDriver?
    private var lastFrame: TimeInterval?
    private var windowObservers: [NSObjectProtocol] = []
    private var labels: [NSTextField] = []
    private let leaders = CAShapeLayer()
    private var fittedSize = CGSize.zero
    var labelFrames: [CGRect] { labels.map(\.frame) }
    override init(frame: NSRect = .zero, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        let world = SCNScene()
        world.background.contents = NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.92, alpha: 1)
        func material(_ color: NSColor) -> SCNMaterial {
            let value = SCNMaterial(); value.diffuse.contents = color; value.roughness.contents = 0.9; return value
        }
        func box(_ name: String, width: CGFloat, height: CGFloat, depth: CGFloat, at position: SCNVector3, material: SCNMaterial) -> SCNNode {
            let shape = SCNBox(width: width, height: height, length: depth, chamferRadius: min(0.07, height / 3))
            shape.materials = [material]
            let node = SCNNode(geometry: shape); node.name = name; node.position = position
            world.rootNode.addChildNode(node); return node
        }
        _ = box("Kitchen floor", width: 16, height: 0.2, depth: 12, at: SCNVector3Zero, material: material(.init(white: 0.71, alpha: 1)))
        world.rootNode.addChildNode(KitchenRoomGeometry.make())
        for (index, area) in KitchenLayout.areas.enumerated() {
            world.rootNode.addChildNode(KitchenStationGeometry.make(area))
            let shortNames = ["Context", "Build", "Prep", "QA", "Attention", "Review"]
            let label = KitchenLabel(labelWithString: "\(index + 1) · \(shortNames[index])")
            label.toolTip = area.label; label.setAccessibilityLabel(area.label)
            label.font = .systemFont(ofSize: 11, weight: .medium); label.textColor = .init(white: 0.18, alpha: 1)
            label.alignment = .center; label.maximumNumberOfLines = 3; label.lineBreakMode = .byWordWrapping
            label.wantsLayer = true; label.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
            label.layer?.cornerRadius = 5
            labels.append(label); addSubview(label)
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = false
        camera.camera?.projectionDirection = .vertical
        camera.camera?.fieldOfView = 38; camera.camera?.zNear = 0.1; camera.camera?.zFar = 200
        // Overcooked-style framing: elevated front view with screen-aligned aisles.
        let elevation = 62.0 * Double.pi / 180, yaw = 0.0
        camera.position = SCNVector3(30 * cos(elevation) * sin(yaw), 30 * sin(elevation), 30 * cos(elevation) * cos(yaw))
        camera.look(at: SCNVector3(0, 0.65, 0)); world.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient; ambient.light?.intensity = 180
        ambient.light?.color = NSColor(red: 1, green: 0.97, blue: 0.91, alpha: 1)
        world.rootNode.addChildNode(ambient)
        let daylight = SCNNode(); daylight.light = SCNLight()
        daylight.light?.type = .directional; daylight.light?.intensity = 1100
        daylight.light?.castsShadow = true; daylight.light?.shadowRadius = 4
        daylight.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        daylight.light?.orthographicScale = 22
        daylight.light?.shadowColor = NSColor(white: 0.08, alpha: 0.48)
        daylight.position = SCNVector3(-8, 12, -5); daylight.look(at: SCNVector3Zero)
        world.rootNode.addChildNode(daylight)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light?.type = .directional; fill.light?.intensity = 240
        fill.light?.color = NSColor(red: 0.82, green: 0.89, blue: 1, alpha: 1)
        fill.position = SCNVector3(8, 6, 8); fill.look(at: SCNVector3Zero)
        world.rootNode.addChildNode(fill)
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.65
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.4
        scene = world; pointOfView = camera; autoenablesDefaultLighting = false
        allowsCameraControl = false; isPlaying = false; rendersContinuously = false
        wantsLayer = true; leaders.strokeColor = NSColor.darkGray.withAlphaComponent(0.25).cgColor
        leaders.fillColor = nil; leaders.lineWidth = 1; layer?.addSublayer(leaders)
        setAccessibilityLabel("Kitchen layout. Context Storage, Builds and Commands, central Prep Planning Editing island, Test and QA, Human Attention, Ready for Review.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); fitFloor() }

    // MARK: Chefs

    /// Reconcile chefs with agents: attention first, then working, capped at `maxChefs`.
    func apply(agents: [SpatialAgent], active: Bool, reducedMotion: Bool) {
        self.active = active; reduced = reducedMotion
        let ranked = agents.enumerated().sorted { a, b in
            let ra = a.element.needsAttention ? 0 : a.element.value.status == .working ? 1 : 2
            let rb = b.element.needsAttention ? 0 : b.element.value.status == .working ? 1 : 2
            return ra != rb ? ra < rb : a.offset < b.offset
        }.prefix(Self.maxChefs).map(\.element)
        let ids = Set(ranked.map(\.id))
        for id in chefs.keys where !ids.contains(id) {
            chefs.removeValue(forKey: id)?.root.removeFromParentNode()
            chefLabels.removeValue(forKey: id)?.removeFromSuperview()
            chefAgents[id] = nil; slots[id] = nil
        }
        guard !ranked.isEmpty, case let .success(assets) = ChefAssets.shared, let world = scene else { updatePlayback(); return }
        slots = KitchenLayout.assignSlots(ranked.map { ($0.id, KitchenLayout.work(for: $0.value).area) }, previous: slots)
        let table = KitchenLayout.chefSlots, pickup = table["test"]?.first, home = table["home"] ?? []
        for agent in ranked {
            chefAgents[agent.id] = agent
            if let chef = chefs[agent.id] {
                chef.director.reducedMotion = reduced
                chef.director.setIntent(KitchenLayout.intent(for: agent.value, at: slots[agent.id], pickup: pickup, restored: false))
            } else {
                // New chefs start at their station in their current state: no walk-in, no replayed gesture.
                let chef = ChefAvatar(id: agent.id, assets: assets, scale: KitchenLayout.chefScale, navigation: navigation)
                chef.director.reducedMotion = reduced
                let spawn = slots[agent.id] ?? (home.isEmpty ? nil : home[chefs.count % home.count])
                if let spawn { chef.director.place(spawn.stand, heading: spawn.facing) }
                chef.director.setIntent(KitchenLayout.intent(for: agent.value, at: slots[agent.id], pickup: pickup, restored: true))
                chef.update(0)
                world.rootNode.addChildNode(chef.root); chefs[agent.id] = chef
                let label = KitchenLabel(labelWithString: "")
                label.font = .systemFont(ofSize: 10, weight: .semibold); label.alignment = .center
                label.wantsLayer = true; label.layer?.cornerRadius = 4
                label.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
                chefLabels[agent.id] = label; addSubview(label)
            }
            let label = chefLabels[agent.id]
            label?.stringValue = agent.value.name + " · " + agent.value.statusLabel
            label?.textColor = agent.needsAttention ? .systemOrange : .init(white: 0.2, alpha: 1)
        }
        placeChefLabels()
        updatePlayback()
        needsDisplay = true
    }
    func frameStep(at time: TimeInterval) {
        let delta = lastFrame.map { Float(min(0.05, max(0, time - $0))) } ?? 0
        lastFrame = time
        for chef in chefs.values { chef.update(delta) }
        placeChefLabels()
        updatePlayback()
    }
    private var effectiveActive: Bool { active && (window == nil || window?.occlusionState.contains(.visible) == true) }
    func updatePlayback() {
        let moving = effectiveActive && chefs.values.contains(where: \.animating)
        if isPlaying != moving { isPlaying = moving }
        if rendersContinuously != moving { rendersContinuously = moving }
        if frameLink?.isPaused != !moving { frameLink?.isPaused = !moving }
        if !moving { lastFrame = nil }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        guard let window else { return }
        let driver = KitchenFrameDriver(); driver.view = self; frameDriver = driver
        let link = displayLink(target: driver, selector: #selector(KitchenFrameDriver.frame(_:)))
        link.add(to: .main, forMode: .common); frameLink = link
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlayback() }
        })
        updatePlayback()
    }
    func tearDown() {
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        scene = nil
    }
    private func placeChefLabels() {
        for (id, chef) in chefs {
            guard let label = chefLabels[id] else { continue }
            let head = chef.root.simdPosition + SIMD3(0, 2.05 * KitchenLayout.chefScale, 0)
            let point = projectPoint(SCNVector3(head))
            let size = label.attributedStringValue.size()
            let width = min(160, size.width + 12), height = size.height + 4
            let y = isFlipped ? bounds.height - CGFloat(point.y) : CGFloat(point.y)
            label.frame = CGRect(x: CGFloat(point.x) - width / 2, y: y, width: width, height: height)
        }
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("agent:"), let agent = chefAgents[String(name.dropFirst(6))] {
                    select?(.agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true))
                    return
                }
                node = current.parent
            }
        }
        super.mouseUp(with: event)
    }
    var floorCorners: [SCNVector3] {
        var result: [SCNVector3] = []
        let signs: [Float] = [-1, 1]
        for x in signs { for y in signs { for z in signs { result.append(SCNVector3(x * 8, y * 0.1, z * 6)) } } }
        return result
    }
    var framingPoints: [SCNVector3] {
        var points: [SCNVector3] = []
        for name in KitchenLayout.areas.map(\.id) {
            guard let node = scene?.rootNode.childNode(withName: name, recursively: false) else { continue }
            let (low, high) = node.boundingBox
            for x in [low.x, high.x] { for y in [low.y, high.y] { for z in [low.z, high.z] {
                points.append(node.convertPosition(SCNVector3(x, y, z), to: nil))
            } } }
        }
        return points
    }
    func fitFloor() {
        guard bounds.width > 1, bounds.height > 1, let camera = pointOfView else { return }
        guard fittedSize != bounds.size else { placeLabels(); return }
        fittedSize = bounds.size
        let points = framingPoints
        let elevation = 62.0 * Double.pi / 180
        let target = SCNVector3(0, 0.65, 0)
        func position(_ distance: Double) {
            camera.position = SCNVector3(0, 0.65 + distance * sin(elevation), distance * cos(elevation))
            camera.look(at: target)
        }
        // Fit the usable stations, not the decorative room envelope. Perspective
        // keeps the foreground substantial; only the outer scenery may crop.
        let tangentY = tan(19.0 * Double.pi / 180)
        let tangentX = tangentY * Double(bounds.width / bounds.height)
        let availableX = max(0.1, 1 - 20 / Double(bounds.width))
        let availableY = max(0.1, 1 - 56 / Double(bounds.height))
        // Solve in camera space; SceneKit's presentation projection can lag
        // node mutations until rendering and cannot drive an iterative fit.
        let distance = points.reduce(5.0) { distance, point in
            let y = Double(point.y) - 0.65, z = Double(point.z)
            let cameraY = y * cos(elevation) - z * sin(elevation)
            let towardCamera = y * sin(elevation) + z * cos(elevation)
            return max(distance,
                       towardCamera + abs(Double(point.x)) / (tangentX * availableX),
                       towardCamera + abs(cameraY) / (tangentY * availableY))
        }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        position(distance)
        SCNTransaction.commit()
        SCNTransaction.flush()
        placeLabels(); needsDisplay = true
    }
    private func placeLabels() {
        var occupied: [CGRect] = []
        let path = CGMutablePath()
        for (index, area) in KitchenLayout.areas.enumerated() {
            let point = projectPoint(SCNVector3(area.footprint.midX, area.id == "context" ? 3.5 : 2.3, area.footprint.minY))
            let anchor = CGPoint(x: CGFloat(point.x), y: isFlipped ? bounds.height - CGFloat(point.y) : CGFloat(point.y))
            let width: CGFloat = min(110, labels[index].attributedStringValue.size().width + 14)
            let size = labels[index].cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width - 8, height: 100)) ?? CGSize(width: width, height: 32)
            let height = max(20, size.height + 4)
            func candidate(_ offset: CGFloat) -> CGRect {
                CGRect(x: min(max(8, anchor.x - width / 2), max(8, bounds.width - width - 8)),
                       y: min(max(8, anchor.y + offset - height / 2), max(8, bounds.height - height - 8)), width: width, height: height)
            }
            var frame = candidate(0)
            for step in 0..<20 {
                let offset = CGFloat((step + 1) / 2) * (height + 6) * (step % 2 == 0 ? -1 : 1)
                let proposed = candidate(offset)
                if !occupied.contains(where: { $0.insetBy(dx: -4, dy: -4).intersects(proposed) }) { frame = proposed; break }
            }
            labels[index].frame = frame; occupied.append(frame)
            path.move(to: anchor); path.addLine(to: CGPoint(x: frame.midX, y: frame.midY))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        leaders.frame = bounds; leaders.path = path
        CATransaction.commit()
    }
}
