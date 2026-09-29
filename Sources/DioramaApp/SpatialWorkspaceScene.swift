import SwiftUI
import SceneKit

struct SpatialCameraPose: Equatable {
    var x = 0.0
    var y = 0.0
    var z = 0.0
    var scale = 30.0
    var yaw = Double.pi / 4
    var elevation = Double.pi / 5
    func interpolated(to end: Self, fraction: Double) -> Self {
        let t = min(1, max(0, fraction))
        let eased = t * t * (3 - 2 * t)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * eased }
        return Self(x: mix(x, end.x), y: mix(y, end.y), z: mix(z, end.z), scale: mix(scale, end.scale),
                    yaw: mix(yaw, end.yaw), elevation: mix(elevation, end.elevation))
    }
}

struct SpatialSceneSurface: NSViewRepresentable {
    var world: SpatialWorld
    var focus: SpatialFocus
    var active: Bool
    var reducedMotion: Bool
    var reset: Int
    var page: Int
    var select: (SpatialFocus) -> Void
    var screenAnchor: (CGPoint) -> Void
    func makeNSView(context: Context) -> SpatialSceneView { SpatialSceneView() }
    func updateNSView(_ view: SpatialSceneView, context: Context) {
        view.select = select
        view.screenAnchor = screenAnchor
        view.apply(world: world, focus: focus, active: active, reducedMotion: reducedMotion, reset: reset, page: page)
    }
    static func dismantleNSView(_ view: SpatialSceneView, coordinator: ()) { view.tearDown() }
}

final class SpatialSceneView: SCNView {
    var select: ((SpatialFocus) -> Void)?
    var screenAnchor: ((CGPoint) -> Void)?
    private(set) var pose = SpatialCameraPose()
    private(set) var workstations: [String: WorkspaceWorkstation] = [:]
    private(set) var officeWorkstations: [String: OfficeWorkstation] = [:]
    private(set) var emptyOfficeDesks: [Int: EmptyOfficeDesk] = [:]
    private(set) var officeLayouts: [String: SharedOfficeLayout] = [:]
    private var officeOccupants: [OfficeOccupant] = []
    private var officeProject: String?
    private(set) var projectSlots = SpatialSlots()
    private var teamSlots: [String: SpatialSlots] = [:]
    private var agentSlots: [String: SpatialSlots] = [:]
    private let camera = SCNNode()
    private let content = SCNNode()
    let meadow = OfficeMeadow()
    private var nodes: [String: SCNNode] = [:]
    private var labelValues: [String: String] = [:]
    private var targets: [String: SpatialFocus] = [:]
    private var world = SpatialWorld()
    private var focus: SpatialFocus?
    private var reset = -1
    private var page = 0
    private var active = true
    private var reduced = false
    private var frameLink: CADisplayLink?
    private var frameDriver: SceneFrameDriver?
    private var windowObservers: [NSObjectProtocol] = []
    private var pendingCamera = false
    private var distantFurniture = true
    private var quality = SceneQualityPolicy()
    private var requestedFPS = 120
    private var lastLinkFPS = 0
    private let sun = SCNNode()
    let frameTelemetry = SceneFrameTelemetry()
    private let gpuProbe = SceneGPUProbe()
    private var lastQualitySample = 0.0
    var frameObserved: ((Double) -> Void)?
    private var escapeMonitor: Any?
    private var travel: (start: SpatialCameraPose, end: SpatialCameraPose, time: TimeInterval)?
    private var lastPoint = NSPoint.zero
    private var dragged = 0.0
    private var framePose = SpatialCameraPose()

    init() {
        super.init(frame: .zero, options: nil)
        scene = SCNScene()
        delegate = frameTelemetry
        backgroundColor = NSColor(srgbRed: 0.91, green: 0.94, blue: 0.95, alpha: 1)
        antialiasingMode = .multisampling4X
        allowsCameraControl = false
        preferredFramesPerSecond = 120
        scene?.rootNode.addChildNode(content)
        scene?.rootNode.addChildNode(meadow.root)
        meadow.root.isHidden = true
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 10000
        scene?.rootNode.addChildNode(camera)
        pointOfView = camera
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 450
        scene?.rootNode.addChildNode(ambient)
        sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 650
        sun.eulerAngles = SCNVector3(-0.8, -0.5, 0)
        sun.light?.castsShadow = true
        sun.light?.shadowColor = NSColor.black.withAlphaComponent(0.18)
        sun.light?.shadowRadius = 5
        sun.light?.shadowSampleCount = 16
        sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.light?.shadowMode = .deferred
        scene?.rootNode.addChildNode(sun)
        setAccessibilityElement(true)
        setAccessibilityLabel("Live spatial workspace")
        setAccessibilityHelp("Select a building, team, or agent. The Explore list provides keyboard navigation. Drag to orbit, scroll to frame.")
        meadow.changed = { [weak self] in self?.updatePlayback() }
        meadow.prepare = { [weak self] node, completed in
            guard let self else { completed(); return }
            self.prepare([node]) { _ in Task { @MainActor in completed() } }
        }
        if ScenePerformance.disabled("MEADOW") { meadow.root.isHidden = true }
        if ScenePerformance.disabled("SHADOWS") { sun.light?.castsShadow = false }
        updateCamera()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        guard let window else { return }
        let driver = SceneFrameDriver(); driver.view = self; frameDriver = driver
        let link = displayLink(target: driver, selector: #selector(SceneFrameDriver.frame(_:)))
        link.add(to: .main, forMode: .common); frameLink = link; lastLinkFPS = 0
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePlayback() }
            })
        }
        updatePlayback()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.active, event.window === self.window, self.window?.attachedSheet == nil,
                  event.keyCode == 53, let focus = self.focus, focus != .portfolio else { return event }
            if !event.isARepeat { self.select?(focus.officeReturn) }
            return nil
        }
    }
    func tearDown() {
        suspend()
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(world: SpatialWorld, focus: SpatialFocus, active: Bool, reducedMotion: Bool, reset: Int, page: Int = 0) {
        let pageChanged = self.page != page
        self.page = page
        let contentsChanged: Bool
        if let projectID = focus.projectID {
            contentsChanged = self.world.projects.first { $0.id == projectID } != world.projects.first { $0.id == projectID }
        } else { contentsChanged = self.world != world }
        let changed = contentsChanged || self.focus != focus || pageChanged
        let lifecycleChanged = self.active != active || reduced != reducedMotion
        self.world = world; self.active = active; reduced = reducedMotion
        setAccessibilityElement(focus != .portfolio)
        // Home hides and pauses this surface, retaining the office nodes and desk assignments.
        if changed && focus != .portfolio { reconcile(focus) }
        if self.focus != focus || self.reset != reset || pageChanged {
            self.focus = focus; self.reset = reset
            framePose = framing(focus)
            move(to: framePose, animated: active && !reducedMotion)
        }
        if changed || lifecycleChanged { updateAgents() }
        if !active || reducedMotion {
            if let travel { pose = travel.end; self.travel = nil; updateCamera() }
        }
        updatePlayback()
    }

    private func projectPosition(_ id: String) -> SCNVector3 {
        let slot = projectSlots.index(id)
        return SCNVector3(Double(slot % 4) * 34, 0, Double(slot / 4) * 34)
    }
    private func teamPosition(_ team: SpatialTeam) -> SCNVector3 {
        let scope = team.projectID ?? "standalone"
        let slot = teamSlots[scope, default: SpatialSlots()].index(team.id)
        let origin = team.projectID.map(projectPosition) ?? SCNVector3Zero
        return SCNVector3(origin.x + CGFloat(slot % 4) * 26, 0, origin.z + CGFloat(slot / 4) * 24)
    }
    private func agentPosition(_ agent: SpatialAgent, team: SpatialTeam) -> SCNVector3 {
        let slot = agentSlots[team.id, default: SpatialSlots()].index(agent.id)
        let origin = teamPosition(team)
        return SCNVector3(origin.x + CGFloat(slot % 3) * 6 - 6, 0, origin.z + CGFloat(slot / 3) * 6)
    }

    private func reconcile(_ next: SpatialFocus) {
        let interval = ScenePerformance.begin("Scene reconciliation")
        defer { ScenePerformance.end("Scene reconciliation", interval) }
        if let project = world.projects.first(where: { $0.id == next.projectID }) {
            reconcileOffice(project, focus: next)
            return
        }
        for station in officeWorkstations.values { station.suspend(); station.root.removeFromParentNode() }
        officeWorkstations = [:]; officeOccupants = []; officeProject = nil
        meadow.root.isHidden = true
        for desk in emptyOfficeDesks.values { desk.root.removeFromParentNode() }; emptyOfficeDesks = [:]
        targets = [:]
        var keep = Set<String>()
        for project in world.projects {
            let origin = projectPosition(project.id)
            let id = "building:" + project.id
            keep.insert(id)
            let node = retained(id) {
                let root = SCNNode()
                root.addChildNode(Self.box(23, 0.5, 22, x: 0, y: -0.4, z: 0, color: .white))
                root.addChildNode(Self.box(18, 7, 14, x: 0, y: 3.3, z: 0, color: NSColor(white: 0.96, alpha: 1)))
                root.addChildNode(Self.box(19, 0.45, 15, x: 0, y: 7, z: 0, color: NSColor(srgbRed: 0.37, green: 0.48, blue: 0.52, alpha: 1)))
                for x in [-6.0, -2, 2, 6] {
                    root.addChildNode(Self.box(2.5, 2.5, 0.12, x: x, y: 4, z: 7.05, color: NSColor(srgbRed: 0.50, green: 0.70, blue: 0.79, alpha: 1)))
                }
                return root
            }
            node.position = origin
            node.isHidden = next != .portfolio
            targets[id] = .project(project.id)
            label(on: node, id: id, title: project.name, subtitle: project.summary.text, height: 11, width: 30)
        }
        let visibleTeams: [SpatialTeam]
        if let team = world.team(next) { visibleTeams = [team] }
        else if let id = next.projectID { visibleTeams = Array((world.projects.first(where: { $0.id == id })?.teams ?? []).dropFirst(next.conversationID == nil ? page * 12 : 0).prefix(next.conversationID == nil ? 12 : Int.max)) }
        else if let team = world.team(next) { visibleTeams = [team] }
        else { visibleTeams = [] }
        let focusedTeam = world.team(next)
        if let projectID = next.projectID {
            let id = "office:" + projectID
            keep.insert(id)
            let office = retained(id) {
                let root = SCNNode()
                root.addChildNode(Self.box(26, 0.3, 22, x: 0, y: -0.4, z: 3, color: .white))
                root.addChildNode(Self.box(26, 3, 0.3, x: 0, y: 1, z: -8, color: NSColor(white: 0.94, alpha: 1)))
                return root
            }
            office.position = projectPosition(projectID)
            office.isHidden = !visibleTeams.isEmpty
        }
        for team in visibleTeams {
            let origin = teamPosition(team)
            let id = "team:" + team.id
            keep.insert(id)
            let rows = max(1, Int(ceil(Double(team.agents.count) / 3)))
            let depth = CGFloat(max(15, rows * 6 + 6))
            let node = retained(id) {
                let root = SCNNode()
                root.addChildNode(Self.box(24, 0.3, depth, x: 0, y: -0.2, z: Double(depth) / 2 - 5, color: NSColor(srgbRed: 0.83, green: 0.79, blue: 0.70, alpha: 1)))
                root.addChildNode(Self.box(24, 2, 0.25, x: 0, y: 0.8, z: -5, color: .white))
                root.addChildNode(Self.box(0.25, 2, depth, x: -12, y: 0.8, z: Double(depth) / 2 - 5, color: .white))
                // A shared board marks the team even before furniture is loaded.
                root.addChildNode(Self.box(8, 3, 0.2, x: 0, y: 2, z: -4.7, color: NSColor(white: 0.98, alpha: 1)))
                for x in [-5.0, 5.0] {
                    let desk = Self.box(3.4, 0.2, 1.65, x: x, y: 1.2, z: 2, color: NSColor(srgbRed: 0.60, green: 0.48, blue: 0.35, alpha: 1))
                    desk.name = "overviewDesk"
                    root.addChildNode(desk)
                }
                return root
            }
            node.position = origin
            node.isHidden = next.agentID != nil && focusedTeam?.id != team.id
            targets[id] = team.focus
            label(on: node, id: id, title: team.title, subtitle: team.summary.text, height: 5.5, width: 22)
            // Detailed furniture exists only for the focused team, bounded by visible desk pages.
            node.childNodes.filter { $0.name == "label" || $0.name == "overviewDesk" }.forEach { $0.isHidden = next.conversationID != nil }
        }
        let agents = focusedTeam?.agents ?? []
        // Keep at most 24 detailed avatars resident. Selecting an agent always includes its page.
        let selectedIndex = agents.firstIndex { $0.id == next.agentID } ?? page * 24
        let start = (selectedIndex / 24) * 24
        let detailed = Array(agents.dropFirst(start).prefix(24))
        let agentIDs = Set(detailed.map(\.id))
        for id in Array(workstations.keys) where !agentIDs.contains(id) {
            workstations[id]?.root.removeFromParentNode(); workstations.removeValue(forKey: id)
        }
        if let team = focusedTeam {
            for agent in detailed {
                if workstations[agent.id] == nil {
                    let slot = agentSlots[team.id, default: SpatialSlots()].index(agent.id)
                    let desk = WorkspaceWorkstation(id: agent.id, index: slot)
                    desk.animationChanged = { [weak self] in self?.updatePlayback() }
                    workstations[agent.id] = desk
                    content.addChildNode(desk.root)
                    let monitor = Self.box(1.3, 0.85, 0.20, x: -0.91, y: 1.98, z: 0.83, color: .clear)
                    monitor.opacity = 0.01; monitor.name = "screen:" + agent.id
                    desk.root.addChildNode(monitor)
                }
                workstations[agent.id]?.root.position = agentPosition(agent, team: team)
                targets["agent:" + agent.id] = agent.focus
                targets["screen:" + agent.id] = .agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true)
            }
        }
        for id in Array(nodes.keys) where !keep.contains(id) {
            nodes[id]?.removeFromParentNode(); nodes.removeValue(forKey: id); labelValues.removeValue(forKey: id)
        }
        needsDisplay = true
    }

    private func reconcileOffice(_ project: SpatialProject, focus next: SpatialFocus) {
        for desk in workstations.values { desk.root.removeFromParentNode() }
        workstations = [:]
        for (id,node) in nodes where id != "sharedFloor:" + project.id {
            node.removeFromParentNode(); nodes.removeValue(forKey: id); labelValues.removeValue(forKey: id)
        }
        if officeProject != project.id {
            for desk in emptyOfficeDesks.values { desk.root.removeFromParentNode() }; emptyOfficeDesks = [:]
        }
        officeProject = project.id
        officeOccupants = OfficeRoster(teams: project.teams, now: Date(), including: next.agentID,
                                      conversation: next.conversationID).occupants
        var layout = officeLayouts[project.id, default: SharedOfficeLayout()]
        layout.register(officeOccupants.map(\.id))
        officeLayouts[project.id] = layout
        let floor = retained("sharedFloor:" + project.id) { SCNNode() }
        let desks = layout.desks
        let minX = (desks.map(\.x).min() ?? -2) - 1.73, maxX = (desks.map(\.x).max() ?? 2) + 1.73
        let minZ = (desks.map(\.z).min() ?? -2) - 1.73, maxZ = (desks.map(\.z).max() ?? 2) + 1.73
        let width = CGFloat(maxX - minX), depth = CGFloat(maxZ - minZ)
        meadow.configure(project: project.id, office: MeadowBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ))
        if (floor.geometry as? SCNBox)?.width != width || (floor.geometry as? SCNBox)?.length != depth {
            let slab = SCNBox(width: width, height: 0.38, length: depth, chamferRadius: 0.09)
            slab.materials = [WorkspaceAvatarFactory.material(NSColor(srgbRed: 0.79, green: 0.82, blue: 0.75, alpha: 1))]
            floor.geometry = slab; floor.position = SCNVector3((minX + maxX) / 2, -0.20, (minZ + maxZ) / 2)
            // The default camera looks from -X/+Z: these are the two far edges.
            // Walls belong to the floor, so they grow with it without moving desks.
            floor.childNodes.forEach { $0.removeFromParentNode() }
            let surface = SCNPlane(width: width - 0.12, height: depth - 0.12)
            let wood = SCNMaterial()
            wood.name = "Matte wood floor"
            wood.lightingModel = .physicallyBased
            let bundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Diorama_DioramaApp.bundle")) } ?? Bundle.module
            wood.diffuse.contents = bundle.url(forResource: "OfficeFloorBaseColor", withExtension: "png", subdirectory: "OfficeFurniture")
            wood.diffuse.wrapS = .mirror; wood.diffuse.wrapT = .mirror
            wood.diffuse.mipFilter = .linear
            wood.diffuse.maxAnisotropy = 8
            // One supplied eight-board image spans 3.2 metres (40 cm per board).
            // World-anchored UVs keep grain scale and placement stable as the office grows.
            var uv = SCNMatrix4MakeScale((width - 0.12) / 3.2, (depth - 0.12) / 3.2, 1)
            uv.m41 = (minX + 0.06) / 3.2; uv.m42 = -(maxZ - 0.06) / 3.2
            wood.diffuse.contentsTransform = uv
            wood.roughness.contents = 0.95
            wood.metalness.contents = 0.0
            wood.specular.contents = NSColor(white: 0.04, alpha: 1)
            surface.materials = [wood]
            let flooring = SCNNode(geometry: surface)
            flooring.name = "officeWoodFloor"
            flooring.eulerAngles.x = -.pi / 2
            flooring.position.y = 0.196
            floor.addChildNode(flooring)
            let back = OfficeWall.make(length: Double(width), endMiter: true)
            back.position = SCNVector3(0, 0.20, -Double(depth) / 2 + 0.32)
            back.name = "officeBackWall"
            let side = OfficeWall.make(length: Double(depth), yaw: -.pi / 2, startMiter: true)
            side.position = SCNVector3(Double(width) / 2 - 0.32, 0.20, 0)
            side.name = "officeSideWall"
            floor.addChildNode(back); floor.addChildNode(side)
        }
        let occupiedSlots = Set(officeOccupants.compactMap { layout.assignments[$0.id]?.slot })
        for slot in Array(emptyOfficeDesks.keys) where occupiedSlots.contains(slot) {
            emptyOfficeDesks.removeValue(forKey: slot)?.root.removeFromParentNode()
        }
        for assignment in desks where !occupiedSlots.contains(assignment.slot) {
            if emptyOfficeDesks[assignment.slot] == nil {
                let desk = EmptyOfficeDesk(); emptyOfficeDesks[assignment.slot] = desk; content.addChildNode(desk.root)
            }
            emptyOfficeDesks[assignment.slot]?.root.position = SCNVector3(assignment.x, 0, assignment.z)
            emptyOfficeDesks[assignment.slot]?.root.eulerAngles.y = assignment.yaw
        }
        let ids = Set(officeOccupants.map(\.id))
        for id in Array(officeWorkstations.keys) where !ids.contains(id) {
            officeWorkstations[id]?.suspend(); officeWorkstations[id]?.root.removeFromParentNode()
            officeWorkstations.removeValue(forKey: id)
        }
        targets = [:]
        for occupant in officeOccupants {
            guard let assignment = layout.assignments[occupant.id] else { continue }
            if officeWorkstations[occupant.id] == nil {
                let station = OfficeWorkstation(id: occupant.id)
                station.animationChanged = { [weak self] in self?.updatePlayback() }
                officeWorkstations[occupant.id] = station; content.addChildNode(station.root)
            }
            let station = officeWorkstations[occupant.id]!
            station.root.position = SCNVector3(assignment.x, 0, assignment.z)
            station.root.eulerAngles.y = assignment.yaw
            targets["agent:" + occupant.id] = occupant.destination
            targets["screen:" + occupant.id] = occupant.destination
        }
        updateMeadowVisibility()
        if ScenePerformance.disabled("FURNITURE") {
            emptyOfficeDesks.values.forEach { $0.root.isHidden = true }
            officeWorkstations.values.forEach { $0.root.isHidden = true }
        }
        needsDisplay = true
    }

    private func retained(_ id: String, make: () -> SCNNode) -> SCNNode {
        if let node = nodes[id] { return node }
        let node = make(); node.name = id; nodes[id] = node; content.addChildNode(node); return node
    }
    private func label(on node: SCNNode, id: String, title: String, subtitle: String, height: CGFloat, width: CGFloat) {
        let value = title + "\n" + subtitle
        guard labelValues[id] != value else { return }
        labelValues[id] = value
        node.childNode(withName: "label", recursively: false)?.removeFromParentNode()
        let image = NSImage(size: NSSize(width: 1000, height: 160))
        image.lockFocus()
        NSColor.white.withAlphaComponent(0.97).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1000, height: 160), xRadius: 20, yRadius: 20).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 20, y: 75, width: 960, height: 65), withAttributes: [.font: NSFont.systemFont(ofSize: 43, weight: .semibold), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        (subtitle as NSString).draw(in: NSRect(x: 20, y: 15, width: 960, height: 55), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph])
        image.unlockFocus()
        let plane = SCNPlane(width: width, height: width * 0.16)
        plane.firstMaterial = WorkspaceAvatarFactory.material(.white, constant: true)
        plane.firstMaterial?.diffuse.contents = image; plane.firstMaterial?.isDoubleSided = true
        let label = SCNNode(geometry: plane); label.name = "label"; label.position.y = height
        label.constraints = [SCNBillboardConstraint()]; node.addChildNode(label)
    }
    private static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, x: Double, y: Double, z: Double, color: NSColor) -> SCNNode {
        WorkspaceAvatarFactory.box(w, h, d, at: SCNVector3(x, y, z), material: WorkspaceAvatarFactory.material(color), bevel: 0.08)
    }

    private func framing(_ next: SpatialFocus) -> SpatialCameraPose {
        if let id = next.projectID, let layout = officeLayouts[id] {
            if let agent = next.agentID, let desk = layout.assignments[agent] {
                return SpatialCameraPose(x: desk.x, y: 0.7, z: desk.z, scale: 1.7, yaw: -.pi * 0.82, elevation: .pi / 5)
            }
            let occupants = officeOccupants.filter { next.conversationID == nil || $0.agent.conversationID == next.conversationID }
            let positions = (next.conversationID == nil ? layout.desks : occupants.compactMap { layout.assignments[$0.id] }).map { SCNVector3($0.x, 0, $0.z) }
            var pose = fitted(positions, padding: 3.5)
            // Orthographic magnification is inverse to scale: 1.5× zoom.
            if next.conversationID == nil { pose.scale /= 1.5 }
            pose.elevation = .pi / 6; pose.yaw = -.pi / 4
            return pose
        }
        if let agent = world.agent(next), let team = world.team(next) {
            let p = agentPosition(agent, team: team)
            return SpatialCameraPose(x: Double(p.x), y: 1.7, z: Double(p.z), scale: next.expanded ? 7 : 6, yaw: -.pi * 0.8, elevation: .pi / 7)
        }
        if let team = world.team(next) {
            let p = teamPosition(team)
            let agents = team.agents.dropFirst(page * 24).prefix(24)
            let positions = agents.map { agentPosition($0, team: team) }
            return fitted(positions.isEmpty ? [p] : positions, padding: 12)
        }
        if let id = next.projectID, let project = world.projects.first(where: { $0.id == id }) {
            let positions = project.teams.dropFirst(page * 12).prefix(12).map(teamPosition)
            let origin = projectPosition(id)
            return fitted(positions.isEmpty ? [origin] : positions, padding: 24)
        }
        return fitted(world.projects.map { projectPosition($0.id) }, padding: 22)
    }
    private func fitted(_ positions: [SCNVector3], padding: Double) -> SpatialCameraPose {
        guard let first = positions.first else { return SpatialCameraPose(scale: padding) }
        let minX = Double(positions.map(\.x).min() ?? first.x), maxX = Double(positions.map(\.x).max() ?? first.x)
        let minZ = Double(positions.map(\.z).min() ?? first.z), maxZ = Double(positions.map(\.z).max() ?? first.z)
        return SpatialCameraPose(x: (minX + maxX) / 2, y: 0, z: (minZ + maxZ) / 2, scale: max(padding, (maxX - minX + maxZ - minZ) * 0.26 + padding))
    }
    func move(to end: SpatialCameraPose, animated: Bool, at time: TimeInterval = CACurrentMediaTime()) {
        if animated { travel = (pose, end, time) }
        else { travel = nil; pose = end; updateCamera() }
        updatePlayback()
    }
    private func updateCamera() {
        let interval = ScenePerformance.begin("Camera update")
        defer { ScenePerformance.end("Camera update", interval) }
        camera.camera?.orthographicScale = pose.scale * max(1, Double(bounds.height / max(1, bounds.width)))
        let distance = max(100, pose.scale * 4)
        let offset = focus?.expanded == true && bounds.width >= 850 ? pose.scale * 0.70 * Double(bounds.width / max(1, bounds.height)) : 0
        let targetX = pose.x + offset * cos(pose.yaw)
        let targetZ = pose.z - offset * sin(pose.yaw)
        camera.position = SCNVector3(targetX + distance * cos(pose.elevation) * sin(pose.yaw), pose.y + distance * sin(pose.elevation), targetZ + distance * cos(pose.elevation) * cos(pose.yaw))
        camera.look(at: SCNVector3(targetX, pose.y, targetZ), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        updateMeadowVisibility()
        needsDisplay = true
    }
    private func updateMeadowVisibility() {
        guard officeProject != nil, bounds.width > 0, bounds.height > 0 else { return }
        // Analytic orthographic ray/ground intersections, expanded above blade tips.
        let halfY = Double(camera.camera?.orthographicScale ?? pose.scale)
        let halfX = halfY * Double(bounds.width / bounds.height)
        let forwardGround = (pose.y + 0.395) / tan(pose.elevation)
        let offset = focus?.expanded == true && bounds.width >= 850 ? pose.scale * 0.70 * Double(bounds.width / bounds.height) : 0
        let cx = pose.x + offset * cos(pose.yaw) - sin(pose.yaw) * forwardGround
        let cz = pose.z - offset * sin(pose.yaw) - cos(pose.yaw) * forwardGround
        let yawCos: Double = abs(cos(pose.yaw))
        let yawSin: Double = abs(sin(pose.yaw))
        let groundHalfY: Double = halfY / sin(pose.elevation)
        let ex: Double = yawCos * halfX + yawSin * groundHalfY + 5.0
        let ez: Double = yawSin * halfX + yawCos * groundHalfY + 5.0
        if ScenePerformance.disabled("MEADOW") { meadow.root.isHidden = true; return }
        meadow.updateVisibility(bounds: MeadowBounds(minX: cx-ex, maxX: cx+ex, minZ: cz-ez, maxZ: cz+ez), centre: SIMD2(pose.x, pose.z))
    }
    private func updateAgents() {
        if officeProject != nil {
            let pixelsPerMetre = bounds.height / max(0.1, CGFloat(pose.scale)*2)
            distantFurniture = pixelsPerMetre < (distantFurniture ? 120 : 100)
            let distant = distantFurniture
            for desk in emptyOfficeDesks.values { desk.setDistant(distant) }
            for occupant in officeOccupants {
                guard let station = officeWorkstations[occupant.id] else { continue }
                let visible = isNode(station.root, insideFrustumOf: camera)
                // SceneKit culls geometry. Visibility gates motion only; hiding the root
                // here would make subsequent frustum queries reject it permanently.
                station.update(occupant, selected: focus?.agentID == occupant.id, reduced: reduced,
                               active: effectiveActive && visible, distant: distant)
            }
            return
        }
        guard let focus, let team = world.team(focus) else { return }
        for agent in team.agents {
            guard let desk = workstations[agent.id] else { continue }
            let visible = (focus.agentID == nil || focus.agentID == agent.id) && isNode(desk.root, insideFrustumOf: camera)
            desk.setMovementLab(focus.agentID != nil)
            desk.update(agent.value, selected: focus.agentID == agent.id, reduceMotion: reduced, active: effectiveActive && visible, cameraYaw: pose.yaw)
        }
    }
    private var effectiveActive: Bool {
        active && (window == nil || window?.occlusionState.contains(.visible) == true)
    }
    private func updatePlayback() {
        requestedFPS = min(120, window?.screen?.maximumFramesPerSecond ?? 120)
        let targetFPS = quality.level >= 4 ? min(60, requestedFPS) : requestedFPS
        if preferredFramesPerSecond != targetFPS { preferredFramesPerSecond = targetFPS }
        if lastLinkFPS != targetFPS {
            frameLink?.preferredFrameRateRange = CAFrameRateRange(minimum: Float(min(60, targetFPS)), maximum: Float(targetFPS), preferred: Float(targetFPS))
            lastLinkFPS = targetFPS
        }
        let visible = effectiveActive && focus != .portfolio
        let wind = visible && !reduced && officeProject != nil && !ScenePerformance.disabled("MEADOW")
        meadow.setRunning(wind, now: CACurrentMediaTime())
        meadow.setStreaming(visible)
        let moving = effectiveActive && (wind || travel != nil || pendingCamera || (visible && meadow.pending) || workstations.values.contains(where: \.animating) || officeWorkstations.values.contains(where: \.animating))
        if isPlaying != moving { isPlaying = moving }
        if rendersContinuously != moving { rendersContinuously = moving }
        if frameLink?.isPaused != !moving { frameLink?.isPaused = !moving }
    }
    func frameStep(at time: TimeInterval) {
        frameObserved?(time)
        meadow.advance(now: time)
        meadow.uploadReady()
        if let travel {
            let fraction = (time - travel.time) / 0.4
            pose = travel.start.interpolated(to: travel.end, fraction: fraction)
            pendingCamera = true
            if fraction >= 1 { self.travel = nil }
        }
        if pendingCamera {
            pendingCamera = false
            updateCamera(); updateAgents()
        }
        if ScenePerformance.enabled, time-lastQualitySample >= 2, !meadow.pending, window != nil, effectiveActive, focus != .portfolio {
            lastQualitySample = time
            let intervals = frameTelemetry.snapshot().intervals.suffix(120)
            let average = intervals.isEmpty ? 0 : intervals.reduce(0,+)/Double(intervals.count)
            if quality.level > 0 || average > 1.15/Double(preferredFramesPerSecond), let scene {
                gpuProbe.sample(scene:scene,camera:camera,size:convertToBacking(bounds).size,samples:quality.level >= 3 ? 2 : 4) { [weak self] seconds in
                    guard let self, self.effectiveActive else { return }
                    // The offscreen single-sample probe is diagnostic only. It cannot
                    // safely drive quality for the multisampled onscreen renderer.
                    _ = seconds
                }
            }
        }
        updatePlayback()
    }
    /// GPU timing must come from measured renderer work, not timer lateness.
    func observeGPU(seconds: Double?, now: Double) {
        guard quality.observe(gpuSeconds: seconds, now: now, targetFPS: requestedFPS) else { return }
        meadow.reducedDetail = quality.level >= 1
        sun.light?.shadowSampleCount = quality.level >= 2 ? 4 : 16
        antialiasingMode = quality.level >= 3 ? .multisampling2X : .multisampling4X
        updateMeadowVisibility(); updatePlayback()
    }
    func suspend() {
        meadow.setRunning(false); meadow.setStreaming(false)
        active = false; travel = nil; pendingCamera = false; frameLink?.isPaused = true
        updateAgents(); isPlaying = false; rendersContinuously = false
    }
    override func layout() { super.layout(); updateCamera(); updateAgents() }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { lastPoint = convert(event.locationInWindow, from: nil); dragged = 0 }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - lastPoint.x, dy = point.y - lastPoint.y
        dragged += abs(dx) + abs(dy); lastPoint = point; travel = nil
        pose.yaw -= dx * 0.008; pose.elevation = min(1.2, max(0.25, pose.elevation + dy * 0.005))
        pendingCamera = true; updatePlayback()
    }
    override func mouseUp(with event: NSEvent) {
        guard dragged < 5 else { return }
        let point = convert(event.locationInWindow, from: nil)
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .categoryBitMask: 1]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, let target = targets[name] {
                    if officeProject == nil, target.expanded, focus?.agentID != target.agentID {
                        select?(target.parent)
                    } else {
                        if target.expanded {
                            let projected = projectPoint(hit.worldCoordinates)
                            screenAnchor?(CGPoint(x: CGFloat(projected.x) / max(1, bounds.width), y: 1 - CGFloat(projected.y) / max(1, bounds.height)))
                        }
                        select?(target)
                    }
                    return
                }
                node = current.parent
            }
        }
    }
    override func scrollWheel(with event: NSEvent) {
        travel = nil
        pose.scale = min(framePose.scale * 3, max(framePose.scale * 0.45, pose.scale * exp(Double(event.scrollingDeltaY) * 0.015)))
        pendingCamera = true; updatePlayback()
    }
}

@MainActor private final class SceneFrameDriver: NSObject {
    weak var view: SpatialSceneView?
    @objc func frame(_ link: CADisplayLink) { view?.frameStep(at: link.targetTimestamp) }
}
