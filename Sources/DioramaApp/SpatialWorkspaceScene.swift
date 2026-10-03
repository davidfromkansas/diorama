import SwiftUI
import SceneKit

struct SpatialCameraPose: Codable, Equatable {
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
    var openInspection: ((AgentInspectionDestination) -> Void)? = nil
    var dismissPlan: (() -> Void)? = nil
    var editStatus: ((String?) -> Void)? = nil
    var cameraStore: ProjectTabStore? = nil
    func makeNSView(context: Context) -> SpatialSceneView {
        let view = SpatialSceneView(); view.placementDefaults = .standard
        view.editor.defaults = .standard
        if let url = Bundle.main.url(forResource: "DevelopmentRoot", withExtension: "txt"),
           let root = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            view.editor.exportURL = URL(fileURLWithPath: root).appendingPathComponent(".local/office-layout-drafts.json")
        }
        return view
    }
    func updateNSView(_ view: SpatialSceneView, context: Context) {
        view.cameraStore = cameraStore
        view.editStatus = editStatus
        view.select = select
        view.openInspection = openInspection
        let restoringSceneFocus = view.dismissPlan != nil && dismissPlan == nil
        view.dismissPlan = dismissPlan
        if restoringSceneFocus { view.window?.makeFirstResponder(view) }
        view.screenAnchor = screenAnchor
        view.applyWhenPrepared(world: world, focus: focus, active: active, reducedMotion: reducedMotion, reset: reset, page: page)
    }
    static func dismantleNSView(_ view: SpatialSceneView, coordinator: ()) { view.tearDown() }
}

final class SpatialSceneView: SCNView {
    weak var cameraStore: ProjectTabStore?
    let editor = OfficeLayoutEditor()
    private var selectionStart: CGPoint?
    private var selectionBase: Set<String> = []
    private let selectionBox = CAShapeLayer()
    private func clearSelectionBox() {
        selectionStart = nil; selectionBase = []; selectionBox.removeFromSuperlayer()
    }
    private func updateSelectionBox(to point: CGPoint) {
        guard let start = selectionStart else { return }
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x-start.x), height: abs(point.y-start.y))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        selectionBox.frame = bounds
        selectionBox.path = CGPath(rect: rect, transform: nil)
        selectionBox.fillColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
        selectionBox.strokeColor = NSColor.systemBlue.cgColor; selectionBox.lineWidth = 1
        CATransaction.commit()
        if selectionBox.superlayer == nil { layer?.addSublayer(selectionBox) }
        if rect.width + rect.height > 5 { editor.chooseMany(selectionBase.union(editor.items(in: rect, view: self))) }
    }
    var editStatus: ((String?) -> Void)?
    private var editKeyMonitor: Any?
    var select: ((SpatialFocus) -> Void)?
    var openInspection: ((AgentInspectionDestination) -> Void)?
    var dismissPlan: (() -> Void)?
    var screenAnchor: ((CGPoint) -> Void)?
    private(set) var pose = SpatialCameraPose()
    private(set) var workstations: [String: WorkspaceWorkstation] = [:]
    private(set) var officeWorkstations: [String: OfficeWorkstation] = [:]
    private var reusableOfficeWorkstations: [OfficeWorkstation] = []
    private(set) var emptyOfficeDesks: [Int: EmptyOfficeDesk] = [:]
    private(set) var officeLayouts: [String: SharedOfficeLayout] = [:]
    var placementDefaults: UserDefaults?
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
    private var travel: (start: SpatialCameraPose, end: SpatialCameraPose, time: TimeInterval)?
    private var lastLeisureFrame: Double?
    private var leisureRevision = ""
    private var leisureUpdateScheduled = false
    private var leisureNavigation = WorkspaceCapybaraNavigation()
    private var editorWasEnabled = false
    private var lastPoint = NSPoint.zero
    private var dragged = 0.0
    private var framePose = SpatialCameraPose()

    init() {
        super.init(frame: .zero, options: nil)
        _ = OfficeAssetPreparation.ready
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
        editor.changed = { [weak self] in
            guard let self else { return }
            self.needsDisplay = true
            if !self.editor.enabled { self.clearSelectionBox() }
            if self.editorWasEnabled && !self.editor.enabled { self.configureLeisure() }
            self.editorWasEnabled = self.editor.enabled
            self.lastLeisureFrame = nil
            self.updateAgents(); self.updatePlayback()
            let status = self.editor.status
            DispatchQueue.main.async { [weak self] in self?.editStatus?(status) }
        }
        updateCamera()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let editKeyMonitor { NSEvent.removeMonitor(editKeyMonitor); self.editKeyMonitor = nil }
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        guard let window else { return }
        editKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleEditKey(event) == true }
            return handled ? nil : event
        }
        let driver = SceneFrameDriver(); driver.view = self; frameDriver = driver
        let link = displayLink(target: driver, selector: #selector(SceneFrameDriver.frame(_:)))
        link.add(to: .main, forMode: .common); frameLink = link; lastLinkFPS = 0
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePlayback() }
            })
        }
        updatePlayback()
    }
    func tearDown() {
        preparing?.cancel(); preparing = nil; preparedApply = nil
        reusableOfficeWorkstations.removeAll()
        officeWorkstations.values.forEach { $0.leisureMotion?.stop() }
        editor.finish()
        if let editKeyMonitor { NSEvent.removeMonitor(editKeyMonitor); self.editKeyMonitor = nil }
        suspend()
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var assetsPrepared = false
    private var preparing: Task<Void, Never>?
    private var preparedApply: (() -> Void)?
    func applyWhenPrepared(world: SpatialWorld, focus: SpatialFocus, active: Bool, reducedMotion: Bool, reset: Int, page: Int) {
        if assetsPrepared || focus == .portfolio {
            if focus == .portfolio { preparedApply = nil }
            apply(world: world, focus: focus, active: active, reducedMotion: reducedMotion, reset: reset, page: page)
            return
        }
        // A single replaceable request prevents an old project appearing after a rapid switch.
        preparedApply = { [weak self] in self?.apply(world: world, focus: focus, active: active, reducedMotion: reducedMotion, reset: reset, page: page) }
        guard preparing == nil else { return }
        preparing = Task { [weak self] in
            await OfficeAssetPreparation.ready.value
            guard !Task.isCancelled, let self else { return }
            assetsPrepared = true; preparing = nil
            let latest = preparedApply; preparedApply = nil; latest?()
        }
    }

    func apply(world: SpatialWorld, focus: SpatialFocus, active: Bool, reducedMotion: Bool, reset: Int, page: Int = 0) {
        let changingProject = self.focus?.projectID != focus.projectID
        if changingProject, let previous = self.focus?.projectID { cameraStore?.cameras[previous] = pose }
        if focus == .portfolio || changingProject || !active { editor.finish() }
        if focus == .portfolio {
            // Home is a 2D library. Do not reframe its hidden camera or stream a new meadow.
            let needsSuspension = self.active || self.focus != .portfolio
            self.focus = focus; self.reset = reset; self.page = page; reduced = reducedMotion
            setAccessibilityElement(false)
            if needsSuspension { suspend() }
            return
        }
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
            // Work screens are overlays: preserve the user's orbit and zoom when
            // opening, switching agents, or returning to the same office.
            let sameSpace = self.focus != .portfolio && focus != .portfolio && self.focus != nil &&
                (focus.projectID != nil ? self.focus?.projectID == focus.projectID :
                    self.focus?.projectID == nil && self.focus?.conversationID == focus.conversationID)
            let preserveCamera = sameSpace && (focus.expanded || self.focus?.expanded == true) && self.reset == reset && !pageChanged
            self.focus = focus; self.reset = reset
            if preserveCamera {
                travel = nil
            } else {
                framePose = framing(focus)
                move(to: changingProject ? (focus.projectID.flatMap { cameraStore?.cameras[$0] } ?? framePose) : framePose, animated: !changingProject && active && !reducedMotion)
            }
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
                AgentPlanButton.update(root: workstations[agent.id]!.root, id: agent.id, plan: agent.value.plan, height: 5.2, scale: 3)
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
        let changedProject = officeProject != project.id
        for (id,node) in nodes where id != "sharedFloor:window" {
            node.removeFromParentNode(); nodes.removeValue(forKey: id); labelValues.removeValue(forKey: id)
        }
        officeProject = project.id
        officeOccupants = OfficeRoster(teams: project.teams, now: Date(), including: next.agentID,
                                      conversation: next.conversationID).occupants
        let key = "officePlacement.v1." + project.id
        let saved = officeLayouts[project.id] == nil ? placementDefaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(SharedOfficeLayout.Saved.self, from: $0) } : nil
        var layout = officeLayouts[project.id] ?? SharedOfficeLayout(saved: saved)
        let before = layout.saved
        layout.place(officeOccupants)
        officeLayouts[project.id] = layout
        officeOccupants = officeOccupants.filter { layout.visibleIDs.contains($0.id) }
        if before != layout.saved, let data = try? JSONEncoder().encode(layout.saved) { placementDefaults?.set(data, forKey: key) }
        let floor = retained("sharedFloor:window") { SCNNode() }
        let desks = layout.desks
        let minX = layout.floorMinX, maxX = layout.floorMaxX
        let minZ = layout.floorMinZ, maxZ = layout.floorMaxZ
        let width = CGFloat(maxX - minX), depth = CGFloat(maxZ - minZ)
        meadow.configure(project: project.id, office: MeadowBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ))
        if (floor.geometry as? SCNBox)?.width != width || (floor.geometry as? SCNBox)?.length != depth {
            lastMeadowVisibility = nil
            let slab = SCNBox(width: width, height: 0.38, length: depth, chamferRadius: 0.09)
            slab.materials = [WorkspaceAvatarFactory.material(NSColor(srgbRed: 0.79, green: 0.82, blue: 0.75, alpha: 1))]
            floor.geometry = slab; floor.position = SCNVector3((minX + maxX) / 2, -0.20, (minZ + maxZ) / 2)
            // The default camera looks from -X/+Z: these are the two far edges.
            // Walls belong to the floor, so they grow with it without moving desks.
            floor.childNodes.filter { $0.name != "officeLeisureFurniture" }.forEach { $0.removeFromParentNode() }
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
        let leisure = floor.childNode(withName: "officeLeisureFurniture", recursively: false) ?? {
            let node = OfficeLoungeAssets.make(); floor.addChildNode(node); return node
        }()
        // Furniture stays in world space while the floor centre moves during expansion.
        leisure.position = SCNVector3(-floor.position.x, -floor.position.y, -floor.position.z)
        if changedProject {
            // Reset shared placement nodes before applying this project's explicit edits.
            for node in leisure.childNodes.flatMap({ $0.name == "officeTVLounge" ? $0.childNodes : [$0] }) { OfficeBakedLayout.apply(to: node) }
        }
        let occupiedSlots = Set(officeOccupants.compactMap { layout.assignments[$0.id]?.slot })
        for slot in Array(emptyOfficeDesks.keys) where occupiedSlots.contains(slot) || slot >= SharedOfficeLayout.minimumDeskCount {
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
            if let station = officeWorkstations.removeValue(forKey: id) {
                station.leisureMotion?.stop(); station.suspend(); station.root.removeFromParentNode()
                if reusableOfficeWorkstations.count < 34 { reusableOfficeWorkstations.append(station) }
            }
        }
        targets = [:]
        for occupant in officeOccupants {
            let assignment = layout.assignments[occupant.id] ?? OfficeDeskAssignment(slot: -1, x: 0, z: 0, yaw: 0)
            if officeWorkstations[occupant.id] == nil {
                let station: OfficeWorkstation
                if let reused = reusableOfficeWorkstations.popLast() { reused.rebind(id: occupant.id); station = reused }
                else { station = OfficeWorkstation(id: occupant.id) }
                station.animationChanged = { [weak self] in self?.updatePlayback() }
                officeWorkstations[occupant.id] = station; content.addChildNode(station.root)
            }
            let station = officeWorkstations[occupant.id]!
            station.showsFurniture = layout.assignments[occupant.id] != nil
            station.root.isHidden = false
            station.place(desk: assignment, standingAt: layout.standingPosition(occupant.id), animated: active && !reduced)
            AgentPlanButton.update(root: station.person, id: occupant.id, plan: occupant.agent.value.plan, height: 2.08)
            targets["agent:" + occupant.id] = occupant.destination
            targets["screen:" + occupant.id] = occupant.destination
        }
        if !changedProject { updateMeadowVisibility() }
        configureEditor(layout: layout, leisure: leisure, project: project.id)
        if !editor.enabled { configureLeisure() }
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
        if officeProject == next.projectID, let id = next.agentID, officeWorkstations[id] == nil { return pose }
        if let id = next.projectID, let layout = officeLayouts[id] {
            if let agent = next.agentID, let point = officeWorkstations[agent]?.person.worldPosition {
                return SpatialCameraPose(x: Double(point.x), y: 0.7, z: Double(point.z), scale: 1.7, yaw: -.pi * 0.82, elevation: .pi / 5)
            }
            let occupants = officeOccupants.filter { next.conversationID == nil || $0.agent.conversationID == next.conversationID }
            var positions = next.conversationID == nil ? layout.desks.map { SCNVector3($0.x,0,$0.z) } : occupants.compactMap { officeWorkstations[$0.id]?.person.worldPosition }
            if next.conversationID == nil {
                positions += [SCNVector3(layout.floorMinX, 0, layout.floorMinZ), SCNVector3(layout.floorMaxX, 0, layout.floorMaxZ)]
            }
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
        if let id = focus?.projectID, cameraStore?.cameras[id] != pose { cameraStore?.cameras[id] = pose }
        let interval = ScenePerformance.begin("Camera update")
        defer { ScenePerformance.end("Camera update", interval) }
        camera.camera?.orthographicScale = pose.scale * max(1, Double(bounds.height / max(1, bounds.width)))
        let distance = max(100, pose.scale * 4)
        let offset = 0.0
        let targetX = pose.x + offset * cos(pose.yaw)
        let targetZ = pose.z - offset * sin(pose.yaw)
        camera.position = SCNVector3(targetX + distance * cos(pose.elevation) * sin(pose.yaw), pose.y + distance * sin(pose.elevation), targetZ + distance * cos(pose.elevation) * cos(pose.yaw))
        camera.look(at: SCNVector3(targetX, pose.y, targetZ), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        updateMeadowVisibility()
        needsDisplay = true
    }
    private var lastMeadowVisibility: (project: String, bounds: MeadowBounds, centre: SIMD2<Double>, detail: Bool)?
    private func updateMeadowVisibility() {
        guard officeProject != nil, bounds.width > 0, bounds.height > 0 else { return }
        // Analytic orthographic ray/ground intersections, expanded above blade tips.
        let halfY = Double(camera.camera?.orthographicScale ?? pose.scale)
        let halfX = halfY * Double(bounds.width / bounds.height)
        let forwardGround = (pose.y + 0.395) / tan(pose.elevation)
        let offset = 0.0
        let cx = pose.x + offset * cos(pose.yaw) - sin(pose.yaw) * forwardGround
        let cz = pose.z - offset * sin(pose.yaw) - cos(pose.yaw) * forwardGround
        let yawCos: Double = abs(cos(pose.yaw))
        let yawSin: Double = abs(sin(pose.yaw))
        let groundHalfY: Double = halfY / sin(pose.elevation)
        let ex: Double = yawCos * halfX + yawSin * groundHalfY + 5.0
        let ez: Double = yawSin * halfX + yawCos * groundHalfY + 5.0
        if ScenePerformance.disabled("MEADOW") { meadow.root.isHidden = true; return }
        let coverage = MeadowBounds(minX: cx-ex, maxX: cx+ex, minZ: cz-ez, maxZ: cz+ez)
        let centre = SIMD2(pose.x, pose.z)
        if let last = lastMeadowVisibility, last.project == officeProject, last.bounds == coverage, last.centre == centre, last.detail == meadow.reducedDetail { return }
        lastMeadowVisibility = (officeProject!, coverage, centre, meadow.reducedDetail)
        meadow.updateVisibility(bounds: coverage, centre: centre)
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
                               active: effectiveActive && visible && !editor.enabled && focus != .portfolio, distant: distant)
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
        let elapsed = lastLeisureFrame.map { min(0.05,max(0,time-$0)) } ?? 0
        lastLeisureFrame = time
        if effectiveActive && focus != .portfolio && !editor.enabled {
            for station in officeWorkstations.values { station.leisureMotion?.step(elapsed) }
        }
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
    override func layout() { super.layout(); guard focus != .portfolio else { return }; updateCamera(); updateAgents() }
    private func handleEditKey(_ event: NSEvent) -> Bool {
        guard event.window === window, active, focus?.projectID != nil, focus != .portfolio,
              dismissPlan == nil, window?.attachedSheet == nil,
              !(window?.firstResponder is NSTextInputClient),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "e" {
            if !event.isARepeat { travel = nil; pendingCamera = false; editor.toggle(); window?.makeFirstResponder(self) }
            return true
        }
        guard editor.enabled else { return false }
        if event.keyCode == 53 { editor.finish(); return true }
        if key == "1" || key == "2" {
            if !event.isARepeat { editor.rotate(clockwise: key == "2") }
            return true
        }
        return false
    }

    private func scheduleLeisureUpdate() {
        guard !leisureUpdateScheduled else { return }
        leisureUpdateScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            leisureUpdateScheduled = false
            updateAgents(); updatePlayback()
        }
    }

    private func configureLeisure() {
        guard let project = officeProject, let layout = officeLayouts[project] else { return }
        editor.prepareReconciliation()
        let furniture = editor.items.filter { !$0.id.hasPrefix("desk:") }.map(\.node)
        let desks = editor.items.filter { $0.id.hasPrefix("desk:") }.map(\.node)
        let revision = editor.items.map { "\($0.id):\($0.node.worldPosition):\($0.node.eulerAngles.y)" }.joined(separator: "|") + "\(layout.floorMaxZ)"
        let changed = revision != leisureRevision
        leisureRevision = revision
        if changed { leisureNavigation = OfficeLeisureAnchors.navigation(furniture: furniture, desks: desks, bounds: .init(minX:layout.floorMinX,maxX:layout.floorMaxX,minZ:layout.floorMinZ,maxZ:layout.floorMaxZ)) }
        let nav = leisureNavigation
        let anchors = OfficeLeisureAnchors.targets(furniture:furniture,overflow: 0)
        for occupant in officeOccupants {
            guard let station = officeWorkstations[occupant.id], let motion = station.leisureMotion else { continue }
            motion.changed = { [weak self] in
                self?.scheduleLeisureUpdate()
            }
            if let slot = officeLayouts[project]?.leisureSlots[occupant.id] {
                assignLeisure(occupant.id, slot:slot, anchors:anchors, navigation:nav, revisionChanged:changed)
            } else {
                let point=station.root.convertPosition(SCNVector3Zero,to:nil)
                let approach=station.root.convertPosition(SCNVector3(0,0,-1.2),to:nil)
                let target=OfficeLeisureTarget(id:"desk:"+occupant.id,kind:.desk,point:SIMD2(Float(point.x),Float(point.z)),approach:SIMD2(Float(approach.x),Float(approach.z)),yaw:Float(station.root.eulerAngles.y))
                motion.blocked = nil
                motion.setTarget(target,navigation:nav,animated:active && !reduced,revisionChanged:changed)
            }
        }
    }

    private func assignLeisure(_ id: String, slot: Int, anchors: [OfficeLeisureTarget], navigation: WorkspaceCapybaraNavigation, revisionChanged: Bool) {
        guard let project=officeProject, let station=officeWorkstations[id], let motion=station.leisureMotion else { return }
        let occupied=Set((officeLayouts[project]?.leisureSlots ?? [:]).filter { $0.key != id }.values)
        guard let available=(min(slot,anchors.count)..<anchors.count).first(where: { !occupied.contains($0) && OfficeLeisureAnchors.accessible(anchors[$0],navigation:navigation) != nil }) else {
            station.root.isHidden = true; motion.stop(); return
        }
        station.root.isHidden = false
        if officeLayouts[project]?.leisureSlots[id] != available {
            officeLayouts[project]?.reserveLeisure(available,for:id)
            if let defaults=placementDefaults, let saved=officeLayouts[project]?.saved, let data=try? JSONEncoder().encode(saved) { defaults.set(data,forKey:"officePlacement.v1."+project) }
        }
        motion.blocked = { [weak self] in
            guard self?.officeProject == project else { return }
            self?.assignLeisure(id,slot:available+1,anchors:anchors,navigation:navigation,revisionChanged:true)
        }
        guard let target=OfficeLeisureAnchors.accessible(anchors[available],navigation:navigation) else { return }
        motion.setTarget(target,navigation:navigation,animated:active && !reduced,revisionChanged:revisionChanged)
    }

    private func configureEditor(layout: SharedOfficeLayout, leisure: SCNNode, project: String) {
        editor.prepareReconciliation()
        var items: [OfficeLayoutEditor.Item] = []
        for assignment in layout.desks {
            let occupant = officeOccupants.first { layout.assignments[$0.id]?.slot == assignment.slot }
            let station = occupant.flatMap { officeWorkstations[$0.id] }
            guard let root = station?.root ?? emptyOfficeDesks[assignment.slot]?.root else { continue }
            let standing = occupant.flatMap { layout.standingPosition($0.id) }
            items.append(.init(id: "desk:\(assignment.slot)", label: "Desk \(assignment.slot+1) and chair", node: root,
                               ignored: station?.person, width: 1.8, depth: 1.9, apply: { [weak root, weak station] value in
                let edited = OfficeDeskAssignment(slot: assignment.slot, x: value.x, z: value.z, yaw: value.rotationRadians)
                if let station { station.place(desk: edited, standingAt: standing, animated: false) }
                else { root?.position = SCNVector3(value.x,0,value.z); root?.eulerAngles.y = value.rotationRadians }
            }))
        }
        let furniture = leisure.childNodes.flatMap { $0.name == "officeTVLounge" ? $0.childNodes : [$0] }
        for node in furniture {
            guard let id = node.name else { continue }
            let bounds = node.boundingBox
            let label = id == "officeArcade" ? "Arcade" : id == "officePinball" ? "Pinball" : id == "loungeTV" ? "TV" : id == "loungeFoosball" ? "Foosball table" : id.hasPrefix("loungeSofa") ? "Luva sectional" : "Eames chair"
            items.append(.init(id: id, label: label, node: node, ignored: nil,
                               width: Double(bounds.max.x-bounds.min.x), depth: Double(bounds.max.z-bounds.min.z), apply: { [weak node] value in
                guard let node else { return }
                node.worldPosition = SCNVector3(value.x,node.worldPosition.y,value.z)
                node.eulerAngles.y = value.rotationRadians
            }))
        }
        editor.configure(project: project, items: items, floor: .init(minX: layout.floorMinX, maxX: layout.floorMaxX, minZ: layout.floorMinZ, maxZ: layout.floorMaxZ))
    }

    private var cursorTracking: NSTrackingArea?
    private var pointerDragging = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); cursorTracking = area
    }
    func hasClickableTarget(at point: NSPoint) -> Bool {
        guard !editor.enabled else { return false }
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .categoryBitMask: 1]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name,
                   (targets[name] != nil || (openInspection != nil && AgentInspectionDestination(nodeName: name) != nil)) { return true }
                node = current.parent
            }
        }
        return false
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if !visibleRect.isEmpty { addCursorRect(visibleRect, cursor: .arrow) }
    }
    private func updatePointer(_ event: NSEvent) {
        guard !pointerDragging else { return }
        // Tracking areas also receive events underneath sibling SwiftUI overlays.
        // Only own the cursor when the scene actually owns the click destination.
        if let content = window?.contentView,
           let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
           hit !== self && !hit.isDescendant(of: self) { return }
        let point = convert(event.locationInWindow, from: nil)
        (hasClickableTarget(at: point) ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
    override func cursorUpdate(with event: NSEvent) { updatePointer(event) }
    override func mouseMoved(with event: NSEvent) { updatePointer(event) }
    override func mouseExited(with event: NSEvent) { window?.invalidateCursorRects(for: self) }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        pointerDragging = true
        NSCursor.arrow.set()
        window?.makeFirstResponder(self)
        lastPoint = convert(event.locationInWindow, from: nil); dragged = 0
        if editor.enabled {
            let hit = hitTest(lastPoint, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: 1]).first
            clearSelectionBox()
            if let id = hit.flatMap({ editor.item(for: $0.node)?.id }) {
                if event.modifierFlags.contains(.shift) { editor.chooseMany(editor.selection.union([id])) }
                else if !editor.selection.contains(id) { editor.choose(id) }
                editor.beginDrag(at: OfficeLayoutEditor.floorPoint(lastPoint, in: self))
            } else {
                selectionBase = event.modifierFlags.contains(.shift) ? editor.selection : []
                editor.chooseMany(selectionBase); selectionStart = lastPoint
            }
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if editor.enabled {
            if selectionStart != nil { updateSelectionBox(to: point) }
            else { editor.drag(to: OfficeLayoutEditor.floorPoint(point, in: self)) }
            return
        }
        let dx = point.x - lastPoint.x, dy = point.y - lastPoint.y
        dragged += abs(dx) + abs(dy); lastPoint = point; travel = nil
        pose.yaw -= dx * 0.008; pose.elevation = min(1.2, max(0.25, pose.elevation + dy * 0.005))
        pendingCamera = true; updatePlayback()
    }
    @discardableResult func activatePlan(named name: String) -> Bool {
        guard let destination = AgentInspectionDestination(nodeName: name) else { return false }
        openInspection?(destination); return true
    }
    override func mouseUp(with event: NSEvent) {
        defer { pointerDragging = false; updatePointer(event) }
        if editor.enabled {
            if selectionStart != nil { updateSelectionBox(to: convert(event.locationInWindow, from: nil)) }
            clearSelectionBox(); editor.endDrag(); return
        }
        guard dragged < 5 else { return }
        let point = convert(event.locationInWindow, from: nil)
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .categoryBitMask: 1]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, activatePlan(named: name) { return }
                if let name = current.name, let target = targets[name] {
                    let destination: SpatialFocus
                    if case let .agent(project, conversation, agent, _) = target {
                        destination = .agent(project: project, conversation: conversation, agent: agent, expanded: true)
                        let projected = projectPoint(hit.worldCoordinates)
                        screenAnchor?(CGPoint(x: CGFloat(projected.x) / max(1, bounds.width), y: 1 - CGFloat(projected.y) / max(1, bounds.height)))
                    } else { destination = target }
                    select?(destination)
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
