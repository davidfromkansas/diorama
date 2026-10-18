import DioramaCore
import SceneKit
import SwiftUI

struct SceneSurface: NSViewRepresentable {
    /// The project's scene (`ProjectPresentationSnapshot.scene`).
    var kind: SceneKind = .kitchen
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
    /// A chef picked up by the pointer (nil when put down), for hiding the UI and showing the trash.
    var holding: ((KitchenHold?) -> Void)? = nil
    /// Why a chef can't go in the trash (nil when it can), and archiving one dropped there.
    var archiveBlocker: ((SpatialAgent) -> String?)? = nil
    var archive: ((SpatialAgent) -> Void)? = nil
    /// The trash can's frame in window coordinates (top-left origin, SwiftUI's global space).
    var trashFrame: CGRect = .zero
    /// How many files an agent's task changed since it began, for a done chef's tag.
    var changedFiles: ((SpatialAgent) -> Int?)? = nil
    /// The model each agent runs on, for its tag.
    var modelName: ((SpatialAgent) -> String)? = nil
    func makeNSView(context: Context) -> SceneStage { SceneStage() }
    func updateNSView(_ stage: SceneStage, context: Context) {
        let view = stage.show(scope ?? "", kind: kind)
        view.select = select
        view.review = review
        view.requestReview = requestReview
        view.progress = progress
        view.reviews = reviews
        view.deselect = deselect
        view.openPantry = openPantry
        view.cameraMoved = cameraMoved
        view.holding = holding
        view.archiveBlocker = archiveBlocker
        view.archive = archive
        view.trashFrame = trashFrame
        view.changedFiles = changedFiles
        view.modelName = modelName
        if stage.cameraResets != resetCamera { stage.cameraResets = resetCamera; view.resetCamera() }
        view.apply(agents: agents, scope: scope, active: active, reducedMotion: reducedMotion)
        view.setSelection(selectedAgentID)
        view.fitFloor()
    }
    static func dismantleNSView(_ stage: SceneStage, coordinator: ()) { stage.tearDown() }
}

/// One scene per project, kept while you look at other projects or tabs, so switching back
/// shows the same chefs (caught up to what their agents did meanwhile) instead of a rebuilt room.
/// Switching a project to another kind of scene replaces its view: the new scene places every
/// chef where its agent's state puts it (no elevator rides) with the camera at home.
final class SceneStage: NSView {
    static let maxKitchens = 6
    private(set) var kitchens: [String: DioramaSceneView] = [:]
    private var recency: [String] = []
    private(set) var current: String?
    var cameraResets = 0

    /// The scene for `scope`, now the only one on screen.
    @discardableResult func show(_ scope: String, kind: SceneKind = .kitchen) -> DioramaSceneView {
        if let existing = kitchens[scope], existing.theme.kind != kind {
            existing.tearDown(); existing.removeFromSuperview(); kitchens[scope] = nil
            if current == scope { current = nil }
        }
        let view = kitchens[scope] ?? {
            let view = DioramaSceneView(frame: bounds, theme: SceneThemes.theme(kind))
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
@MainActor private final class SceneFrameDriver: NSObject {
    weak var view: DioramaSceneView?
    @objc func frame(_ link: CADisplayLink) { view?.frameStep(at: link.targetTimestamp) }
}
/// A station's sign: small capitals on a soft dark capsule, readable on any floor.
private final class KitchenLabel: NSTextField {
    override class var cellClass: AnyClass? { get { CenteredLabelCell.self } set {} }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    static let height: CGFloat = 18
    func style(_ title: String) {
        attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .kern: 0.9,
            .foregroundColor: NSColor.white.withAlphaComponent(0.96),
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()
        ])
        isBezeled = false; drawsBackground = false; lineBreakMode = .byTruncatingTail; maximumNumberOfLines = 1
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.09, blue: 0.14, alpha: 0.58).cgColor
        layer?.cornerRadius = Self.height / 2
    }
}
/// Draws a single line centred vertically, so the text sits in the middle of the capsule.
private final class CenteredLabelCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let height = attributedStringValue.size().height
        return NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        attributedStringValue.draw(in: titleRect(forBounds: cellFrame))
    }
}

/// Kitchen workspace: the focused project's agents appear as chefs working at the station that
/// matches their state. It only observes agent state; it never controls provider execution.
final class DioramaSceneView: SCNView {
    /// What this scene is (the kitchen, the office): its layout, fixtures, light and sounds.
    let theme: any SceneTheme
    /// The theme's floor plan and station table.
    let floorPlan: SceneLayout
    /// The theme's sound set, read on the render thread.
    nonisolated let soundFolder: String
    /// The lounge (break room) is silent: chefs resting or walking about in it make no sound.
    nonisolated let quietArea: CGRect
    private let kit: ChefAvatar.Kit
    /// Only the break room is limited: one chef per seat, the most recently active idle
    /// conversations. Everyone working, needing you or serving is always in the kitchen (extra
    /// chefs queue behind a busy station).
    /// At most this many chefs rest in the break room: the six most recently active.
    static let maxResting = 6
    var maxResting: Int { Self.maxResting }
    var floorSize: SIMD3<Float> { SIMD3(Float(floorPlan.floor.width), 0.2, Float(floorPlan.floor.height)) }
    var select: ((SpatialFocus) -> Void)?
    var review: ((SpatialAgent) -> Void)?
    var requestReview: ((SpatialAgent) -> Void)?
    var progress: ((SpatialAgent) -> Void)?
    var deselect: (() -> Void)?
    var openPantry: (() -> Void)?
    var holding: ((KitchenHold?) -> Void)?
    var archiveBlocker: ((SpatialAgent) -> String?)?
    var archive: ((SpatialAgent) -> Void)?
    var trashFrame: CGRect = .zero
    /// A press on a chef that becomes a pick-up after `holdDelay` or a small drag.
    private var press: (id: String, at: CGPoint, timer: Timer)?
    /// The chef in the pointer's grip, and what the trash makes of it.
    private(set) var heldID: String?
    private var hold: KitchenHold?
    /// Chefs dropped in the trash: kept out of the kitchen while their thread archives.
    private var trashed: [String: Double] = [:]
    static let holdDelay = 0.25, trashedFor = 8.0
    var reviews: [String: KitchenReviews.State] = [:]
    private(set) var chefs: [String: ChefAvatar] = [:]
    private var chefAgents: [String: SpatialAgent] = [:]
    /// Tags above the chefs: name, live step and progress bar.
    private(set) var chefLabels: [String: ChefTagView] = [:]
    private var lastSilenceCheck: TimeInterval = 0
    /// The task-label revision the tags were last written with.
    private var labelRevision = TaskLabels.shared.revision
    /// Changed-file counts for done chefs' tags, and the revision they were last written with.
    var changedFiles: ((SpatialAgent) -> Int?)?
    var modelName: ((SpatialAgent) -> String)?
    private var changeRevision = SessionChangeCounts.shared.revision
    /// The chef under the pointer: its tag gets an outline; resting chefs show their tag only then.
    private var hoveredID: String?
    private var slots: [String: ChefStation] = [:]
    private let navigation: FloorNavigation
    private var active = false
    private var reduced = false
    private var frameLink: CADisplayLink?
    private var frameDriver: SceneFrameDriver?
    private var lastFrame: TimeInterval?
    private var windowObservers: [NSObjectProtocol] = []
    private var labels: [NSTextField] = []
    /// The stations' live details (burner flames, idle boards, desk screens).
    private var effects: [any SceneStationEffect] = []
    private let leaders = CAShapeLayer()
    private var fittedSize = CGSize.zero
    var labelFrames: [CGRect] { labels.map(\.frame) }
    init(frame: NSRect = .zero, options: [String: Any]? = nil, theme: any SceneTheme = KitchenTheme.shared) {
        self.theme = theme; floorPlan = theme.layout; soundFolder = theme.soundFolder; kit = theme.avatarKit
        quietArea = theme.layout.loungeArea
        navigation = floorPlan.chefNavigation; slotTable = floorPlan.chefSlots
        super.init(frame: frame, options: options)
        let world = SCNScene()
        world.background.contents = theme.backdrop
        for node in theme.buildRoom() { world.rootNode.addChildNode(node) }
        if let surroundings = theme.surroundings {
            world.rootNode.addChildNode(surroundings.make())
            seatDiners(surroundings, in: world)
        }
        var stations: [String: SCNNode] = [:]
        for area in floorPlan.areas {
            let station = theme.buildStation(area)
            world.rootNode.addChildNode(station); stations[area.id] = station
            let label = KitchenLabel(labelWithString: area.short)
            label.toolTip = area.label; label.setAccessibilityLabel(area.label)
            label.style(area.short)
            labels.append(label); addSubview(label)
        }
        effects = theme.makeEffects(world: world.rootNode, stations: stations)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = false
        camera.camera?.projectionDirection = .vertical
        camera.camera?.fieldOfView = 38; camera.camera?.zNear = 0.1; camera.camera?.zFar = 200
        // Overcooked-style framing: elevated front view with screen-aligned aisles.
        let elevation = Double(KitchenCameraController.elevationDegrees) * Double.pi / 180, yaw = 0.0
        camera.position = SCNVector3(30 * cos(elevation) * sin(yaw), 30 * sin(elevation), 30 * cos(elevation) * cos(yaw))
        camera.look(at: SCNVector3(0, 0.65, 0)); world.rootNode.addChildNode(camera)
        cameraNode = camera
        if let lens = camera.camera { theme.light(world.rootNode, camera: lens) }
        scene = world; pointOfView = camera; autoenablesDefaultLighting = false
        delegate = self
        KitchenAudio.shared.prepare()
        allowsCameraControl = false; isPlaying = false; rendersContinuously = false
        wantsLayer = true; leaders.strokeColor = NSColor(srgbRed: 0.10, green: 0.09, blue: 0.14, alpha: 0.22).cgColor
        leaders.fillColor = nil; leaders.lineWidth = 1; layer?.addSublayer(leaders)
        setAccessibilityLabel(theme.vocabulary.place.capitalized + " layout. " + floorPlan.areas.map(\.label).joined(separator: ", ") + ".")
        setAccessibilityHelp(Self.controlsHint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); fitFloor(); chefLock.lock(); soundWidth = bounds.width; chefLock.unlock() }

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
        /// Arriving, still stepping out of the elevator and waving (before heading to the rail).
        var exiting = false
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
    private let slotTable: [String: [ChefStation]]
    /// Chefs are stepped on SceneKit's render thread (`renderer(_:updateAtTime:)`) so their
    /// animation never waits for the main thread; main-thread steering takes the same lock.
    nonisolated let chefLock = NSRecursiveLock()
    nonisolated(unsafe) private var renderChefs: [ChefAvatar] = []
    nonisolated(unsafe) private var lastRenderTime: TimeInterval?
    /// When the main thread last placed tags and paced chefs, and whether the render thread has
    /// already asked for another step (both under `chefLock`).
    nonisolated(unsafe) private var lastMainStep: TimeInterval = 0
    nonisolated(unsafe) private var mainStepQueued = false
    /// From when chef sounds may play (under `chefLock`): nil out of view, and only once the
    /// kitchen has caught up so the jump to where chefs already are stays silent.
    nonisolated(unsafe) private var soundsFrom: Double?
    nonisolated(unsafe) private var soundWidth: CGFloat = 0
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
    /// Glides the free camera to look at a spot on the floor (world x, z), `zoom` times closer
    /// than home (the development demo's camera moves; `resetCamera` goes back).
    func focusCamera(on center: SIMD2<Float>, zoom: Float) {
        freeCamera.force(.init(center: center, zoom: min(KitchenCameraController.maxZoom, max(1, zoom)), yaw: 0))
        applyFreeCamera()
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
        if heldID != nil, event.keyCode == 53 { if event.type == .keyDown { drop(cancelled: true) }; return true }
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
            case "a":
                // A hides every chef's name tag, and shows them again; in every kitchen.
                if down, !event.isARepeat { Self.tagsHidden.toggle(); placeChefLabels() }
                return true
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
        let elevation: Float = KitchenCameraController.elevationDegrees * .pi / 180, distance: Float = 8.5
        let look = position + SIMD3(0, 1.2, 0)
        return CameraPose(eye: look + SIMD3(0, distance * sin(elevation), distance * cos(elevation)), look: look)
    }
    /// Seconds for the camera to cover most of the way to its target.
    nonisolated static let cameraEase: Float = 0.35
    private func publishChefs() { chefLock.lock(); renderChefs = Array(chefs.values) + diners + (manager.map { [$0] } ?? []); chefLock.unlock() }
    /// Projects (or standalone conversations) already shown here: only agents that start while
    /// their project is on screen ride the elevator in; everything else appears in place.
    private var seenScopes: Set<String> = []
    /// Every chef this kitchen has shown, and where each removed one last stood: a chef that
    /// comes back (its agent got feedback, or the cap had pushed it out) returns to work from
    /// there instead of arriving by elevator.
    private var shownChefs: Set<String> = []
    /// Which character each agent's chef wears (shared by every kitchen; tests swap in their own).
    var characters = ChefCharacterModel.shared
    private var departed: [String: (position: SIMD2<Float>, heading: Float)] = [:]
    /// When each shown chef started resting: it keeps its place past the cap long enough to walk
    /// to the break room and sit down, rather than vanishing from the serving window.
    private var restingSince: [String: Double] = [:]
    static let walkOff: Double = 25
    /// Diners at the restaurant's tables beside the kitchen, and which finished task each one was
    /// served (by conversation): its dish on their table until the work is accepted.
    private(set) var diners: [ChefAvatar] = []
    /// The manager (the head chef), in the kitchen while chefs wait at the gong (see `updateManager`).
    private(set) var manager: ChefAvatar?
    /// Who rests where in the break room and what they're up to (`BreakRoom`), on the scene clock.
    private(set) lazy var breakRoom = BreakRoom(spots: floorPlan.lounge.spots, durations: (try? ChefAssets.shared.get())?.manifest.clips.mapValues { Double($0.duration) } ?? [:])
    private var breakClock = CACurrentMediaTime()
    /// Emoji bubbles over chefs in the break room, when each chef last had one, and how far each
    /// arcade player is into its game (its win shows a trophy).
    private var bubbles: [String: ChefBubbleView] = [:]
    private var lastBubble: [String: Double] = [:]
    private var arcadeTime: [String: Float] = [:]
    private var arcadeWins: [String: Int] = [:]
    private var bubbleCount = 0
    /// The chef the manager is going to, the spot it talks from, and the chef it is talking with
    /// once it got there; leaving once nobody waits.
    private(set) var managerVisit: (id: String, spot: ChefStation)?
    private(set) var managerTalking: String?
    private var managerLeaving = false
    /// Gong strikes already shown (the sum over chefs' `gongStrikes`), and the chefs standing at a
    /// bell that rings on arrival.
    private var gongStrikesSeen = 0
    private var atBell: Set<String> = []
    /// What each guest is doing (see `RestaurantGuests`), and the food on their tables.
    private(set) var guests = RestaurantGuests(positions: [], durations: [:])
    private(set) var tablePlates: [SCNNode?] = []
    private var cheers = 0
    private var served: [String: (seat: Int, dish: SCNNode?, leftAt: Double?)] = [:]
    static let dinerCount = 12, dinerLinger = 8.0

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
        let base = options[n % options.count], back = Float(n / options.count + 1) * 0.95 * ChefMetrics.chefScale
        let queued = ChefStation(id: "\(base.id)~\(n)", area: area, stand: base.stand - SIMD2(sin(base.facing), cos(base.facing)) * back, facing: base.facing)
        slots[id] = queued
        return queued
    }
    /// The intent this chef's agent calls for. It keeps the chef's spot when the area is the
    /// same; otherwise it claims a new spot (`claim`) or uses a placeholder for comparison.
    private func wanted(_ id: String, claim: Bool, restored: Bool = false) -> ChefIntent? {
        guard let state = pacing[id], let chef = chefs[id] else { return nil }
        let work = floorPlan.work(for: state.agent, review: state.review)
        var slot: ChefStation?
        if work.area == "break" {
            // The break room hands out its own spots (a machine, a chair or a place in a circle).
            breakRoom.join(id, now: breakClock)
            slot = breakRoom.station(for: id)
            if claim, let slot { slots[id] = slot }
        } else if let area = work.area {
            if let current = slots[id], current.area == area { slot = current }
            else if claim { slot = claimSlot(id, area: area) }
            else { slot = ChefStation(id: "pending:" + area, area: area, stand: .zero, facing: 0) }
        }
        // Finished chefs pick their plate up where they already work, never at a shared spot.
        let pickup = chef.director.station.flatMap { ["cooking", "stove", "prep", "tasting"].contains($0.area) ? $0 : nil }
        var intent = floorPlan.intent(for: state.agent, at: slot, pickup: pickup, restored: restored, review: state.review)
        // Waiting at the gong with the manager beside it: turned to the manager, talking it over.
        if managerTalking == id, let visit = managerVisit, let station = intent.station, station.area == "bell", !station.id.hasPrefix("pending:") {
            let toward = visit.spot.stand - station.stand
            intent.station = ChefStation(id: station.id, area: station.area, stand: station.stand, facing: atan2(toward.x, toward.y))
            intent.loop = "talk_reply"
            intent.key += "|talk"
        }
        if let station = intent.station, station.area == "break", let member = breakRoom.members[id], let kind = breakRoom.kind(of: id) {
            intent = breakIntent(intent, member: member, kind: kind)
        }
        return intent
    }
    /// A resting chef's intent at its break-room spot: the room's clip, and at a machine its
    /// gesture (fetching a soda, pulling a shot) and what it then holds.
    private func breakIntent(_ base: ChefIntent, member: BreakRoom.Member, kind: BreakRoomLayout.Kind) -> ChefIntent {
        var intent = base
        let restored = base.oneShot?.restored ?? false
        intent.loop = member.clip.isEmpty ? "idle_available" : member.clip
        switch kind {
        case .arcade:
            intent.hand = nil; intent.oneShot = nil
        case .vending, .espresso:
            let gesture = kind == .vending ? "use_vending" : "brew_espresso"
            intent.hand = kind == .vending ? .can : .mug
            intent.oneShot = .init(id: "\(gesture):\(member.since)", clip: gesture, restored: restored)
        case .chair:
            intent.hand = member.clip == "sit_sip" ? .mug : nil  // keeps `sit_down` from the rest work
        case .circle:
            intent.hand = nil; intent.oneShot = nil
        }
        intent.key = ["break", intent.station?.id ?? "", intent.loop, intent.hand?.rawValue ?? "", intent.oneShot?.id ?? ""].joined(separator: "|")
        return intent
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
        return floorPlan.intent(for: agent, at: slot, pickup: nil, restored: false)
    }
    private func queuedWithFreeSpot(_ id: String) -> Bool {
        guard let slot = slots[id], slot.id.contains("~") else { return false }
        let taken = Set(slots.filter { $0.key != id }.map(\.value.id))
        return (slotTable[slot.area] ?? []).contains { !taken.contains($0.id) }
    }

    /// Reconcile chefs with agents: everyone with work in hand, plus the most recent resters.
    func apply(agents: [SpatialAgent], scope: String? = nil, active: Bool, reducedMotion: Bool, now: Double = CACurrentMediaTime()) {
        // The render thread only sees published chefs, so new chefs are built outside the lock;
        // the lock covers just the short steering steps below (a long hold froze every chef).
        defer { publishChefs() }
        let applyStart = CACurrentMediaTime()
        defer { if CACurrentMediaTime() - applyStart > 0.02 { Self.trace(String(format: "slow apply %.0f ms", (CACurrentMediaTime() - applyStart) * 1000)) } }
        if active != self.active { Self.trace("active -> \(active)") }
        self.active = active; reduced = reducedMotion
        defer { if let scope { seenScopes.insert(scope) } }
        // Attention first, then working, then dishes waiting for review, then anything else
        // that isn't resting; all of them are shown. Resting chefs (rank 3) take the break room's
        // seats, most recently active first.
        func rank(_ agent: SpatialAgent) -> Int {
            if agent.needsAttention { return 0 }
            if agent.value.status == .working || reviews[agent.conversationID] == .reworking { return 1 }
            switch floorPlan.work(for: agent.value, review: reviews[agent.conversationID]).area {
            case "serving": return 2
            case "break": return 3
            default: return 4
            }
        }
        func recency(_ agent: SpatialAgent) -> Date { agent.value.meaningfulUpdatedAt ?? agent.value.observedAt ?? .distantPast }
        // Once its thread is archived the agent leaves the list; an undo brings it straight back.
        let incoming = Set(agents.map(\.id))
        trashed = trashed.filter { now - $0.value < Self.trashedFor && incoming.contains($0.key) }
        let agents = agents.filter { trashed[$0.id] == nil }
        // Typed out in steps: as one chained tuple expression it took seconds to type-check.
        typealias Entry = (rank: Int, offset: Int, agent: SpatialAgent)
        var sorted: [Entry] = []
        for (offset, agent) in agents.enumerated() { sorted.append((rank: rank(agent), offset: offset, agent: agent)) }
        sorted.sort { (a: Entry, b: Entry) -> Bool in a.rank != b.rank ? a.rank < b.rank : a.offset < b.offset }
        let busy = sorted.filter { $0.rank != 3 }
        for entry in sorted {
            if entry.rank != 3 { restingSince[entry.agent.id] = nil }
            else if restingSince[entry.agent.id] == nil, chefs[entry.agent.id] != nil { restingSince[entry.agent.id] = now }
        }
        let listed = Set(agents.map(\.id))
        restingSince = restingSince.filter { listed.contains($0.key) }
        let walking = sorted.filter { $0.rank == 3 && chefs[$0.agent.id] != nil && now - (restingSince[$0.agent.id] ?? -.infinity) < Self.walkOff }
        let walkingIDs = Set(walking.map(\.agent.id))
        var idle: [Entry] = sorted.filter { $0.rank == 3 && !walkingIDs.contains($0.agent.id) }
        idle.sort { (a: Entry, b: Entry) -> Bool in
            let first = recency(a.agent), second = recency(b.agent)
            return first != second ? first > second : a.offset < b.offset
        }
        let resting = walking + idle.prefix(max(0, maxResting - walking.count))
        let ranked = (busy + resting).map(\.agent)
        let ids = Set(ranked.map(\.id))
        for id in chefs.keys where !ids.contains(id) {
            chefLock.lock(); renderChefs.removeAll { $0.id == id }; chefLock.unlock()
            if let director = chefs[id]?.director { departed[id] = (director.position, director.heading) }
            if heldID == id { heldID = nil; hold = nil; holding?(nil) }
            chefs.removeValue(forKey: id)?.root.removeFromParentNode()
            chefLabels.removeValue(forKey: id)?.removeFromSuperview()
            chefAgents[id] = nil; slots[id] = nil; pacing[id] = nil
        }
        guard !ranked.isEmpty, case let .success(assets) = ChefAssets.shared, let world = scene else { updatePlayback(); return }
        assets.preload()
        for agent in ranked {
            chefAgents[agent.id] = agent
            let review = reviews[agent.conversationID]
            if chefs[agent.id] == nil {
                // Its own character: one no other chef in this kitchen wears, while any are left.
                let character = characters.character(for: agent.id, project: agent.projectID ?? agent.conversationID,
                                                     available: assets.characters.map(\.id), inScene: chefs.values.map(\.character))
                let chef = ChefAvatar(id: agent.id, assets: assets, scale: ChefMetrics.chefScale, navigation: navigation, character: character, kit: kit)
                chef.director.reducedMotion = reduced
                chef.dish = theme.deliverable(for: agent.value.completionKey ?? agent.conversationID)
                chefs[agent.id] = chef
                // Only new agents that start while someone watches ride the elevator in: never one
                // this kitchen showed before, nor a conversation you already followed up on.
                let returning = shownChefs.contains(agent.id) || agent.value.latestRequest != nil
                shownChefs.insert(agent.id)
                let arriving = !returning && !catchingUp && seenScopes.contains(agent.projectID ?? agent.conversationID) && [.live, .recentlyObserved].contains(agent.value.freshness)
                if arriving, let door = slotTable["elevator"]?.first, claimSlot(agent.id, area: "order") != nil {
                    // A new agent joins: it rides the elevator in, steps out and waves to you, then
                    // reads its order at the rail. The doors stay open until it gets there.
                    chef.director.place(door.stand, heading: door.facing)
                    chef.director.setIntent(floorPlan.exitIntent(for: agent.id))
                    pacing[agent.id] = Pacing(agent: agent.value, review: review, arriving: true, exiting: true, testsSeen: agent.value.turnWork.tests.count, resourcesSeen: agent.value.turnWork.resources.count, filesSeen: agent.value.turnWork.files.count)
                    openElevator()
                } else if !catchingUp, let spot = departed[agent.id] {
                    // Back in view while you watch: it walks from where it last stood to its work.
                    let area = floorPlan.work(for: agent.value, review: review).area
                    let slot = area.flatMap { claimSlot(agent.id, area: $0) }
                    chef.director.place(spot.position, heading: spot.heading)
                    chef.director.setIntent(floorPlan.intent(for: agent.value, at: slot, pickup: nil, restored: false, review: review))
                    pacing[agent.id] = Pacing(agent: agent.value, review: review, testsSeen: agent.value.turnWork.tests.count, resourcesSeen: agent.value.turnWork.resources.count, filesSeen: agent.value.turnWork.files.count)
                    pacing[agent.id]?.want = chef.director.intent
                } else {
                    // Chefs shown from history start in place: no walk-in, no replayed gesture.
                    let area = floorPlan.work(for: agent.value, review: review).area
                    let slot = area.flatMap { claimSlot(agent.id, area: $0) }
                    let home = slotTable["break"] ?? []
                    if let spawn = slot ?? (home.isEmpty ? nil : home[chefs.count % home.count]) { chef.director.place(spawn.stand, heading: spawn.facing) }
                    chef.director.setIntent(floorPlan.intent(for: agent.value, at: slot, pickup: nil, restored: true, review: review))
                    pacing[agent.id] = Pacing(agent: agent.value, review: review, testsSeen: agent.value.turnWork.tests.count, resourcesSeen: agent.value.turnWork.resources.count, filesSeen: agent.value.turnWork.files.count)
                    pacing[agent.id]?.want = chef.director.intent
                }
                chef.update(0)
                world.rootNode.addChildNode(chef.root)
                let label = ChefTagView(frame: .zero)
                chefLabels[agent.id] = label; addSubview(label)
            } else {
                // Moments since the last look (not while catching up or for history): a reaction.
                if !catchingUp, agent.fresh, let previous = pacing[agent.id]?.agent {
                    let moments = ChefMoment.detect(previous: previous, current: agent.value)
                    if !moments.isEmpty {
                        chefLabels[agent.id]?.react(moments)
                        KitchenLog.record(["event": "emote", "agent": agent.value.name, "conversation": agent.conversationID, "emotes": moments.map(\.rawValue).joined(separator: ",")])
                    }
                }
                chefLock.lock()
                chefs[agent.id]?.director.reducedMotion = reduced
                // One dish per task: a new turn (new completion key) rolls a new one.
                chefs[agent.id]?.dish = theme.deliverable(for: agent.value.completionKey ?? agent.conversationID)
                chefs[agent.id]?.pantryItem = PantryCarry.item(for: agent.value)
                chefs[agent.id]?.prepItem = PantryCarry.planItem(for: agent.value)
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
            // The tag: the chef's name, what it is doing now and how far along it is.
            chefLabels[agent.id]?.update(tagContent(agent, review: review), reducedMotion: reduced)
        }
        seenScopes.formUnion(ranked.map { $0.projectID ?? $0.conversationID })
        noteObservation()
        chefLock.lock(); pace(now: now); chefLock.unlock()
        if catchingUp { catchUp(); logStations("jumped") } else { logStations() }
        updateManager()
        syncSelection()
        updateEffects()
        placeChefLabels()
        updatePlayback()
        needsDisplay = true
    }
    /// Applies wanted intents: urgent ones at once, others after the chef has arrived and worked
    /// at its station for `minimumDwell` (or read its order for `orderReading` after arriving).
    func pace(now: Double) {
        for id in chefs.keys.sorted() {
            guard let chef = chefs[id], chef.held == nil, var state = pacing[id] else { continue }
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
                    if director.station != nil, settledFor >= ChefMetrics.minimumDwell { state.owed.removeFirst() }
                    pacing[id] = state; continue
                } else if !walking, director.intent?.station == nil || settledFor >= ChefMetrics.minimumDwell, let next = owedIntent(id, area: owedArea) {
                    director.setIntent(next)
                    state.arrivedAt = nil
                    pacing[id] = state; continue
                } else { pacing[id] = state; continue }
            }
            if state.arriving, state.exiting {
                // Out of the elevator and waved: on to the order rail.
                if director.station?.id == floorPlan.elevatorLanding.id, settledFor >= ChefMetrics.arrivalWave,
                   let order = slots[id], order.area == "order" {
                    director.setIntent(floorPlan.arrivalIntent(at: order))
                    state.exiting = false; state.arrivedAt = nil
                }
                pacing[id] = state; continue
            }
            if state.arriving {
                apply = state.arrivedAt != nil && settledFor >= ChefMetrics.orderReading
                if apply { state.arriving = false }
            } else if let want = state.want, want.key != director.intent?.key {
                // Urgent changes apply at once. Otherwise a walking chef finishes its trip (agents
                // switch tools several times a second; re-routing mid-walk made chefs stop, turn
                // and restart) and then works at least the minimum dwell before moving on.
                apply = want.urgent || director.intent?.station == nil || (!walking && settledFor >= ChefMetrics.minimumDwell)
            } else if !walking, settledFor >= ChefMetrics.minimumDwell, queuedWithFreeSpot(id) {
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
    /// Station details follow the chefs at them (flames under a command, boards in use).
    func updateEffects() {
        guard !effects.isEmpty else { return }
        chefLock.lock()
        let snapshot = chefs.values.map { chef in
            ChefSnapshot(station: chef.director.station, clip: chef.director.clip.name, position: chef.director.position, choppingOnBoard: chef.choppingOnBoard)
        }
        chefLock.unlock()
        for effect in effects { effect.update(snapshot, reduced: reduced) }
    }
    func updateFlames() { updateEffects() }
    func updateBoards() { updateEffects() }
    var litBurners: Set<String> { effects.lazy.compactMap { ($0 as? BurnerFlames)?.lit }.first ?? [] }
    var idleBoards: Set<String> { effects.lazy.compactMap { ($0 as? IdleBoards)?.idle }.first ?? [] }
    private var pacingPending: Bool {
        pacing.contains { id, state in state.arriving || (state.want != nil && state.want?.key != chefs[id]?.director.intent?.key) || slots[id]?.id.contains("~") == true }
    }
    /// Whether the elevator doors are open (for a chef on its way from them to the rail).
    private(set) var elevatorOpen = false
    private func openElevator() { moveElevatorDoors(open: true) }
    /// Opens or closes the doors; they stay as they are until told otherwise.
    private func moveElevatorDoors(open: Bool) {
        guard open != elevatorOpen, let car = scene?.rootNode.childNode(withName: "elevator", recursively: false) else { return }
        elevatorOpen = open
        let width = CGFloat(floorPlan.areas.first { $0.id == "elevator" }?.footprint.width ?? 2.4)
        for (name, direction) in [("elevator door left", -1.0), ("elevator door right", 1.0)] {
            guard let door = car.childNode(withName: name, recursively: false) else { continue }
            let slide = CGFloat(direction) * (width / 2 - 0.2)
            // Slides from wherever it is (it may be mid-move) to open or shut.
            let closed = doorClosedX[name] ?? CGFloat(door.position.x)
            doorClosedX[name] = closed
            door.removeAction(forKey: "doors")
            door.runAction(.move(to: SCNVector3(closed + (open ? slide : 0), CGFloat(door.position.y), CGFloat(door.position.z)), duration: 0.6), forKey: "doors")
        }
    }
    /// Each door's closed position, recorded the first time it moves.
    private var doorClosedX: [String: CGFloat] = [:]
    /// The doors close once every arriving chef has reached the order rail.
    private func updateElevatorDoors() {
        guard elevatorOpen else { return }
        chefLock.lock()
        let coming = pacing.values.contains { $0.arriving && ($0.exiting || $0.arrivedAt == nil) }
        chefLock.unlock()
        if !coming { moveElevatorDoors(open: false) }
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
        updateManager()
        updateGong()
        updateBreakRoom(now: CACurrentMediaTime())
        serveDiners(now: CACurrentMediaTime())
        logStations()
        updateEffects()
        updateElevatorDoors()
        noticeSilence()
        refreshLabels()
        placeChefLabels()
        placeBubbles(now: CACurrentMediaTime())
        updatePlayback()
    }
    private func tagContent(_ agent: SpatialAgent, review: KitchenReviews.State?, now: Date = Date()) -> ChefTagContent {
        // Only finished work counts its files (a git read): working chefs have no use for it.
        let finished = agent.value.status == .done || review != nil
        return ChefTagContent.make(agent, review: review, note: KitchenReviews.shared.note(agent.conversationID),
                                   checks: KitchenReviews.shared.checks(agent.conversationID), files: finished ? changedFiles?(agent) : nil,
                                   model: modelName?(agent) ?? "", now: now)
    }
    /// Written task labels and changed-file counts arrive after a chef appears; swap them into the tags.
    private func refreshLabels() {
        guard TaskLabels.shared.revision != labelRevision || SessionChangeCounts.shared.revision != changeRevision else { return }
        labelRevision = TaskLabels.shared.revision; changeRevision = SessionChangeCounts.shared.revision
        for (id, agent) in chefAgents { chefLabels[id]?.update(tagContent(agent, review: pacing[id]?.review), reducedMotion: reduced) }
    }
    /// Once a second, working tags catch up with the clock: a quiet agent turns to thinking,
    /// and the thinking and elapsed times count up.
    private func noticeSilence(now: Date = Date()) {
        let time = CACurrentMediaTime()
        guard time - lastSilenceCheck >= 1, !catchingUp else { return }
        lastSilenceCheck = time
        for (id, agent) in chefAgents where agent.fresh && agent.value.status == .working {
            chefLabels[id]?.update(tagContent(agent, review: pacing[id]?.review, now: now), reducedMotion: reduced)
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
            guard let chef = chefs[id], chef.held == nil, var state = pacing[id] else { continue }
            let director = chef.director
            state.arriving = false; state.exiting = false; state.owed = []; pacing[id] = state
            let walking = director.intent?.station != nil && director.station == nil
            guard walking || state.want?.key != director.intent?.key || queuedWithFreeSpot(id) else { continue }
            if queuedWithFreeSpot(id) { slots[id] = nil }
            guard let next = wanted(id, claim: true, restored: true) else { continue }
            if let station = next.station { director.place(station.stand, heading: station.facing) }
            director.setIntent(next, force: true)
            state.want = wanted(id, claim: false)
            state.arrivedAt = now - ChefMetrics.minimumDwell
            pacing[id] = state
        }
    }
    func updatePlayback() {
        noteObservation()
        // Only chef state is read under the lock: SceneKit playback setters can wait on the
        // renderer, which may itself be waiting for the lock in renderer(_:updateAtTime:).
        chefLock.lock()
        // The restaurant's guests keep chatting and eating whenever the kitchen is on screen.
        let animating = chefs.values.contains(where: \.animating) || diners.contains(where: \.animating) || manager?.animating == true || pacingPending || cameraMoving || !freeCamera.held.isEmpty
        chefLock.unlock()
        let moving = effectiveActive && animating
        let audibleFrom = window != nil && effectiveActive ? observedSince.map { $0 + Self.catchUpWindow } : nil
        chefLock.lock(); soundsFrom = audibleFrom; chefLock.unlock()
        if isPlaying != moving { isPlaying = moving }
        if rendersContinuously != moving { rendersContinuously = moving }
        if moving, motionActivity == nil {
            motionActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Animating the kitchen")
        } else if !moving, let activity = motionActivity {
            ProcessInfo.processInfo.endActivity(activity); motionActivity = nil
        }
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
        let driver = SceneFrameDriver(); driver.view = self; frameDriver = driver
        let link = displayLink(target: driver, selector: #selector(SceneFrameDriver.frame(_:)))
        link.add(to: .main, forMode: .common); frameLink = link
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlayback() }
        })
        // Keys held when the window loses focus would otherwise keep the camera moving.
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.freeCamera.releaseAll(); if self?.heldID != nil { self?.drop(cancelled: true) } }
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
    /// Select a chef (nil clears it): ring it, follow it, and recede the other name tags. Clearing
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
        let size = CGFloat(1.75 * ChefMetrics.chefScale)
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.diffuse.contents = selectionRingImage
        material.lightingModel = .constant; material.blendMode = .add
        material.writesToDepthBuffer = false; material.isDoubleSided = true
        plane.materials = [material]
        let disc = SCNNode(geometry: plane); disc.name = "selection ring disc"
        disc.eulerAngles.x = -.pi / 2
        disc.position.y = CGFloat(ChefMetrics.floorTop) + 0.012
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
    /// Where a chef stands in window coordinates (origin bottom-left), about knee high (below its name tag): the
    /// development demo picks chefs up from here.
    func windowPoint(ofAgent id: String) -> CGPoint? {
        chefLock.lock(); let position = chefs[id]?.root.simdWorldPosition; chefLock.unlock()
        guard let position, let point = projectWithoutLock(position + SIMD3(0, 0.45, 0)) else { return nil }
        return convert(point, to: nil)
    }
    /// Projects a world point to view coordinates (origin bottom-left, like `projectPoint`) with
    /// the camera's matrices. `projectPoint` takes SceneKit's scene lock and waits for the
    /// renderer, which stalled every animation frame when used for per-frame name tags.
    func projectWithoutLock(_ point: SIMD3<Float>) -> CGPoint? {
        guard let eye = pointOfView, let camera = eye.camera, bounds.width > 0, bounds.height > 0 else { return nil }
        let projection = simd_float4x4(camera.projectionTransform(withViewportSize: bounds.size))
        // Spelled out step by step: the release compiler can't infer the chained product.
        let view: simd_float4x4 = eye.simdWorldTransform.inverse
        let world = SIMD4<Float>(point.x, point.y, point.z, 1)
        let clip: SIMD4<Float> = projection * (view * world)
        guard clip.w > 0.0001 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return CGPoint(x: CGFloat(ndc.x + 1) / 2 * bounds.width, y: CGFloat(ndc.y + 1) / 2 * bounds.height)
    }
    /// Name tags hidden with the A key (all kitchens, until pressed again).
    static var tagsHidden = false
    private func placeChefLabels() {
        var placed: [CGRect] = []
        chefLock.lock()
        let positions = chefs.mapValues(\.root.simdPosition)
        chefLock.unlock()
        // The most important tags are placed first and keep their spot: needing you, the
        // selected chef, working, done, idle.
        func priority(_ id: String) -> Int {
            guard let phase = chefLabels[id]?.content?.phase else { return 5 }
            if phase.needsYou { return 0 }
            return id == selectedID ? 1 : phase.priority
        }
        let order = positions.keys.map { (id: $0, priority: priority($0)) }
            .sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.id < $1.id }
        func clashes(_ frame: CGRect) -> CGRect? { placed.first { $0.insetBy(dx: -2, dy: -1).intersects(frame) } }
        for id in order.map(\.id) {
            guard let label = chefLabels[id], let position = positions[id] else { continue }
            if heldID == id || Self.tagsHidden { label.isHidden = true; continue }
            let selected = selectedID == id, hovered = hoveredID == id
            // Resting chefs show their tag on hover.
            if selectedID == nil, label.content?.resting == true, !hovered { label.isHidden = true; continue }
            let head = position + SIMD3(0, 2.05 * ChefMetrics.chefScale, 0)
            // A chef out of frame (the camera follows another) takes its tag with it, rather than
            // leaving it pinned to the edge.
            guard let point = projectWithoutLock(head), bounds.insetBy(dx: -24, dy: -24).contains(point) else { label.isHidden = true; continue }
            label.isHidden = false
            // While another chef is selected the rest recede, except those that need you.
            var mode: ChefTagView.Mode = selectedID != nil && !selected && label.content?.phase.needsYou != true ? .compact : .full
            var frame = tagFrame(label.size(mode, selected: selected, hovered: hovered), at: point, above: true)
            // Crowded out by a more important tag: shrink and step down below the chef's feet.
            if clashes(frame) != nil, !selected, !hovered, let feet = projectWithoutLock(position) {
                mode = .compact
                frame = tagFrame(label.size(mode, selected: false, hovered: false), at: feet, above: false)
            }
            let start = frame.midY
            while let clash = clashes(frame) {
                frame.origin.y = isFlipped ? clash.maxY + 2 : clash.minY - frame.height - 2
            }
            // In a crowd (seven chefs at the pass) a tag pushed this far would float over another
            // part of the room; it shows on hover or selection instead, and the sidebar lists it.
            if !selected, !hovered, abs(frame.midY - start) > frame.height * 3 { label.isHidden = true; continue }
            placed.append(frame)
            label.present(mode, selected: selected, hovered: hovered)
            label.frame = frame
        }
    }
    /// A tag's frame: its bottom edge at a head, or its top edge at a chef's feet, kept inside
    /// the view near the walls.
    private func tagFrame(_ size: NSSize, at point: CGPoint, above: Bool) -> CGRect {
        let y = isFlipped ? bounds.height - point.y : point.y
        let x = min(max(4, point.x - size.width / 2), max(4, bounds.width - size.width - 4))
        let origin = isFlipped ? (above ? y - size.height : y) : (above ? y : y - size.height)
        return CGRect(x: x, y: min(max(4, origin), max(4, bounds.height - size.height - 4)), width: size.width, height: size.height)
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
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: ~Self.dinerCategory]) {
            if let node = sequence(first: hit.node, next: \.parent).first(where: { $0.name?.hasPrefix("agent:") == true }) { found = String(node.name!.dropFirst(6)); break }
        }
        if found != hoveredID { hoveredID = found; placeChefLabels() }
    }
    override func mouseExited(with event: NSEvent) { if hoveredID != nil { hoveredID = nil; placeChefLabels() } }
    override func mouseUp(with event: NSEvent) {
        press?.timer.invalidate(); press = nil
        if heldID != nil { drop(); return }
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
        let half = SIMD2(Float(floorPlan.floor.width / 2), Float(floorPlan.floor.height / 2))
        for x in signs { for y in signs { for z in signs { result.append(SCNVector3(x * half.x, y * 0.1, z * half.y)) } } }
        return result
    }
    var framingPoints: [SCNVector3] {
        var points: [SCNVector3] = []
        for name in floorPlan.areas.map(\.id) {
            guard let station = scene?.rootNode.childNode(withName: name, recursively: false) else { continue }
            // The break room spreads tall machines along its back and low chairs at its front: frame
            // each piece, not one box whose corners would pair the machines' height with the front.
            for node in name == "break" ? station.childNodes : [station] {
                let (low, high) = node.boundingBox
                for x in [low.x, high.x] { for y in [low.y, high.y] { for z in [low.z, high.z] {
                    points.append(node.convertPosition(SCNVector3(x, y, z), to: nil))
                } } }
            }
        }
        return points
    }
    func fitFloor() {
        guard bounds.width > 1, bounds.height > 1, let camera = pointOfView else { return }
        guard fittedSize != bounds.size else { placeLabels(); return }
        fittedSize = bounds.size
        var points = framingPoints
        // In a wide window the restaurant's tables on both sides stay in the home view too (with
        // the camera this low they'd fall just off the edges).
        if bounds.width / bounds.height >= 1.5, let restaurant = theme.surroundings {
            points += restaurant.seats.map { SCNVector3($0.dish.x, $0.dish.y, $0.dish.z) }
        }
        let elevation = Double(KitchenCameraController.elevationDegrees) * Double.pi / 180
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
        for (index, area) in floorPlan.areas.enumerated() {
            // Lock-free, like the name tags: `projectPoint` waits for the renderer, and the signs are
            // placed on every agent update.
            // The break room's sign stands over its rug, not its little side table.
            let spot = area.id == "break" ? floorPlan.restSign : area.footprint
            guard let point = projectWithoutLock(SIMD3(Float(spot.midX), 2.6, Float(spot.minY))) else { continue }
            let anchor = CGPoint(x: point.x, y: isFlipped ? bounds.height - point.y : point.y)
            let width: CGFloat = min(150, ceil(labels[index].attributedStringValue.size().width) + 18)
            let height = KitchenLabel.height
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

extension DioramaSceneView: SCNSceneRendererDelegate {
    /// Plays the sounds chefs cued this frame, panned to where each stands on screen and quieter
    /// for chefs out of frame. Render thread, under `chefLock`.
    nonisolated private func playSounds(_ renderer: any SCNSceneRenderer, at now: Double) {
        let audible = soundsFrom.map { now >= $0 } ?? false
        for chef in renderChefs where !chef.heard.isEmpty {
            let sounds = chef.heard; chef.heard = []
            let spot = chef.director.position
            let resting = chef.director.station?.area == "break" || quietArea.contains(CGPoint(x: CGFloat(spot.x), y: CGFloat(spot.y)))
            guard audible, soundWidth > 0, !resting else { continue }
            let point = renderer.projectPoint(SCNVector3(chef.root.simdWorldPosition))
            let x = Float(CGFloat(point.x) / soundWidth)
            let inFrame = x >= 0 && x <= 1 && point.z < 1
            for sound in sounds { KitchenAudio.shared.play(sound, pan: x * 2 - 1, level: inFrame ? 1 : 0.35, folder: soundFolder) }
        }
    }

    /// Runs on SceneKit's render thread every rendered frame, independent of main-thread work.
    nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        chefLock.lock(); defer { chefLock.unlock() }
        if let last = lastRenderTime, time - last > 0.05 { Self.trace(String(format: "render gap %.0f ms", (time - last) * 1000)) }
        let delta = lastRenderTime.map { Float(min(0.1, max(0, time - $0))) } ?? 0
        lastRenderTime = time
        for chef in renderChefs { chef.update(delta) }
        playSounds(renderer, at: CACurrentMediaTime())
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

/// A chef in the pointer's grip, as the kitchen's overlays need it.
struct KitchenHold: Equatable {
    var name: String
    /// Why the trash won't take it, or nil.
    var blocker: String?
    var overTrash = false
}

// MARK: Picking chefs up

extension DioramaSceneView {
    /// The chef under a view point, if any.
    private func chefID(at point: CGPoint) -> String? {
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: ~Self.dinerCategory]) {
            if let node = sequence(first: hit.node, next: \.parent).first(where: { $0.name?.hasPrefix("agent:") == true }) { return String(node.name!.dropFirst(6)) }
        }
        return nil
    }
    override func mouseDown(with event: NSEvent) {
        press?.timer.invalidate(); press = nil
        let point = convert(event.locationInWindow, from: nil)
        guard holding != nil, heldID == nil, window?.attachedSheet == nil,
              !chefLabels.values.contains(where: { !$0.isHidden && $0.frame.contains(point) }),
              let id = chefID(at: point), chefs[id] != nil else { super.mouseDown(with: event); return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.pickUp() }
        }
        press = (id, point, timer)
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if heldID == nil, let press, hypot(point.x - press.at.x, point.y - press.at.y) > 4 { pickUp() }
        if heldID != nil { carry(to: event.locationInWindow) }
        else { super.mouseDragged(with: event) }
    }

    /// The development demo's drag, through the same pick-up, carry and drop as the mouse.
    func demoPickUp(_ id: String, at windowPoint: CGPoint) {
        guard chefs[id] != nil else { return }
        press = (id, convert(windowPoint, from: nil), Timer())
        pickUp(at: windowPoint)
    }
    func demoCarry(to windowPoint: CGPoint) { carry(to: windowPoint) }
    func demoDrop() { if heldID != nil { drop() } }

    /// Lifts the pressed chef: it squirms in the grip, its tags hide, and the overlays give way to the trash.
    private func pickUp(at windowPoint: CGPoint? = nil) {
        guard let press, let chef = chefs[press.id], let agent = chefAgents[press.id] else { self.press = nil; return }
        press.timer.invalidate(); self.press = nil
        heldID = press.id
        let window = windowPoint ?? self.window?.mouseLocationOutsideOfEventStream ?? convert(press.at, to: nil)
        chefLock.lock()
        let start = chef.director.position
        chef.held = ChefAvatar.Hold(target: grabPoint(window) ?? start, point: start)
        chefLock.unlock()
        hoveredID = nil
        hold = KitchenHold(name: agent.value.name, blocker: archiveBlocker?(agent))
        holding?(hold)
        placeChefLabels()
        KitchenAudio.shared.play(.grab, pan: Float(press.at.x / max(1, bounds.width)) * 2 - 1, folder: soundFolder)
        updatePlayback()
        carry(to: window)
    }
    private func carry(to windowPoint: CGPoint) {
        guard let id = heldID, let chef = chefs[id] else { return }
        if let target = grabPoint(windowPoint) { chefLock.lock(); chef.held?.target = target; chefLock.unlock() }
        let over = overTrash(windowPoint)
        if hold?.overTrash != over { hold?.overTrash = over; holding?(hold) }
    }
    /// Over the trash can: SwiftUI reports its frame in window coordinates with a top-left origin.
    private func overTrash(_ windowPoint: CGPoint) -> Bool {
        guard trashFrame.width > 0, let height = window?.contentView?.bounds.height else { return false }
        return trashFrame.insetBy(dx: -16, dy: -16).contains(CGPoint(x: windowPoint.x, y: height - windowPoint.y))
    }

    /// Puts the held chef down: into the trash (archiving its thread) when it may go there,
    /// otherwise on the nearest free floor, from where it walks back to its work.
    func drop(cancelled: Bool = false) {
        guard let id = heldID, let chef = chefs[id] else { heldID = nil; hold = nil; holding?(nil); return }
        let agent = chefAgents[id]
        let binned = !cancelled && hold?.overTrash == true && hold?.blocker == nil && agent != nil && archive != nil
        heldID = nil; hold = nil
        holding?(nil)
        chefLock.lock(); let spot = chef.held?.point ?? chef.director.position; chefLock.unlock()
        let pan = projectWithoutLock(SIMD3(spot.x, 0, spot.y)).map { Float($0.x / max(1, bounds.width)) * 2 - 1 } ?? 0
        if binned, let agent {
            chefLock.lock(); chef.held?.trashing = 0; chefLock.unlock()
            KitchenAudio.shared.play(.clatter, pan: 1, folder: soundFolder)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
                guard let self else { return }
                self.trashed[id] = CACurrentMediaTime()
                self.archive?(agent)
                self.apply(agents: Array(self.chefAgents.values), active: self.active, reducedMotion: self.reduced)
            }
        } else {
            let floor = freeFloor(near: insideWalls(spot))
            chefLock.lock(); chef.release(at: floor); chefLock.unlock()
            KitchenAudio.shared.play(.plate, pan: pan, level: 0.7, folder: soundFolder)
            pacing[id]?.arrivedAt = nil
        }
        placeChefLabels()
        updatePlayback()
    }

    /// Where the held chef's root goes for a pointer position: the chef hangs from the pointer,
    /// so the ray meets the plane at its lifted head height. Held in the air it isn't kept inside
    /// the walls, so it reaches the trash in the corner; it lands back inside when put down.
    /// Lock-free, like `projectWithoutLock`.
    func grabPoint(_ windowPoint: CGPoint) -> SIMD2<Float>? {
        let point = convert(windowPoint, from: nil)
        let height = (ChefAvatar.liftHeight + 1.7) * ChefMetrics.chefScale
        guard let hit = floorRay(point, planeY: height) else { return nil }
        let reach = SIMD2(Float(floorPlan.floor.width), Float(floorPlan.floor.height)) * 2
        return simd_clamp(hit, -reach, reach)
    }
    /// The floor inside the walls nearest a point.
    func insideWalls(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let half = SIMD2(Float(floorPlan.floor.width / 2), Float(floorPlan.floor.height / 2)) - 0.3
        return simd_clamp(point, -half, half)
    }
    /// Where a view point's ray crosses the horizontal plane at `planeY` (world x, z).
    func floorRay(_ point: CGPoint, planeY: Float) -> SIMD2<Float>? {
        guard let eye = pointOfView, let camera = eye.camera, bounds.width > 0, bounds.height > 0 else { return nil }
        let projection = simd_float4x4(camera.projectionTransform(withViewportSize: bounds.size))
        let inverse = (projection * eye.simdWorldTransform.inverse).inverse
        let ndc = SIMD2(Float(point.x / bounds.width) * 2 - 1, Float(point.y / bounds.height) * 2 - 1)
        func world(_ z: Float) -> SIMD3<Float>? {
            let value = inverse * SIMD4(ndc.x, ndc.y, z, 1)
            guard abs(value.w) > 0.000001 else { return nil }
            return SIMD3(value.x, value.y, value.z) / value.w
        }
        guard let near = world(0), let far = world(0.5) else { return nil }
        let direction = far - near
        guard abs(direction.y) > 0.00001 else { return nil }
        let t = (planeY - near.y) / direction.y
        guard t > 0 else { return nil }
        let hit = near + direction * t
        return SIMD2(hit.x, hit.z)
    }
    /// The free floor point nearest `point` (counters and walls are not floor).
    func freeFloor(near point: SIMD2<Float>) -> SIMD2<Float> {
        if navigation.isFree(point) { return point }
        for ring in 1...24 {
            let r = Float(ring) * 0.25
            for step in 0..<(ring * 8) {
                let angle = Float(step) / Float(ring * 8) * 2 * .pi
                let candidate = point + SIMD2(cos(angle), sin(angle)) * r
                if navigation.isFree(candidate) { return candidate }
            }
        }
        return point
    }
}

// MARK: Diners

extension DioramaSceneView {
    /// Seats the restaurant's guests at the tables along both sides of the kitchen, each with a
    /// plate of food, and sets them chatting.
    private func seatDiners(_ restaurant: any SceneSurroundings, in world: SCNScene) {
        guard case let .success(assets) = ChefAssets.shared else { return }
        let seats = Array(restaurant.seats.prefix(Self.dinerCount))
        let cast = RestaurantGuests.cast(assets.guests.map(\.id), seats: seats.map(\.dish))
        guests = RestaurantGuests(positions: seats.map(\.dish), durations: assets.manifest.clips.mapValues { Double($0.duration) }, script: theme.guestScript)
        let settings = theme.tableSettings, foods = settings.keys.sorted()
        for (index, seat) in seats.enumerated() {
            let character = cast.indices.contains(index) ? cast[index] : ChefAssets.classic
            let diner = ChefAvatar(id: "diner-" + seat.id, assets: assets, scale: ChefMetrics.chefScale, navigation: floorPlan.chefNavigation, character: character, kit: kit)
            diner.root.name = "diner:" + seat.id
            diner.silent = true
            // Seen and lit like everything else, but never picked instead of a chef behind them.
            diner.root.enumerateHierarchy { node, _ in node.categoryBitMask = Self.dinerCategory }
            diner.director.place(seat.stand, heading: seat.facing)
            diner.director.setIntent(dinerIntent(seat: seat, clip: guests.seats[index].clip))
            diner.update(0)
            world.rootNode.addChildNode(diner.root)
            diners.append(diner)
            // Every table has food on it; a served dish takes its place for a while.
            if !foods.isEmpty, let template = settings[foods[(index * 7 + 3) % foods.count]] {
                let plate = template.clone()
                plate.simdScale = SIMD3(repeating: ChefAvatar.dishSize * ChefMetrics.chefScale * 0.62)
                plate.simdPosition = seat.dish + SIMD3(0, 0.005, 0)
                world.rootNode.addChildNode(plate)
                tablePlates.append(plate)
            } else {
                tablePlates.append(nil)
            }
        }
    }
    /// Restaurant guests' category: lit and drawn as usual, left out of chef picking.
    static let dinerCategory = 1 << 4
    private func dinerIntent(seat: SceneSeat, clip: String) -> ChefIntent {
        let station = ChefStation(id: "dining-" + seat.id, area: "dining", stand: seat.stand, facing: seat.facing)
        let script = guests.script
        let hand: ChefProp? = clip == script.enjoy ? script.enjoyHand : clip == "sit_sip" ? .mug : nil
        if clip == script.cheer {
            return ChefIntent(key: ["dining", seat.id, clip, String(cheers)].joined(separator: "|"), station: station, loop: script.enjoy,
                              oneShot: .init(id: "cheer-\(seat.id)-\(cheers)", clip: clip, restored: false), hand: nil)
        }
        return ChefIntent(key: ["dining", seat.id, clip].joined(separator: "|"), station: station, loop: clip, hand: hand)
    }
    /// Moves the guests on: each switches what it's doing on its own clock.
    private func updateGuests(now: Double) {
        guard let restaurant = theme.surroundings, !diners.isEmpty else { return }
        let changed = guests.update(now: now)
        guard !changed.isEmpty else { return }
        chefLock.lock()
        for seat in changed where diners.indices.contains(seat) && restaurant.seats.indices.contains(seat) {
            diners[seat].director.setIntent(dinerIntent(seat: restaurant.seats[seat], clip: guests.seats[seat].clip))
        }
        chefLock.unlock()
    }
    /// Seated diners currently being served, by conversation (for tests).
    var servedSeats: [String: Int] { served.mapValues(\.seat) }

    /// A chef who sets a finished task's dish on the pass serves it to the nearest free diner:
    /// the same dish lands on their table and they light up. Once the work is accepted (or the
    /// task leaves the kitchen) they finish eating and the table clears.
    func serveDiners(now: Double) {
        guard let restaurant = theme.surroundings, !diners.isEmpty else { return }
        chefLock.lock()
        var plated: [String: String] = [:] // conversation -> dish id
        for (id, chef) in chefs where chef.director.placedPlate != nil {
            if let agent = chefAgents[id], agent.value.isMain { plated[agent.conversationID] = chef.dish ?? "" }
        }
        chefLock.unlock()
        for (conversation, dishID) in plated.sorted(by: { $0.key < $1.key }) where served[conversation] == nil || served[conversation]?.leftAt != nil {
            if let back = served[conversation], back.leftAt != nil { served[conversation]?.leftAt = nil; continue }
            let taken = Set(served.values.map(\.seat))
            guard let seat = diners.indices.first(where: { !taken.contains($0) }), seat < restaurant.seats.count else { break }
            let spot = restaurant.seats[seat]
            var plate: SCNNode?
            if let template = kit.deliverables[dishID] {
                let node = template.clone(); node.simdScale = SIMD3(repeating: ChefAvatar.dishSize * ChefMetrics.chefScale * 0.62)
                node.simdPosition = spot.dish + SIMD3(0, 0.005, 0)
                scene?.rootNode.addChildNode(node); plate = node
            }
            served[conversation] = (seat, plate, nil)
            if plate != nil, tablePlates.indices.contains(seat) { tablePlates[seat]?.isHidden = true }
            guests.serve(seat, now: now); cheers += 1
            chefLock.lock(); diners[seat].director.setIntent(dinerIntent(seat: spot, clip: guests.script.cheer)); chefLock.unlock()
            if let point = projectWithoutLock(spot.dish) {
                KitchenAudio.shared.play(.clink, pan: Float(point.x / max(1, bounds.width)) * 2 - 1, level: 0.8, folder: soundFolder)
            }
        }
        for (conversation, entry) in served where plated[conversation] == nil {
            guard let left = entry.leftAt else { served[conversation]?.leftAt = now; continue }
            guard now - left > Self.dinerLinger else { continue }
            entry.dish?.removeFromParentNode()
            if tablePlates.indices.contains(entry.seat) { tablePlates[entry.seat]?.isHidden = false }
            served[conversation] = nil
        }
        updateGuests(now: now)
    }
}

// MARK: Gong and manager

extension DioramaSceneView {
    /// Chefs waiting in front of the gong for you: arrived at their spot (or the one being visited,
    /// which turns in place to talk), longest first.
    private var gongWaiting: [KitchenManager.Waiting] {
        chefs.compactMap { id, chef in
            guard chef.held == nil, let state = pacing[id], state.want?.station?.area == "bell" else { return nil }
            let arrived = chef.director.station?.area == "bell"
            let visited = id == managerVisit?.id && chef.director.intent?.station?.area == "bell"
            guard arrived || visited else { return nil }
            return KitchenManager.Waiting(id: id, since: state.arrivedAt ?? 0)
        }
    }

    /// The manager comes in from the dining room when a chef waits at the gong, walks over and
    /// talks with it until you answer, then visits the next waiting chef or walks back out.
    func updateManager() {
        guard case let .success(assets) = ChefAssets.shared, let world = scene,
              assets.staff.contains(where: { $0.id == ChefAssets.manager }) else { return }
        chefLock.lock(); defer { chefLock.unlock() }
        let waiting = gongWaiting
        let target = KitchenManager.next(current: managerVisit?.id, waiting: waiting)
        // Where the chef is headed, not where it is: it strikes the gong first, then steps to its
        // waiting spot, and the manager must stand clear of that.
        if let target, let chef = chefs[target], let stand = (chef.director.intent?.station ?? chef.director.station)?.stand {
            let manager = self.manager ?? enterManager(assets, in: world)
            managerLeaving = false
            if managerVisit?.id != target || managerVisit.map({ simd_distance($0.spot.stand, stand) < 1.0 }) == true {
                stopTalking()
                let others = waiting.compactMap { $0.id == target ? nil : chefs[$0.id]?.director.station?.stand } + [floorPlan.gongStrike.stand]
                let spot = floorPlan.managerSpot(talkingTo: stand, others: others)
                managerVisit = (target, spot)
                if catchingUp { manager.director.place(spot.stand, heading: spot.facing) }
                manager.director.setIntent(ChefIntent(key: "manager|\(target)", station: spot, loop: "manager_talk", urgent: true))
            }
            if managerTalking != target, manager.director.station?.id == managerVisit?.spot.id {
                managerTalking = target
                let want = wanted(target, claim: false)
                pacing[target]?.want = want
            }
        } else if let manager {
            stopTalking()
            managerVisit = nil
            if !managerLeaving {
                managerLeaving = true
                manager.director.setIntent(ChefIntent(key: "manager|leave", station: floorPlan.managerDoor, loop: "idle_available", urgent: true))
            } else if manager.director.station?.id == floorPlan.managerDoor.id || catchingUp {
                // Back through to the dining room.
                self.manager = nil; managerLeaving = false
                manager.root.runAction(.sequence([.fadeOut(duration: catchingUp ? 0 : 0.35), .removeFromParentNode()]))
                DispatchQueue.main.async { [weak self] in self?.publishChefs() }
            }
        }
    }

    private func enterManager(_ assets: ChefAssets, in world: SCNScene) -> ChefAvatar {
        let manager = ChefAvatar(id: "manager", assets: assets, scale: ChefMetrics.chefScale, navigation: floorPlan.chefNavigation,
                                 character: ChefAssets.manager)
        manager.root.name = "staff:manager"
        // Seen and lit like everything else, but never picked instead of a chef behind it.
        manager.root.enumerateHierarchy { node, _ in node.categoryBitMask = Self.dinerCategory }
        manager.director.strolls = true
        manager.director.reducedMotion = reduced
        let door = floorPlan.managerDoor
        manager.director.place(door.stand, heading: door.facing)
        manager.update(0)
        manager.root.opacity = catchingUp ? 1 : 0
        world.rootNode.addChildNode(manager.root)
        if !catchingUp { manager.root.runAction(.fadeIn(duration: 0.35)) }
        self.manager = manager
        DispatchQueue.main.async { [weak self] in self?.publishChefs() }
        return manager
    }

    /// The chef the manager was talking with turns back to the gong (or goes about its work).
    private func stopTalking() {
        guard let talking = managerTalking else { return }
        managerTalking = nil
        if pacing[talking] != nil { let want = wanted(talking, claim: false); pacing[talking]?.want = want }
    }

    /// Sets the gong shivering each time a chef's mallet lands on it; a scene whose chefs don't
    /// strike it (the office's desk bell) rings as each one arrives.
    func updateGong() {
        let fixture = scene?.rootNode.childNode(withName: "bell", recursively: false)
        guard floorPlan.dressing.strikesNeedsYou else {
            chefLock.lock()
            let here = Set(chefs.compactMap { $0.value.director.station?.area == "bell" ? $0.key : nil })
            let position = chefs.first { here.contains($0.key) && !atBell.contains($0.key) }?.value.root.simdPosition
            chefLock.unlock()
            defer { atBell = here }
            guard !here.subtracting(atBell).isEmpty, !catchingUp, let fixture else { return }
            if !reduced { theme.ringNeedsYou(fixture) }
            let pan = position.flatMap { projectWithoutLock($0) }.map { Float($0.x / max(1, bounds.width)) * 2 - 1 } ?? 0
            KitchenAudio.shared.play(.gong, pan: pan, folder: soundFolder)
            return
        }
        chefLock.lock()
        let strikes = chefs.values.reduce(0) { $0 + $1.director.gongStrikes }
        chefLock.unlock()
        defer { gongStrikesSeen = strikes }
        guard strikes > gongStrikesSeen, !reduced, let fixture else { return }
        theme.ringNeedsYou(fixture)
    }
}

// MARK: Break room

extension DioramaSceneView {
    /// Moves the break room on: newcomers take spots, turns at the machines, who talks and who
    /// laughs. Chefs whose spot or clip changed get their new intent; some get an emoji bubble.
    func updateBreakRoom(now: Double) {
        breakClock = now
        chefLock.lock()
        let resting = pacing.compactMap { id, state in
            chefs[id] != nil && floorPlan.work(for: state.agent, review: state.review).area == "break" ? id : nil
        }
        let before = breakRoom.members
        let changed = breakRoom.update(resting: resting, now: now)
        for id in changed where pacing[id] != nil {
            let want = wanted(id, claim: true)
            pacing[id]?.want = want
        }
        // What shows in a bubble: arriving at a machine, starting to talk or laugh, an arcade win.
        var said: [(String, [String])] = []
        for id in changed.sorted() {
            guard let member = breakRoom.members[id], let kind = breakRoom.kind(of: id) else { continue }
            let moved = before[id]?.spot != member.spot
            switch kind {
            case .arcade where moved: said.append((id, ["🎮", "🕹️"]))
            case .vending where moved: said.append((id, ["🥤"]))
            case .espresso where moved: said.append((id, ["☕"]))
            default:
                if BreakRoom.laughing.contains(member.clip) { said.append((id, ["😂", "🤣", "😆"])) }
                else if BreakRoom.talking.contains(member.clip) { said.append((id, ["💬", "🗣️", "💬", "👀"])) }
            }
        }
        for (id, member) in breakRoom.members where member.clip == "play_arcade" {
            guard let director = chefs[id]?.director, director.clip.name == "play_arcade" else { arcadeTime[id] = nil; continue }
            let win = (director.clips["play_arcade"]?.duration ?? 6) * (director.clips["play_arcade"]?.markers["win"] ?? 0.77)
            let t = director.clipTime, last = arcadeTime[id] ?? t
            if last < win && t >= win || (t < last && win <= t) {
                // Every other win gets a trophy, so they stay a treat.
                arcadeWins[id, default: 0] += 1
                if arcadeWins[id, default: 0] % 2 == 1 { said.append((id, ["🏆", "⭐", "🎉"])) }
            }
            arcadeTime[id] = t
        }
        chefLock.unlock()
        for (id, options) in said { say(id, options, now: now) }
    }

    /// Puts up a bubble over a resting chef: at most one each, three seconds apart, four at once.
    private func say(_ id: String, _ options: [String], now: Double) {
        guard selectedID == nil, !options.isEmpty, now - (lastBubble[id] ?? -.infinity) >= 3 else { return }
        let showing = bubbles.values.filter { $0.until > now }.count
        guard showing < 4 || bubbles[id] != nil else { return }
        let bubble = bubbles[id] ?? { let b = ChefBubbleView(frame: .zero); addSubview(b); bubbles[id] = b; return b }()
        bubbleCount += 1
        bubble.show(options[bubbleCount % options.count], now: now, reducedMotion: reduced)
        lastBubble[id] = now
    }

    /// Bubbles ride over their chefs' heads (off to one side of the tag) and fade when done.
    func placeBubbles(now: Double) {
        chefLock.lock()
        let positions = bubbles.keys.reduce(into: [String: SIMD3<Float>]()) { $0[$1] = chefs[$1]?.root.simdPosition }
        chefLock.unlock()
        for (id, bubble) in bubbles {
            guard selectedID == nil, let root = positions[id], bubble.update(now: now),
                  let point = projectWithoutLock(root + SIMD3(0.35, 2.15 * ChefMetrics.chefScale, 0)) else {
                bubble.removeFromSuperview(); bubbles[id] = nil; continue
            }
            // Projected points are from the bottom left (as `tagFrame` reads them); the tail sits on the point.
            let size = ChefBubbleView.size
            let bottom = isFlipped ? bounds.height - point.y - size.height : point.y
            bubble.frame = CGRect(x: point.x - size.width / 2, y: bottom, width: size.width, height: size.height)
        }
    }
    /// The emoji bubbles showing now, by chef (for tests).
    var bubbleEmoji: [String: String] { bubbles.compactMapValues { $0.isHidden ? nil : $0.emoji } }
}

