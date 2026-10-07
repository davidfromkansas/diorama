import DioramaCore
import SceneKit
import SwiftUI

enum WorkspaceSceneKind: String, CaseIterable { case office = "Office", kitchen = "Kitchen" }

/// Which side of a station the chefs work from; fixtures face the room accordingly.
enum KitchenWall { case back, left, right, front, island, freestanding }

struct KitchenArea: Identifiable {
    let id: String
    let label: String
    let short: String
    let footprint: CGRect // X/Z coordinates on the floor.
    let wall: KitchenWall
    /// Agreed number of chefs working here at once; more queue behind.
    let spots: Int
    let accent: NSColor
    var center: SCNVector3 { SCNVector3(footprint.midX, 0.6, footprint.midY) }
}
/// The kitchen follows an agent's journey: elevator → order rail → prep → cooking (cutting
/// boards for editing, burners for commands) → tasting → serving window, with the service bell in the middle
/// and the break room for finished chefs. Sized for 10 agents in parallel.
enum KitchenLayout {
    static let floor = CGRect(x: -12, y: -8, width: 24, height: 16)
    /// Cabinets that close the gaps between wall stations.
    static let connectors: [CGRect] = [
        .init(x: -9.2, y: -7.8, width: 0.8, height: 1.2),
        .init(x: -3.6, y: -7.8, width: 2.4, height: 1.2),
        .init(x: 8.0, y: -7.8, width: 3.8, height: 1.2),
        .init(x: 10.6, y: -6.6, width: 1.2, height: 2.2),
        .init(x: 10.6, y: 0.4, width: 1.2, height: 7.2)
    ]
    static let areas: [KitchenArea] = [
        .init(id: "elevator", label: "Elevator: new agents arrive", short: "Elevator", footprint: .init(x: -11.6, y: -7.8, width: 2.4, height: 2.0), wall: .freestanding, spots: 1, accent: .init(red: 0.55, green: 0.52, blue: 0.68, alpha: 1)),
        .init(id: "order", label: "Order rail: read the request", short: "Orders", footprint: .init(x: -8.4, y: -7.8, width: 4.8, height: 1.2), wall: .back, spots: 3, accent: .init(red: 0.56, green: 0.67, blue: 0.61, alpha: 1)),
        .init(id: "prep", label: "Prep: planning and research", short: "Prep", footprint: .init(x: -1.2, y: -7.8, width: 9.2, height: 1.2), wall: .back, spots: 6, accent: .init(red: 0.56, green: 0.67, blue: 0.61, alpha: 1)),
        // Two long islands, each worked from the far side so chefs face the camera: one
        // cutting board or burner per chef.
        .init(id: "cooking", label: "Cooking island: editing code", short: "Cooking", footprint: .init(x: -4.5, y: -2.8, width: 9.0, height: 1.2), wall: .front, spots: 6, accent: .init(red: 0.57, green: 0.64, blue: 0.72, alpha: 1)),
        .init(id: "stove", label: "Stove island: running commands", short: "Stove", footprint: .init(x: -4.5, y: 0.6, width: 9.0, height: 1.2), wall: .front, spots: 6, accent: .init(red: 0.69, green: 0.59, blue: 0.47, alpha: 1)),
        .init(id: "tasting", label: "Tasting: tests and QA", short: "Tasting", footprint: .init(x: 10.6, y: -4.4, width: 1.2, height: 4.8), wall: .right, spots: 3, accent: .init(red: 0.64, green: 0.59, blue: 0.72, alpha: 1)),
        .init(id: "bell", label: "Service bell: needs you", short: "Needs you", footprint: .init(x: -0.5, y: 4.0, width: 1.0, height: 1.0), wall: .freestanding, spots: 6, accent: .init(red: 0.75, green: 0.58, blue: 0.47, alpha: 1)),
        .init(id: "serving", label: "Serving window: ready for review", short: "Serving", footprint: .init(x: 3.2, y: 6.4, width: 7.4, height: 1.2), wall: .front, spots: 5, accent: .init(red: 0.51, green: 0.67, blue: 0.66, alpha: 1)),
        .init(id: "break", label: "Break room: finished agents", short: "Break room", footprint: .init(x: -11.0, y: 5.4, width: 6.6, height: 1.0), wall: .island, spots: 10, accent: .init(red: 0.55, green: 0.52, blue: 0.68, alpha: 1)),
        // Where agents fetch what they use: skills (jars), plugins (crates) and MCP servers (appliances).
        .init(id: "pantry", label: "Pantry: skills, plugins and MCP", short: "Pantry", footprint: .init(x: -11.8, y: -5.8, width: 1.2, height: 8.9), wall: .left, spots: 4, accent: .init(red: 0.62, green: 0.43, blue: 0.24, alpha: 1))
    ]
    /// Low partial walls enclosing the break room, with a doorway toward the kitchen.
    static let breakRoomWalls: [CGRect] = [
        .init(x: -12, y: 3.125, width: 6.6, height: 0.15),
        .init(x: -3.475, y: 3.125, width: 0.15, height: 4.875)
    ]
    /// The elevator car's side and back walls; its interior and doorway stay walkable.
    static let elevatorWalls: [CGRect] = [
        .init(x: -11.6, y: -7.8, width: 0.12, height: 2.0),
        .init(x: -9.32, y: -7.8, width: 0.12, height: 2.0)
    ]
}
struct KitchenSceneSurface: NSViewRepresentable {
    var agents: [SpatialAgent] = []
    /// The project (or conversation) on screen, so even an empty one counts as already shown.
    var scope: String? = nil
    /// Review state per conversation (see `KitchenReviews`).
    var reviews: [String: KitchenReviews.State] = [:]
    var active = false
    var reducedMotion = false
    var select: (SpatialFocus) -> Void = { _ in }
    /// Clicking a chef waiting at the serving window opens the review panel instead.
    var review: ((SpatialAgent) -> Void)? = nil
    /// Clicking a chef waiting at the bell opens its pending request.
    var requestReview: ((SpatialAgent) -> Void)? = nil
    /// Clicking a chef's name tag opens its progress panel.
    var progress: ((SpatialAgent) -> Void)? = nil
    /// The selected agent: ringed, followed by the camera, the only one with a name tag.
    var selectedAgentID: String? = nil
    /// Clearing the selection (a click on empty floor).
    var deselect: (() -> Void)? = nil
    /// A click on the pantry wall opens the pantry card.
    var openPantry: (() -> Void)? = nil
    /// Whether the free camera left the home view (zoomed or turned), for the Reset View button.
    var cameraMoved: ((Bool) -> Void)? = nil
    /// Incremented to send the camera home.
    var resetCamera = 0
    func makeNSView(context: Context) -> KitchenStage { KitchenStage() }
    func updateNSView(_ stage: KitchenStage, context: Context) {
        let view = stage.show(scope ?? "")
        view.select = select
        view.review = review
        view.requestReview = requestReview
        view.progress = progress
        view.reviews = reviews
        view.deselect = deselect
        view.openPantry = openPantry
        view.cameraMoved = cameraMoved
        if stage.cameraResets != resetCamera { stage.cameraResets = resetCamera; view.resetCamera() }
        view.apply(agents: agents, scope: scope, active: active, reducedMotion: reducedMotion)
        view.setSelection(selectedAgentID)
        view.fitFloor()
    }
    static func dismantleNSView(_ stage: KitchenStage, coordinator: ()) { stage.tearDown() }
}

/// One kitchen per project, kept while you look at other projects or tabs, so switching back
/// shows the same chefs (caught up to what their agents did meanwhile) instead of a rebuilt room.
final class KitchenStage: NSView {
    static let maxKitchens = 6
    private(set) var kitchens: [String: KitchenSceneView] = [:]
    private var recency: [String] = []
    private(set) var current: String?
    var cameraResets = 0

    /// The kitchen for `scope`, now the only one on screen.
    @discardableResult func show(_ scope: String) -> KitchenSceneView {
        let view = kitchens[scope] ?? {
            let view = KitchenSceneView(frame: bounds)
            view.autoresizingMask = [.width, .height]
            addSubview(view); kitchens[scope] = view
            return view
        }()
        recency.removeAll { $0 == scope }; recency.append(scope)
        while recency.count > Self.maxKitchens {
            let old = recency.removeFirst()
            kitchens.removeValue(forKey: old).map { $0.tearDown(); $0.removeFromSuperview() }
        }
        if current != scope {
            current = scope
            for (key, kitchen) in kitchens where kitchen.isHidden != (key != scope) {
                kitchen.isHidden = key != scope
                kitchen.updatePlayback()
            }
        }
        return view
    }
    func tearDown() {
        kitchens.values.forEach { $0.tearDown(); $0.removeFromSuperview() }
        kitchens = [:]; recency = []; current = nil
    }
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
    /// Extra chefs allowed past `maxChefs` so every dish waiting for review stays reachable.
    static let maxWaiting = 12
    let floorSize = SIMD3<Float>(Float(KitchenLayout.floor.width), 0.2, Float(KitchenLayout.floor.height))
    var select: ((SpatialFocus) -> Void)?
    var review: ((SpatialAgent) -> Void)?
    var requestReview: ((SpatialAgent) -> Void)?
    var progress: ((SpatialAgent) -> Void)?
    var deselect: (() -> Void)?
    var openPantry: (() -> Void)?
    var reviews: [String: KitchenReviews.State] = [:]
    private(set) var chefs: [String: ChefAvatar] = [:]
    private var chefAgents: [String: SpatialAgent] = [:]
    private(set) var chefLabels: [String: ChefTagView] = [:]
    /// Pixel emotes above the chefs' tags: reactions to moments, and lasting states.
    private(set) var chefEmotes: [String: ChefEmoteView] = [:]
    /// Checklist progress bars between the tags and the chefs' heads.
    private(set) var chefBars: [String: ChefProgressView] = [:]
    /// When each chef last showed the thinking bubble during a quiet stretch.
    private var lastThinking: [String: Date] = [:]
    private var lastSilenceCheck: TimeInterval = 0
    /// The task-label revision the tags were last written with.
    private var labelRevision = TaskLabels.shared.revision
    /// The chef under the pointer: resting chefs show their tag only then.
    private var hoveredID: String?
    private var slots: [String: ChefStation] = [:]
    private let navigation = KitchenLayout.chefNavigation
    private var active = false
    private var reduced = false
    private var frameLink: CADisplayLink?
    private var frameDriver: KitchenFrameDriver?
    private var lastFrame: TimeInterval?
    private var windowObservers: [NSObjectProtocol] = []
    private var labels: [NSTextField] = []
    /// One flame per burner, keyed by the stove slot it belongs to.
    private var flames: [String: (node: SCNNode, fire: SCNParticleSystem)] = [:]
    /// Per cooking slot: the plain board a chef chops on, and the cleaver-on-board model shown
    /// while nobody is there.
    private var boards: [String: (plain: SCNNode, idle: SCNNode)] = [:]
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
        _ = box("Kitchen floor", width: KitchenLayout.floor.width, height: 0.2, depth: KitchenLayout.floor.height, at: SCNVector3Zero, material: material(.init(white: 0.71, alpha: 1)))
        world.rootNode.addChildNode(KitchenRoomGeometry.make())
        for slot in KitchenLayout.chefSlots["stove"] ?? [] {
            let burner = SCNVector3(slot.stand.x, KitchenLayout.worktopHeight + 0.04, Float(KitchenLayout.areas.first { $0.id == "stove" }?.footprint.midY ?? 0))
            let flame = Self.flame(); flame.node.position = burner
            world.rootNode.addChildNode(flame.node); flames[slot.id] = flame
        }
        for area in KitchenLayout.areas {
            let station = KitchenStationGeometry.make(area)
            world.rootNode.addChildNode(station)
            if area.id == "cooking" { boards = Self.idleBoards(on: station) }
            let label = KitchenLabel(labelWithString: area.short)
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
        cameraNode = camera
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
        delegate = self
        allowsCameraControl = false; isPlaying = false; rendersContinuously = false
        wantsLayer = true; leaders.strokeColor = NSColor.darkGray.withAlphaComponent(0.25).cgColor
        leaders.fillColor = nil; leaders.lineWidth = 1; layer?.addSublayer(leaders)
        setAccessibilityLabel("Kitchen layout. " + KitchenLayout.areas.map(\.label).joined(separator: ", ") + ".")
        setAccessibilityHelp(Self.controlsHint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); fitFloor() }

    // MARK: Chefs

    /// Per-chef pacing: the agent state the chef should reflect, the intent that calls for (with
    /// the chef's current spot, or a placeholder when it needs a new one), when it arrived where
    /// it stands, and whether it is still reading its order after arriving by elevator.
    private struct Pacing {
        var agent: WorkspaceAgent
        var review: KitchenReviews.State?
        var want: ChefIntent?
        var arrivedAt: Double?
        var arriving = false
        /// Test runs seen this turn, and whether a newer one still owes a visit to the tasting
        /// station (tests often finish faster than a chef can walk over).
        var testsSeen = 0
        var resourcesSeen = 0
        var filesSeen = 0
        /// Stations a chef still owes a visit for brief work the agent already moved on from:
        /// tasting for a test run, the pantry for a skill or plugin it fetched, the cooking
        /// station for files edited. Paid before serving, so a quick turn still shows its work.
        var owed: [String] = []
    }
    private var pacing: [String: Pacing] = [:]
    private let slotTable = KitchenLayout.chefSlots
    /// Chefs are stepped on SceneKit's render thread (`renderer(_:updateAtTime:)`) so their
    /// animation never waits for the main thread; main-thread steering takes the same lock.
    nonisolated let chefLock = NSRecursiveLock()
    nonisolated(unsafe) private var renderChefs: [ChefAvatar] = []
    nonisolated(unsafe) private var lastRenderTime: TimeInterval?
    /// When the main thread last placed tags and paced chefs, and whether the render thread has
    /// already asked for another step (both under `chefLock`).
    nonisolated(unsafe) private var lastMainStep: TimeInterval = 0
    nonisolated(unsafe) private var mainStepQueued = false
    /// Keeps macOS from throttling Diorama while chefs move in a visible kitchen.
    private var motionActivity: NSObjectProtocol?

    static let controlsHint = "Scroll to zoom · Arrow keys to move · Q/W rotate · R reset"
    // MARK: On-screen log
    /// What each chef last showed, so only changes are logged.
    private var shown: [String: (intent: String, station: String?)] = [:]
    /// Logs chefs that set off for, or reach, a station (kitchens in a window only).
    private func logStations(_ how: String = "") {
        guard window != nil else { return }
        chefLock.lock()
        let states = chefs.mapValues { chef in (intent: chef.director.intent, station: chef.director.station?.area, clip: chef.director.clip.name) }
        chefLock.unlock()
        for (id, state) in states {
            guard let agent = chefAgents[id] else { continue }
            // Where the chef is going (its spot), not the gesture it plays there: a gesture change
            // alone is not a move.
            let key = (state.intent?.station?.id ?? "here"), before = shown[id]
            if before?.intent == key && before?.station == state.station { continue }
            shown[id] = (key, state.station)
            var fields = ["agent": agent.value.name, "conversation": agent.conversationID, "provider": agent.value.provider,
                          "status": agent.value.status.rawValue, "tool": agent.value.latestTool,
                          "detail": String(agent.value.latestToolDetail.split(whereSeparator: \.isNewline).first?.prefix(160) ?? "")]
            if before?.intent != key {
                fields["event"] = how.isEmpty ? "heading" : how
                fields["station"] = state.intent?.station?.area ?? "here"
                fields["loop"] = state.intent?.loop ?? ""
                if let shot = state.intent?.oneShot?.clip { fields["gesture"] = shot }
                KitchenLog.record(fields)
            }
            if let station = state.station, before?.station != station, how.isEmpty {
                fields["event"] = "arrived"; fields["station"] = station; fields["clip"] = state.clip
                fields["gesture"] = nil; fields["loop"] = nil
                KitchenLog.record(fields)
            }
        }
        for id in shown.keys where states[id] == nil { shown[id] = nil }
    }

    // MARK: Free camera
    /// Scroll to zoom, arrow keys to move, Q/W to turn, R to reset (see `KitchenCameraController`).
    private(set) var freeCamera = KitchenCameraController()
    /// Told whether the camera has left the home view, so the Reset View button can show.
    var cameraMoved: ((Bool) -> Void)?
    private var keyMonitor: Any?
    private var reportedAway = false
    /// Hands the free camera's pose to the render thread, which eases toward it.
    private func applyFreeCamera() {
        chefLock.lock()
        overviewPose = CameraPose(eye: freeCamera.eye, look: freeCamera.look)
        cameraMoving = true; snapCamera = reduced
        chefLock.unlock()
        let away = !freeCamera.isHome
        if away != reportedAway { reportedAway = away; cameraMoved?(away) }
        syncSelection()
    }
    func resetCamera() {
        freeCamera.reset(); applyFreeCamera()
    }
    /// Scroll zooms the free camera in and back out to home (not while a chef is followed, a
    /// modifier is held, or a sheet is open).
    override func scrollWheel(with event: NSEvent) {
        guard selectedID == nil, window?.attachedSheet == nil,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { super.scrollWheel(with: event); return }
        let delta = Float(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8)
        guard delta != 0 else { return }
        freeCamera.scroll(delta)
        applyFreeCamera()
    }
    /// Arrow keys, Q/W and R while the kitchen is on screen and nothing that types has focus.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, window.isKeyWindow, observed, window.attachedSheet == nil,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        // Typing, or arrowing through a list, keeps the keys.
        if let responder = window.firstResponder, responder is NSText || responder is NSTableView || responder is NSTextField {
            if !freeCamera.held.isEmpty { freeCamera.releaseAll() }
            return false
        }
        let down = event.type == .keyDown
        let key: KitchenCameraController.Key?
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 123: key = .left
        case 124: key = .right
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": key = .turnLeft
            case "w": key = .turnRight
            case "r":
                if down, !event.isARepeat, !freeCamera.isHome { resetCamera(); return true }
                return false
            default: key = nil
            }
        }
        guard let key, selectedID == nil else { return false }
        // Arrows only matter zoomed in; at home they stay with whatever else uses them.
        if [.up, .down, .left, .right].contains(key), !freeCamera.isZoomedIn { return false }
        if down { freeCamera.press(key) } else { freeCamera.release(key) }
        updatePlayback()
        return true
    }

    // MARK: Selection and camera
    /// The selected chef: it wears the selection ring, the camera follows it, and only its name
    /// tag shows.
    private(set) var selectedID: String?
    private var selectionRing: SCNNode?
    /// Camera state stepped on the render thread (under `chefLock`): the overview pose that frames
    /// the kitchen, the chef it follows, and where it is now.
    nonisolated(unsafe) private var cameraNode: SCNNode?
    nonisolated(unsafe) private var overviewPose: CameraPose?
    nonisolated(unsafe) private var followID: String?
    nonisolated(unsafe) private(set) var cameraPose: CameraPose?
    nonisolated(unsafe) private(set) var cameraMoving = false
    nonisolated(unsafe) private var snapCamera = false
    struct CameraPose: Equatable {
        var eye: SIMD3<Float>
        var look: SIMD3<Float>
    }
    /// The follow camera keeps the overview's angle, closer in, aimed at the chef's chest.
    nonisolated static func followPose(for position: SIMD3<Float>) -> CameraPose {
        let elevation: Float = 62 * .pi / 180, distance: Float = 8.5
        let look = position + SIMD3(0, 1.2, 0)
        return CameraPose(eye: look + SIMD3(0, distance * sin(elevation), distance * cos(elevation)), look: look)
    }
    /// Seconds for the camera to cover most of the way to its target.
    nonisolated static let cameraEase: Float = 0.35
    private func publishChefs() { chefLock.lock(); renderChefs = Array(chefs.values); chefLock.unlock() }
    /// Projects (or standalone conversations) already shown here: only agents that start while
    /// their project is on screen ride the elevator in; everything else appears in place.
    private var seenScopes: Set<String> = []

    /// Spots are owned: a chef keeps its spot until it actually sets off, and claims a free spot
    /// (the station's first unused one, else a queue place behind it) only when it leaves.
    private func claimSlot(_ id: String, area: String) -> ChefStation? {
        if let current = slots[id], current.area == area { return current }
        let taken = Set(slots.filter { $0.key != id }.map(\.value.id))
        let options = slotTable[area] ?? []
        if let free = options.first(where: { !taken.contains($0.id) }) { slots[id] = free; return free }
        guard !options.isEmpty else { return nil }
        var n = 0
        while taken.contains("\(options[n % options.count].id)~\(n)") { n += 1 }
        let base = options[n % options.count], back = Float(n / options.count + 1) * 0.95 * KitchenLayout.chefScale
        let queued = ChefStation(id: "\(base.id)~\(n)", area: area, stand: base.stand - SIMD2(sin(base.facing), cos(base.facing)) * back, facing: base.facing)
        slots[id] = queued
        return queued
    }
    /// The intent this chef's agent calls for. It keeps the chef's spot when the area is the
    /// same; otherwise it claims a new spot (`claim`) or uses a placeholder for comparison.
    private func wanted(_ id: String, claim: Bool, restored: Bool = false) -> ChefIntent? {
        guard let state = pacing[id], let chef = chefs[id] else { return nil }
        let work = KitchenLayout.work(for: state.agent, review: state.review)
        var slot: ChefStation?
        if let area = work.area {
            if let current = slots[id], current.area == area { slot = current }
            else if claim { slot = claimSlot(id, area: area) }
            else { slot = ChefStation(id: "pending:" + area, area: area, stand: .zero, facing: 0) }
        }
        // Finished chefs pick their plate up where they already work, never at a shared spot.
        let pickup = chef.director.station.flatMap { ["cooking", "stove", "prep", "tasting"].contains($0.area) ? $0 : nil }
        return KitchenLayout.intent(for: state.agent, at: slot, pickup: pickup, restored: restored, review: state.review)
    }
    /// The visit owed for brief work (a test run, a skill fetched), whatever the agent does by now.
    private func owedIntent(_ id: String, area: String) -> ChefIntent? {
        guard var agent = pacing[id]?.agent else { return nil }
        agent.status = .working; agent.turnHasEdits = true
        if area == "pantry" { agent.latestTool = "Skill"; agent.latestToolDetail = agent.turnWork.resources.last ?? "" }
        else if area == "cooking" { agent.latestTool = "Edit"; agent.latestToolDetail = agent.turnWork.files.last ?? "" }
        else if area == "stove" { agent.latestTool = "Bash"; agent.latestToolDetail = "npm run build" }
        else { agent.latestTool = "Bash"; agent.latestToolDetail = agent.turnWork.tests.last?.command ?? "npm test" }
        let slot = claimSlot(id, area: area)
        return KitchenLayout.intent(for: agent, at: slot, pickup: nil, restored: false)
    }
    private func queuedWithFreeSpot(_ id: String) -> Bool {
        guard let slot = slots[id], slot.id.contains("~") else { return false }
        let taken = Set(slots.filter { $0.key != id }.map(\.value.id))
        return (slotTable[slot.area] ?? []).contains { !taken.contains($0.id) }
    }

    /// Reconcile chefs with agents: attention first, then working, capped at `maxChefs`.
    func apply(agents: [SpatialAgent], scope: String? = nil, active: Bool, reducedMotion: Bool, now: Double = CACurrentMediaTime()) {
        // The render thread only sees published chefs, so new chefs are built outside the lock;
        // the lock covers just the short steering steps below (a long hold froze every chef).
        defer { publishChefs() }
        let applyStart = CACurrentMediaTime()
        defer { if CACurrentMediaTime() - applyStart > 0.02 { Self.trace(String(format: "slow apply %.0f ms", (CACurrentMediaTime() - applyStart) * 1000)) } }
        if active != self.active { Self.trace("active -> \(active)") }
        self.active = active; reduced = reducedMotion
        defer { if let scope { seenScopes.insert(scope) } }
        // Attention first, then working, then dishes waiting for review; resting chefs fill what
        // is left. Dishes waiting for review are never dropped: past the cap they queue at the pass.
        func rank(_ agent: SpatialAgent) -> Int {
            if agent.needsAttention { return 0 }
            if agent.value.status == .working { return 1 }
            return KitchenLayout.work(for: agent.value, review: reviews[agent.conversationID]).area == "serving" ? 2 : 3
        }
        let sorted = agents.enumerated().map { (rank: rank($0.element), offset: $0.offset, agent: $0.element) }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.offset < $1.offset }
        let working = sorted.filter { $0.rank <= 1 }.prefix(Self.maxChefs)
        let waiting = sorted.filter { $0.rank == 2 }.prefix(Self.maxChefs + Self.maxWaiting - working.count)
        let resting = sorted.filter { $0.rank == 3 }.prefix(max(0, Self.maxChefs - working.count - waiting.count))
        let ranked = (working + waiting + resting).map(\.agent)
        let ids = Set(ranked.map(\.id))
        for id in chefs.keys where !ids.contains(id) {
            chefLock.lock(); renderChefs.removeAll { $0.id == id }; chefLock.unlock()
            chefs.removeValue(forKey: id)?.root.removeFromParentNode()
            chefLabels.removeValue(forKey: id)?.removeFromSuperview()
            chefEmotes.removeValue(forKey: id)?.removeFromSuperview(); lastThinking[id] = nil
            chefBars.removeValue(forKey: id)?.removeFromSuperview()
            chefAgents[id] = nil; slots[id] = nil; pacing[id] = nil
        }
        guard !ranked.isEmpty, case let .success(assets) = ChefAssets.shared, let world = scene else { updatePlayback(); return }
        for agent in ranked {
            chefAgents[agent.id] = agent
            let review = reviews[agent.conversationID]
            if chefs[agent.id] == nil {
                let chef = ChefAvatar(id: agent.id, assets: assets, scale: KitchenLayout.chefScale, navigation: navigation)
                chef.director.reducedMotion = reduced
                chef.dish = KitchenFood.dish(for: agent.value.completionKey ?? agent.conversationID)
                chefs[agent.id] = chef
                // Only agents that start while someone watches ride the elevator in.
                let arriving = !catchingUp && seenScopes.contains(agent.projectID ?? agent.conversationID) && [.live, .recentlyObserved].contains(agent.value.freshness)
                if arriving, let door = slotTable["elevator"]?.first, let order = claimSlot(agent.id, area: "order") {
                    // A new agent joins: it rides the elevator in and reads its order first.
                    chef.director.place(door.stand, heading: door.facing)
                    chef.director.setIntent(KitchenLayout.arrivalIntent(at: order))
                    pacing[agent.id] = Pacing(agent: agent.value, review: review, arriving: true, testsSeen: agent.value.turnWork.tests.count, resourcesSeen: agent.value.turnWork.resources.count, filesSeen: agent.value.turnWork.files.count)
                    openElevator()
                } else {
                    // Chefs shown from history start in place: no walk-in, no replayed gesture.
                    let area = KitchenLayout.work(for: agent.value, review: review).area
                    let slot = area.flatMap { claimSlot(agent.id, area: $0) }
                    let home = slotTable["break"] ?? []
                    if let spawn = slot ?? (home.isEmpty ? nil : home[chefs.count % home.count]) { chef.director.place(spawn.stand, heading: spawn.facing) }
                    chef.director.setIntent(KitchenLayout.intent(for: agent.value, at: slot, pickup: nil, restored: true, review: review))
                    pacing[agent.id] = Pacing(agent: agent.value, review: review, testsSeen: agent.value.turnWork.tests.count, resourcesSeen: agent.value.turnWork.resources.count, filesSeen: agent.value.turnWork.files.count)
                    pacing[agent.id]?.want = chef.director.intent
                }
                chef.update(0)
                world.rootNode.addChildNode(chef.root)
                let label = ChefTagView(frame: .zero)
                chefLabels[agent.id] = label; addSubview(label)
                let emote = ChefEmoteView(frame: .zero)
                chefEmotes[agent.id] = emote; addSubview(emote)
                let bar = ChefProgressView(frame: .zero)
                chefBars[agent.id] = bar; addSubview(bar)
            } else {
                // Moments since the last look (not while catching up or for history): a reaction.
                if !catchingUp, agent.fresh, let previous = pacing[agent.id]?.agent {
                    let moments = ChefMoment.detect(previous: previous, current: agent.value)
                    if !moments.isEmpty {
                        chefEmotes[agent.id]?.react(moments)
                        KitchenLog.record(["event": "emote", "agent": agent.value.name, "conversation": agent.conversationID, "emotes": moments.map(\.rawValue).joined(separator: ",")])
                    }
                }
                chefLock.lock()
                chefs[agent.id]?.director.reducedMotion = reduced
                // One dish per task: a new turn (new completion key) rolls a new one.
                chefs[agent.id]?.dish = KitchenFood.dish(for: agent.value.completionKey ?? agent.conversationID)
                pacing[agent.id]?.agent = agent.value
                pacing[agent.id]?.review = review
                // Every new test run sends the chef to taste, however quickly the agent moves on.
                // Brief work still gets its station: tasting for each new test run, the pantry for
                // each skill or plugin fetched, however quickly the agent moves on.
                let tests = agent.value.turnWork.tests.count, seen = pacing[agent.id]?.testsSeen ?? tests
                let fetched = agent.value.turnWork.resources.count, fetchedSeen = pacing[agent.id]?.resourcesSeen ?? fetched
                // Only live work owes visits: history loading after a relaunch also raises the counts.
                let files = agent.value.turnWork.files.count, filesSeen = pacing[agent.id]?.filesSeen ?? files
                if !catchingUp, agent.value.status == .working, agent.fresh, var state = pacing[agent.id] {
                    if fetched > fetchedSeen, !state.owed.contains("pantry") { state.owed.append("pantry") }
                    // Edits come before the tests that check them.
                    if files > filesSeen, !state.owed.contains("cooking") { state.owed.insert("cooking", at: state.owed.firstIndex(of: "tasting") ?? state.owed.endIndex) }
                    // A command that tests and builds owes both stations, in the order it ran them:
                    // the kitchen shows recent work at a run, even when the agent has moved on.
                    if tests > seen {
                        let steps = agent.value.turnWork.tests.last.map { KitchenActivity.stations(command: $0.command) } ?? []
                        let areas = steps.compactMap { step -> String? in
                            switch step { case .testing, .checking: "tasting"; case .commands: "stove"; default: nil }
                        }
                        for area in areas.isEmpty ? ["tasting"] : areas where !state.owed.contains(area) { state.owed.append(area) }
                    }
                    pacing[agent.id] = state
                }
                pacing[agent.id]?.filesSeen = files
                pacing[agent.id]?.testsSeen = tests
                pacing[agent.id]?.resourcesSeen = fetched
                if pacing[agent.id]?.arriving == false { let want = wanted(agent.id, claim: false); pacing[agent.id]?.want = want }
                chefLock.unlock()
            }
            // The tag shows a short task name; the emote above it what needs noticing.
            let content = ChefTagContent.make(agent, review: review)
            chefLabels[agent.id]?.update(content, reducedMotion: reduced)
            chefBars[agent.id]?.update(content.progress)
            if let emote = chefEmotes[agent.id] {
                emote.reducedMotion = reduced; emote.name = agent.value.name
                emote.setLasting(ChefEmote.lasting(agent, review: review))
            }
        }
        seenScopes.formUnion(ranked.map { $0.projectID ?? $0.conversationID })
        noteObservation()
        chefLock.lock(); pace(now: now); chefLock.unlock()
        if catchingUp { catchUp(); logStations("jumped") } else { logStations() }
        syncSelection()
        updateFlames()
        updateBoards()
        placeChefLabels()
        updatePlayback()
        needsDisplay = true
    }
    /// Applies wanted intents: urgent ones at once, others after the chef has arrived and worked
    /// at its station for `minimumDwell` (or read its order for `orderReading` after arriving).
    func pace(now: Double) {
        for id in chefs.keys.sorted() {
            guard let chef = chefs[id], var state = pacing[id] else { continue }
            let director = chef.director
            if director.station != nil, state.arrivedAt == nil { state.arrivedAt = now }
            let settledFor = state.arrivedAt.map { now - $0 } ?? 0
            let walking = director.intent?.station != nil && director.station == nil
            var apply = false, promote = false
            // A turn that just finished still pays its visits on the way to the pass; anything
            // else (needs you, stopped, failed) drops them.
            if ![.working, .done, .ready].contains(state.agent.status) { state.owed.removeAll() }
            if let owedArea = state.owed.first, !state.arriving {
                // Needs-you comes first; otherwise the chef pays the visit before moving on (even to serve).
                if state.want?.station?.area == "bell" || (state.want?.urgent == true && state.want?.station == nil) { state.owed.removeAll() }
                else if director.intent?.station?.area == owedArea {
                    if director.station != nil, settledFor >= KitchenLayout.minimumDwell { state.owed.removeFirst() }
                    pacing[id] = state; continue
                } else if !walking, director.intent?.station == nil || settledFor >= KitchenLayout.minimumDwell, let next = owedIntent(id, area: owedArea) {
                    director.setIntent(next)
                    state.arrivedAt = nil
                    pacing[id] = state; continue
                } else { pacing[id] = state; continue }
            }
            if state.arriving {
                apply = state.arrivedAt != nil && settledFor >= KitchenLayout.orderReading
                if apply { state.arriving = false }
            } else if let want = state.want, want.key != director.intent?.key {
                // Urgent changes apply at once. Otherwise a walking chef finishes its trip (agents
                // switch tools several times a second; re-routing mid-walk made chefs stop, turn
                // and restart) and then works at least the minimum dwell before moving on.
                apply = want.urgent || director.intent?.station == nil || (!walking && settledFor >= KitchenLayout.minimumDwell)
            } else if !walking, settledFor >= KitchenLayout.minimumDwell, queuedWithFreeSpot(id) {
                // A chef queued behind a full station steps into a spot once one frees up.
                apply = true; promote = true
            }
            if apply {
                pacing[id] = state
                if promote { slots[id] = nil }
                if var next = wanted(id, claim: true) {
                    // Work that leaves the serving window for the break room was accepted: celebrate.
                    if next.station?.area == "break", director.intent?.station?.area == "serving" { next.prelude = "celebrate_done" }
                    director.setIntent(next)
                    state.arrivedAt = nil
                }
                state.want = wanted(id, claim: false)
            }
            pacing[id] = state
        }
    }
    /// A burner is lit while a chef works at it (watching its command cook).
    func updateFlames() {
        chefLock.lock()
        let lit = Set(chefs.values.compactMap { chef -> String? in
            guard let station = chef.director.station, station.area == "stove", chef.director.clip.name == "waiting_tool" else { return nil }
            return station.id
        })
        chefLock.unlock()
        for (id, flame) in flames {
            let on = lit.contains(id)
            flame.node.isHidden = !on
            flame.fire.birthRate = on && !reduced ? 140 : 0
        }
    }
    /// A board shows the resting cleaver until a chef reaches it.
    func updateBoards() {
        guard !boards.isEmpty else { return }
        chefLock.lock()
        let busy = Set(chefs.values.compactMap { chef -> String? in
            guard let station = chef.director.station, station.area == "cooking",
                  simd_distance(chef.director.position, station.stand) < 0.35 else { return nil }
            return station.id
        })
        chefLock.unlock()
        for (id, board) in boards {
            let used = busy.contains(id)
            if board.plain.isHidden != !used { board.plain.isHidden = !used }
            if board.idle.isHidden != used { board.idle.isHidden = used }
        }
    }
    var idleBoards: Set<String> { Set(boards.filter { !$0.value.idle.isHidden }.map(\.key)) }
    /// Pairs each plain board on the island with its cooking slot (nearest along the island) and
    /// lays the cleaver model over it, sized to the plain board.
    private static func idleBoards(on island: SCNNode) -> [String: (plain: SCNNode, idle: SCNNode)] {
        guard let template = KitchenProps.cleaverBoard else { return [:] }
        let slots = KitchenLayout.chefSlots["cooking"] ?? []
        var result: [String: (plain: SCNNode, idle: SCNNode)] = [:]
        for plain in island.childNodes where plain.name == "cutting board" {
            let x = Float(island.convertPosition(plain.position, to: nil).x)
            guard let slot = slots.min(by: { abs($0.stand.x - x) < abs($1.stand.x - x) }), result[slot.id] == nil,
                  let box = plain.geometry as? SCNBox else { continue }
            let idle = template.clone(); idle.name = "idle cutting board"
            // The model is 1.0 wide; the island's height scale is undone so it keeps its proportions.
            let width = box.width, lift = CGFloat(island.scale.y)
            idle.scale = SCNVector3(width, width / lift, width)
            idle.position = SCNVector3(plain.position.x, plain.position.y - box.height / 2, plain.position.z)
            island.addChildNode(idle)
            plain.isHidden = true
            result[slot.id] = (plain, idle)
        }
        return result
    }
    var litBurners: Set<String> { Set(flames.filter { !$0.value.node.isHidden }.map(\.key)) }
    private static func flame() -> (node: SCNNode, fire: SCNParticleSystem) {
        let node = SCNNode(); node.name = "burner flame"; node.isHidden = true
        // A steady glow (also shown under reduced motion) plus rising particles.
        let glow = SCNCone(topRadius: 0.02, bottomRadius: 0.2, height: 0.32)
        let hot = SCNMaterial(); hot.lightingModel = .constant; hot.diffuse.contents = NSColor(red: 1, green: 0.55, blue: 0.12, alpha: 0.85)
        hot.emission.contents = NSColor(red: 1, green: 0.45, blue: 0.1, alpha: 1); hot.blendMode = .add; hot.writesToDepthBuffer = false
        glow.materials = [hot]
        let cone = SCNNode(geometry: glow); cone.position.y = 0.16; node.addChildNode(cone)
        let fire = SCNParticleSystem()
        fire.birthRate = 0
        fire.particleLifeSpan = 0.45; fire.particleLifeSpanVariation = 0.15
        fire.particleSize = 0.11; fire.particleSizeVariation = 0.04
        fire.particleVelocity = 0.9; fire.particleVelocityVariation = 0.3
        fire.emittingDirection = SCNVector3(0, 1, 0); fire.spreadingAngle = 18
        fire.emitterShape = SCNTorus(ringRadius: 0.17, pipeRadius: 0.03)
        fire.particleColor = NSColor(red: 1, green: 0.52, blue: 0.12, alpha: 1); fire.particleColorVariation = SCNVector4(0.04, 0.1, 0, 0)
        fire.blendMode = .additive; fire.isLightingEnabled = false; fire.isAffectedByGravity = false
        fire.particleImage = flameSprite
        let fade = CAKeyframeAnimation(); fade.values = [0.0, 1.0, 0.6, 0.0]; fade.keyTimes = [0, 0.15, 0.6, 1]
        let shrink = CAKeyframeAnimation(); shrink.values = [1.0, 0.8, 0.2]; shrink.keyTimes = [0, 0.5, 1]
        fire.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade), .size: SCNParticlePropertyController(animation: shrink)]
        node.addParticleSystem(fire)
        return (node, fire)
    }
    private static let flameSprite: NSImage = {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSGradient(colors: [.white, NSColor(white: 1, alpha: 0)])?.draw(in: NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 64, height: 64)), relativeCenterPosition: .zero)
        image.unlockFocus()
        return image
    }()
    private var pacingPending: Bool {
        pacing.contains { id, state in state.arriving || (state.want != nil && state.want?.key != chefs[id]?.director.intent?.key) || slots[id]?.id.contains("~") == true }
    }
    private func openElevator() {
        guard let car = scene?.rootNode.childNode(withName: "elevator", recursively: false) else { return }
        let width = CGFloat(KitchenLayout.areas.first { $0.id == "elevator" }?.footprint.width ?? 2.4)
        for (name, direction) in [("elevator door left", -1.0), ("elevator door right", 1.0)] {
            guard let door = car.childNode(withName: name, recursively: false), door.action(forKey: "doors") == nil else { continue }
            let slide = CGFloat(direction) * (width / 2 - 0.2)
            door.runAction(.sequence([.moveBy(x: slide, y: 0, z: 0, duration: 0.6), .wait(duration: 2.4), .moveBy(x: -slide, y: 0, z: 0, duration: 0.6)]), forKey: "doors")
        }
    }
    /// Diagnostics: when /tmp/diorama-kitchen-frames.log exists, frame gaps over 50 ms, slow
    /// reconciles and playback pauses are appended to it.
    nonisolated static func trace(_ text: @autoclosure () -> String) {
        // Opened per event (events are rare), so the file can be created or removed at any time.
        guard let log = FileHandle(forWritingAtPath: "/tmp/diorama-kitchen-frames.log") else { return }
        defer { try? log.close() }
        log.seekToEndOfFile(); log.write(Data((String(format: "%.3f ", CACurrentMediaTime()) + text() + "\n").utf8))
    }
    func frameStep(at time: TimeInterval, lagging: Bool = false) {
        chefLock.lock(); let previousStep = lastMainStep; lastMainStep = CACurrentMediaTime(); chefLock.unlock()
        if lastFrame != nil, lastMainStep - previousStep > 0.05 { Self.trace(String(format: "tag gap %.0f ms", (lastMainStep - previousStep) * 1000)) }
        if !lagging, let last = lastFrame, time - last > 0.05 { Self.trace(String(format: "gap %.0f ms", (time - last) * 1000)) }
        let stepStart = CACurrentMediaTime()
        defer { if CACurrentMediaTime() - stepStart > 0.02 { Self.trace(String(format: "slow frameStep %.0f ms", (CACurrentMediaTime() - stepStart) * 1000)) } }
        let delta = lastFrame.map { Float(min(0.05, max(0, time - $0))) } ?? 0
        lastFrame = time
        // Chefs advance on the render thread; this loop paces them, places tags and moves the
        // free camera while keys are held.
        if !freeCamera.held.isEmpty, selectedID == nil {
            freeCamera.step(delta)
            applyFreeCamera()
        }
        chefLock.lock(); pace(now: CACurrentMediaTime()); chefLock.unlock()
        logStations()
        updateFlames()
        updateBoards()
        noticeSilence()
        refreshLabels()
        placeChefLabels()
        updatePlayback()
    }
    /// Written task labels arrive a few seconds after a chef appears; swap them into the tags.
    private func refreshLabels() {
        guard TaskLabels.shared.revision != labelRevision else { return }
        labelRevision = TaskLabels.shared.revision
        for (id, agent) in chefAgents {
            let content = ChefTagContent.make(agent, review: pacing[id]?.review)
            chefLabels[id]?.update(content, reducedMotion: reduced); chefBars[id]?.update(content.progress)
        }
    }
    /// A working agent that has gone quiet (composing a long file, thinking) shows a thought
    /// bubble now and then.
    private func noticeSilence(now: Date = Date()) {
        let time = CACurrentMediaTime()
        guard time - lastSilenceCheck >= 1, !catchingUp else { return }
        lastSilenceCheck = time
        for (id, agent) in chefAgents where agent.fresh && ChefMoment.silent(agent.value, now: now) {
            guard now.timeIntervalSince(lastThinking[id] ?? .distantPast) >= ChefMoment.thinkingEvery else { continue }
            lastThinking[id] = now
            chefEmotes[id]?.react([.thinking], now: now)
        }
    }
    private var effectiveActive: Bool { active && !isHiddenOrHasHiddenAncestor && (window == nil || window?.occlusionState.contains(.visible) == true) }
    /// Whether someone can see this kitchen. A view outside any window (tests, capture) counts as
    /// seen, so it always paces and animates.
    var observed: Bool { window == nil || effectiveActive }
    /// When the kitchen last came into view after being out of view, for catching up.
    private var observedSince: Double? = 0
    /// Out of view, and for a moment after coming back, changes take effect at once: the kitchen
    /// looks as if it kept working while nobody watched.
    private var catchingUp: Bool { observedSince.map { CACurrentMediaTime() - $0 < Self.catchUpWindow } ?? true }
    static let catchUpWindow = 1.5
    private func noteObservation() {
        if !observed { observedSince = nil; if !freeCamera.held.isEmpty { freeCamera.releaseAll() } }
        else if observedSince == nil { observedSince = CACurrentMediaTime(); catchUp() }
    }
    /// Jump every chef to where its agent's current state puts it: no walk, no replayed gesture,
    /// and a dish waiting for review already on the pass.
    func catchUp() {
        chefLock.lock(); defer { chefLock.unlock() }
        let now = CACurrentMediaTime()
        for id in chefs.keys.sorted() {
            guard let chef = chefs[id], var state = pacing[id] else { continue }
            let director = chef.director
            state.arriving = false; state.owed = []; pacing[id] = state
            let walking = director.intent?.station != nil && director.station == nil
            guard walking || state.want?.key != director.intent?.key || queuedWithFreeSpot(id) else { continue }
            if queuedWithFreeSpot(id) { slots[id] = nil }
            guard let next = wanted(id, claim: true, restored: true) else { continue }
            if let station = next.station { director.place(station.stand, heading: station.facing) }
            director.setIntent(next, force: true)
            state.want = wanted(id, claim: false)
            state.arrivedAt = now - KitchenLayout.minimumDwell
            pacing[id] = state
        }
    }
    func updatePlayback() {
        noteObservation()
        // Only chef state is read under the lock: SceneKit playback setters can wait on the
        // renderer, which may itself be waiting for the lock in renderer(_:updateAtTime:).
        chefLock.lock()
        let animating = chefs.values.contains(where: \.animating) || pacingPending || cameraMoving || !freeCamera.held.isEmpty
        chefLock.unlock()
        let moving = effectiveActive && animating
        if isPlaying != moving { isPlaying = moving }
        if moving, motionActivity == nil {
            motionActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Animating the kitchen")
        } else if !moving, let activity = motionActivity {
            ProcessInfo.processInfo.endActivity(activity); motionActivity = nil
        }
        if rendersContinuously != moving { rendersContinuously = moving }
        if !moving { chefLock.lock(); lastRenderTime = nil; chefLock.unlock() } // a pause is not a stall
        if frameLink?.isPaused != !moving {
            Self.trace("playback \(moving ? "running" : "paused") active=\(active) window=\(window?.occlusionState.contains(.visible) ?? false)")
            frameLink?.isPaused = !moving
        }
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
        // Keys held when the window loses focus would otherwise keep the camera moving.
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.freeCamera.releaseAll() }
        })
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                // Local monitors run on the main thread.
                nonisolated(unsafe) let event = event
                let handled = MainActor.assumeIsolated { self?.handleKey(event) == true }
                return handled ? nil : event
            }
        }
        updatePlayback()
    }
    /// Select a chef (nil clears it): ring it, follow it, and hide the other name tags. Clearing
    /// waits a moment: switching to another chef passes through "nothing selected" (the
    /// conversation changes first), and the camera should glide across, not pull back and in.
    func setSelection(_ agentID: String?, immediately: Bool = false) {
        if agentID == nil, selectedID != nil, !immediately {
            guard pendingDeselect == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingDeselect = nil
                self.selectedID = nil; self.syncSelection()
            }
            pendingDeselect = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.deselectGrace, execute: work)
            return
        }
        pendingDeselect?.cancel(); pendingDeselect = nil
        guard agentID != selectedID else { return }
        selectedID = agentID
        syncSelection()
    }
    private var pendingDeselect: DispatchWorkItem?
    static let deselectGrace = 0.25
    /// Keeps the ring, the followed chef and the station signs in line with the selection, also
    /// when the selected chef appears or leaves after it was chosen.
    private func syncSelection() {
        let chef = selectedID.flatMap { chefs[$0] }
        chefLock.lock()
        let previous = followID
        followID = chef == nil ? nil : selectedID
        if followID != previous { cameraMoving = true; snapCamera = reduced }
        chefLock.unlock()
        // The others step back: dimmed while a chef is selected.
        for (id, other) in chefs {
            let opacity: CGFloat = selectedID == nil || id == selectedID ? 1 : 0.4
            if other.root.opacity != opacity {
                SCNTransaction.begin(); SCNTransaction.animationDuration = reduced ? 0 : 0.25
                other.root.opacity = opacity
                SCNTransaction.commit()
            }
        }
        // Flying to a chef takes the camera; keys held for the free camera are let go.
        if chef != nil, !freeCamera.held.isEmpty { freeCamera.releaseAll() }
        if let chef {
            let ring = selectionRing ?? Self.makeSelectionRing(reducedMotion: reduced)
            selectionRing = ring
            if ring.parent !== chef.root { ring.removeFromParentNode(); chef.root.addChildNode(ring) }
        } else {
            selectionRing?.removeFromParentNode()
        }
        // Station signs and their leaders are drawn for the overview; they step aside while the
        // camera is anywhere else.
        let overview = chef == nil && !cameraMoving && freeCamera.isHome
        for label in labels where label.isHidden == overview { label.isHidden = !overview }
        if leaders.isHidden == overview { leaders.isHidden = !overview }
        if overview { placeLabels() }
        placeChefLabels()
        updatePlayback()
    }
    /// Eases the camera toward the followed chef, or back to the overview (render thread, under
    /// `chefLock`).
    nonisolated private func stepCamera(_ delta: Float) {
        guard let camera = cameraNode, let overview = overviewPose else { return }
        let target = followID.flatMap { id in renderChefs.first { $0.id == id } }.map { Self.followPose(for: $0.root.simdPosition) } ?? overview
        guard cameraMoving || followID != nil else { return }
        var pose = cameraPose ?? overview
        let blend = snapCamera ? 1 : 1 - exp(-delta / Self.cameraEase)
        pose.eye += (target.eye - pose.eye) * blend
        pose.look += (target.look - pose.look) * blend
        let arrived = simd_distance(pose.eye, target.eye) < 0.01 && simd_distance(pose.look, target.look) < 0.01
        if arrived { pose = target }
        cameraPose = pose
        camera.simdPosition = pose.eye
        camera.simdLook(at: pose.look)
        if followID == nil && arrived {
            cameraMoving = false; snapCamera = false
            // Back on the overview: the station signs return on the main thread.
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.syncSelection() } }
        }
    }
    /// A glowing ring on the floor around the selected chef, slowly turning (StarCraft-style).
    static func makeSelectionRing(reducedMotion: Bool) -> SCNNode {
        let size = CGFloat(1.75 * KitchenLayout.chefScale)
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.diffuse.contents = selectionRingImage
        material.lightingModel = .constant; material.blendMode = .add
        material.writesToDepthBuffer = false; material.isDoubleSided = true
        plane.materials = [material]
        let disc = SCNNode(geometry: plane); disc.name = "selection ring disc"
        disc.eulerAngles.x = -.pi / 2
        disc.position.y = CGFloat(KitchenLayout.floorTop) + 0.012
        disc.renderingOrder = 5; disc.castsShadow = false
        let ring = SCNNode(); ring.name = "selection ring"
        ring.addChildNode(disc)
        if !reducedMotion {
            ring.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 7)))
            disc.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.6, duration: 0.9), .fadeOpacity(to: 1, duration: 0.9)])))
        }
        return ring
    }
    /// Soft glow, a bright ring and three bright arcs that make the turning visible.
    private static let selectionRingImage: NSImage = {
        let side: CGFloat = 512
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        let center = NSPoint(x: side / 2, y: side / 2), radius = side * 0.40
        let color = NSColor(red: 0.35, green: 1, blue: 0.62, alpha: 1)
        if let context = NSGraphicsContext.current?.cgContext,
           let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(0.45).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0.62, 0.8, 1]) {
            context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
        color.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(); ring.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360); ring.lineWidth = 7; ring.stroke()
        color.setStroke()
        for start in stride(from: 0.0, to: 360.0, by: 120.0) {
            let arc = NSBezierPath(); arc.appendArc(withCenter: center, radius: radius + 18, startAngle: start, endAngle: start + 62)
            arc.lineWidth = 14; arc.lineCapStyle = .round; arc.stroke()
        }
        image.unlockFocus()
        return image
    }()
    func tearDown() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let activity = motionActivity { ProcessInfo.processInfo.endActivity(activity); motionActivity = nil }
        frameLink?.invalidate(); frameLink = nil; frameDriver = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers = []
        scene = nil
    }
    /// Projects a world point to view coordinates (origin bottom-left, like `projectPoint`) with
    /// the camera's matrices. `projectPoint` takes SceneKit's scene lock and waits for the
    /// renderer, which stalled every animation frame when used for per-frame name tags.
    func projectWithoutLock(_ point: SIMD3<Float>) -> CGPoint? {
        guard let eye = pointOfView, let camera = eye.camera, bounds.width > 0, bounds.height > 0 else { return nil }
        let projection = simd_float4x4(camera.projectionTransform(withViewportSize: bounds.size))
        let clip = projection * eye.simdWorldTransform.inverse * SIMD4(point, 1)
        guard clip.w > 0.0001 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return CGPoint(x: CGFloat(ndc.x + 1) / 2 * bounds.width, y: CGFloat(ndc.y + 1) / 2 * bounds.height)
    }
    private func placeChefLabels() {
        var placed: [CGRect] = []
        chefLock.lock()
        let positions = chefs.mapValues(\.root.simdPosition)
        chefLock.unlock()
        for (id, position) in positions.sorted(by: { $0.key < $1.key }) {
            guard let label = chefLabels[id] else { continue }
            // A selected chef has the stage to itself; resting chefs show their tag on hover.
            let emote = chefEmotes[id], bar = chefBars[id]
            emote?.isHidden = true; bar?.isHidden = true
            if let selectedID, selectedID != id { label.isHidden = true; continue }
            if selectedID == nil, label.content?.resting == true, hoveredID != id { label.isHidden = true; continue }
            let head = position + SIMD3(0, 2.05 * KitchenLayout.chefScale, 0)
            guard let point = projectWithoutLock(head) else { label.isHidden = true; continue }
            label.isHidden = false
            let size = label.tagSize
            // Top to bottom above the head: emote, tag, then the progress bar (when there's a list).
            let barRoom: CGFloat = bar?.fraction == nil ? 0 : ChefProgressView.size.height + 2
            let width = size.width, height = size.height + barRoom
            let y = isFlipped ? bounds.height - CGFloat(point.y) : CGFloat(point.y)
            // Keep name tags fully inside the view near the walls.
            let x = min(max(4, CGFloat(point.x) - width / 2), max(4, bounds.width - width - 4))
            var frame = CGRect(x: x, y: min(max(4, y), max(4, bounds.height - height - 4)), width: width, height: height)
            // Neighbouring chefs (e.g. side by side in the break room) stack their tags instead of overlapping.
            while let clash = placed.first(where: { $0.insetBy(dx: -2, dy: -1).intersects(frame) }) {
                frame.origin.y = isFlipped ? clash.maxY + 2 : clash.minY - height - 2
            }
            placed.append(frame)
            // `frame` holds tag and bar together; the bar sits nearest the head.
            let tagFrame = CGRect(x: frame.minX, y: isFlipped ? frame.minY : frame.minY + barRoom, width: width, height: size.height)
            label.frame = tagFrame
            if let bar, barRoom > 0 {
                let barSize = ChefProgressView.size
                bar.frame = CGRect(x: tagFrame.midX - barSize.width / 2, y: isFlipped ? tagFrame.maxY + 2 : tagFrame.minY - 2 - barSize.height, width: barSize.width, height: barSize.height)
                bar.isHidden = false
            }
            // The emote sits just above the tag, centred on it.
            if let emote {
                let size = ChefEmoteView.size
                emote.frame = CGRect(x: tagFrame.midX - size.width / 2, y: isFlipped ? tagFrame.minY - size.height - 2 : tagFrame.maxY + 2, width: size.width, height: size.height)
                emote.isHidden = false
            }
        }
    }
    /// Pointer tracking: resting chefs reveal their tag under the pointer.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var found: String?
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]) {
            if let node = sequence(first: hit.node, next: \.parent).first(where: { $0.name?.hasPrefix("agent:") == true }) { found = String(node.name!.dropFirst(6)); break }
        }
        if found != hoveredID { hoveredID = found; placeChefLabels() }
    }
    override func mouseExited(with event: NSEvent) { if hoveredID != nil { hoveredID = nil; placeChefLabels() } }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Name tags sit above the 3D scene; a click on one opens that chef's progress.
        if let progress, let id = chefLabels.first(where: { !$0.value.isHidden && $0.value.frame.contains(point) })?.key, let agent = chefAgents[id] {
            progress(agent); return
        }
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("agent:"), let agent = chefAgents[String(name.dropFirst(6))] {
                    chefLock.lock(); let area = chefs[agent.id]?.director.intent?.station?.area; chefLock.unlock()
                    // The first click selects; clicking the selected chef at the pass opens its review,
                    // and at the bell its pending request.
                    let ready = selectedID == agent.id || selectedID == nil && deselect == nil
                    if let review, area == "serving", ready { review(agent); return }
                    if let requestReview, area == "bell", ready { requestReview(agent); return }
                    select?(.agent(project: agent.projectID, conversation: agent.conversationID, agent: agent.id, expanded: true))
                    return
                }
                node = current.parent
            }
        }
        // The pantry wall opens the pantry.
        if let openPantry, hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]).contains(where: { hit in
            sequence(first: hit.node, next: \.parent).contains { $0.name == "pantry" }
        }) { openPantry(); return }
        // Anywhere else in the kitchen clears the selection.
        if selectedID != nil, let deselect { deselect(); return }
        super.mouseUp(with: event)
    }
    var floorCorners: [SCNVector3] {
        var result: [SCNVector3] = []
        let signs: [Float] = [-1, 1]
        let half = SIMD2(Float(KitchenLayout.floor.width / 2), Float(KitchenLayout.floor.height / 2))
        for x in signs { for y in signs { for z in signs { result.append(SCNVector3(x * half.x, y * 0.1, z * half.y)) } } }
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
        freeCamera.setHome(center: SIMD2(Float(target.x), Float(target.z)), distance: Float(distance))
        chefLock.lock()
        overviewPose = CameraPose(eye: freeCamera.eye, look: freeCamera.look)
        // Zoomed or turned, the render thread eases the camera; only the home view is placed here.
        let following = followID != nil || cameraMoving || !freeCamera.isHome
        if !following { cameraPose = overviewPose }
        chefLock.unlock()
        // While a chef is followed the render thread owns the camera; it returns here on deselect.
        guard !following else { needsDisplay = true; return }
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
            // Lock-free, like the name tags: `projectPoint` waits for the renderer, and the signs are
            // placed on every agent update.
            guard let point = projectWithoutLock(SIMD3(Float(area.footprint.midX), 2.6, Float(area.footprint.minY))) else { continue }
            let anchor = CGPoint(x: point.x, y: isFlipped ? bounds.height - point.y : point.y)
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

extension KitchenSceneView: SCNSceneRendererDelegate {
    /// Runs on SceneKit's render thread every rendered frame, independent of main-thread work.
    nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        chefLock.lock(); defer { chefLock.unlock() }
        if let last = lastRenderTime, time - last > 0.05 { Self.trace(String(format: "render gap %.0f ms", (time - last) * 1000)) }
        let delta = lastRenderTime.map { Float(min(0.1, max(0, time - $0))) } ?? 0
        lastRenderTime = time
        for chef in renderChefs { chef.update(delta) }
        stepCamera(delta)
        // macOS slows the main thread's frame link while another app is in front; the render
        // thread keeps full rate, so it asks for the tag/pacing step whenever that link falls behind.
        if !mainStepQueued, time - lastMainStep > 0.03 {
            mainStepQueued = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.chefLock.lock(); self.mainStepQueued = false; let late = CACurrentMediaTime() - self.lastMainStep > 0.03; self.chefLock.unlock()
                    if late, self.frameLink?.isPaused == false { self.frameStep(at: CACurrentMediaTime(), lagging: true) }
                }
            }
        }
    }
}
