import SwiftUI
import SceneKit
import DioramaCore

/// The adapter observes existing conversation state; it never starts or resumes an agent.
struct WorkspaceSessionScene: View {
    @Bindable var library: LibraryModel
    @Environment(\.scenePhase) private var scenePhase
    let session: Session?
    var openConversation: () -> Void
    var openActivity: () -> Void

    @State private var libraryVisible = false
    @State private var libraryModel = CapabilityLibraryModel()
    @State private var selectedBook: CapabilityLibraryItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var context: CapabilityLibraryContext {
        let segment = session.flatMap { library.conversations.record($0.id)?.segments.last }
        return .init(provider: segment.flatMap { Provider(rawValue: $0.provider) } ?? session?.provider ?? .codex,
              folder: session?.project ?? library.projects.selected?.folder ?? FileManager.default.homeDirectoryForCurrentUser.path,
              sessionID: segment?.nativeID ?? session?.sessionID)
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1000
            HStack(spacing: 0) {
                WorkspaceSceneView(agents: library.workspaceAgents(session), openAgent: { agent in
                    if let recordID = agent.activityRecordID, let session {
                        let state = library.activityState(session)
                        state.section = "Agents"; state.selectedAgent = recordID; openActivity()
                    } else { openConversation() }
                }, agentDetails: { agent in
                    AnyView(AgentWorkDetailsView(library: library, parent: session, agent: agent, openConversation: openConversation))
                }, libraryOpen: libraryVisible, selectedBook: selectedBook, openLibrary: {
                    withAnimation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.22)) { libraryVisible.toggle() }
                })
                if wide && libraryVisible {
                    catalogue(compact: false).frame(width: 440)
                        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97, anchor: .leading)))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let session, let observation = library.observations[session.id] {
                    Text(library.paused ? "Observation paused" : observation.error.map { "Observation unavailable · " + $0 }
                         ?? "Observing \(session.origin == .claudeDesktop ? "Claude Code Desktop" : session.provider.rawValue) · synced \(observation.synchronizedAt.formatted(date: .omitted, time: .standard))\(session.provider == .codex ? " · source may buffer updates" : "")")
                        .font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(10)
                        .accessibilityIdentifier("external-observation-status")
                }
            }
            .sheet(isPresented: Binding(get: { libraryVisible && !wide }, set: { if !$0 { closeLibrary() } })) {
                catalogue(compact: true).frame(minWidth: 360, idealWidth: 480, maxWidth: 620, minHeight: 480, idealHeight: 680)
            }
        }
        .onExitCommand {
            if libraryVisible {
                if selectedBook != nil { selectedBook = nil } else { closeLibrary() }
            }
        }
        .onChange(of: context) { libraryVisible = false; selectedBook = nil }
        .task(id: scenePhase == .active ? session?.sessionID : nil) {
            guard scenePhase == .active, session != nil else { return }
            while !Task.isCancelled {
                library.observationClock = Date()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .task(id: scenePhase == .active ? session?.sessionID : nil) {
            guard scenePhase == .active, let session else { return }
            while !Task.isCancelled {
                if !library.paused, library.execution.tasks[session.sessionID]?.attached == true {
                    await library.execution.refreshAgents(session)
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    private func catalogue(compact: Bool) -> some View {
        CapabilityLibraryView(controller: library.execution, context: context, compact: compact, selected: $selectedBook, model: libraryModel, close: closeLibrary)
    }
    private func closeLibrary() {
        selectedBook = nil
        withAnimation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.22)) { libraryVisible = false }
    }
}

struct WorkspaceSceneView: View {
    var startInMovementLab = false
    var agents: [WorkspaceAgent] = [.ready]
    var openAgent: (WorkspaceAgent) -> Void = { _ in }
    var agentDetails: ((WorkspaceAgent) -> AnyView)? = nil
    var libraryOpen = false
    var selectedBook: CapabilityLibraryItem?
    var openLibrary: () -> Void = {}
    @FocusState private var libraryButtonFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var resetGeneration = 0
    @State private var selectedID: String?
    @State private var rosterVisible = false
    @State private var movementLab = false
    @State private var movementGait = WorkspaceCapybaraMotion.Gait.walk
    @State private var movementCommand = 0
    @State private var movementAction = "stop"
    @State private var movementStatus = "Click the floor to move"
    @State private var roster = WorkspaceAgentRoster()
    private var displayedAgents: [WorkspaceAgent] { roster.agents.isEmpty ? agents : roster.agents }

    private var selected: WorkspaceAgent? { displayedAgents.first { $0.id == selectedID } }

    var body: some View {
        GeometryReader { geometry in
            WorkspaceSceneSurface(agents: displayedAgents, selectedID: selectedID, reduceMotion: reduceMotion,
                                  active: scenePhase == .active, resetGeneration: resetGeneration,
                                  select: { selectedID = $0 }, openLibrary: openLibrary,
                                  selectedBook: selectedBook, libraryOpen: libraryOpen, movementLab: movementLab,
                                  movementGait: movementGait, movementCommand: movementCommand, movementAction: movementAction,
                                  movementStatus: { movementStatus = $0 })
                .overlay(alignment: .top) {
                    HStack {
                        Button("Agents · \(displayedAgents.count)", systemImage: "person.2") { rosterVisible.toggle() }
                            .popover(isPresented: $rosterVisible) {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 4) {
                                        ForEach(displayedAgents) { agent in
                                            Button {
                                                selectedID = agent.id
                                                rosterVisible = false
                                            } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(agent.name).fontWeight(.medium)
                                                    Text(agent.statusLabel).foregroundStyle(.secondary)
                                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(agent.accessibilityLabel)
                                            .accessibilityHint("Show agent details")
                                        }
                                    }.padding(8)
                                }.frame(width: 300, height: min(360, CGFloat(displayedAgents.count) * 70 + 16))
                            }
                        Button("Library", systemImage: "books.vertical") { openLibrary() }
                            .focused($libraryButtonFocused).help("Browse workspace capabilities")
                        Button("Movement Lab", systemImage: "figure.walk") { movementLab.toggle() }
                            .help("Test the capybara in this workspace")
                        Spacer()
                        Button("Reset View", systemImage: "arrow.counterclockwise") { resetGeneration += 1 }
                    }
                    .buttonStyle(.borderless).font(.caption)
                    .padding(10)
                    .background(DioramaStyle.sidebar, in: RoundedRectangle(cornerRadius: 8))
                    .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    if movementLab {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Capybara movement").font(.headline)
                            Picker("Gait", selection: $movementGait) {
                                ForEach(WorkspaceCapybaraMotion.Gait.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                            HStack {
                                ForEach(["Stop", "Turn left", "Turn right", "Reset"], id: \.self) { action in
                                    Button(action) { movementAction = action.lowercased(); movementCommand += 1 }
                                }
                            }
                            Text(movementStatus).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("Click the floor to move around furniture. Drag to orbit; scroll to zoom.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(14).frame(width: min(400, max(220, geometry.size.width - 24)))
                            .background(DioramaStyle.sidebar, in: RoundedRectangle(cornerRadius: 12)).padding(12)
                    } else if let selected {
                        details(selected)
                            .frame(width: min(340, max(200, geometry.size.width - 24)),
                                   height: min(320, max(160, geometry.size.height * 0.48)))
                            .background(DioramaStyle.sidebar, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DioramaStyle.border))
                            .padding(12)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if startInMovementLab { movementLab = true } }
        .onChange(of: agents, initial: true) { roster.update(agents) }
        .onChange(of: libraryOpen) { if !libraryOpen { libraryButtonFocused = true } }
    }

    private func details(_ agent: WorkspaceAgent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(agent.name).font(.headline).lineLimit(2)
                Spacer(minLength: 4)
                Button { selectedID = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close agent details").accessibilityLabel("Close agent details")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(agent.statusLabel).fontWeight(.medium)
                    Text(agent.freshness.rawValue + (agent.provider.isEmpty ? "" : " · " + agent.provider))
                        .foregroundStyle(.secondary)
                    if !agent.task.isEmpty { Text(agent.task).textSelection(.enabled) }
                    if !agent.action.isEmpty { Text("Latest action: " + agent.action).textSelection(.enabled) }
                    if let parent = agent.parentName { Text("Parent: " + parent).foregroundStyle(.secondary) }
                    if agent.status == .unknown && !agent.reportedStatus.isEmpty {
                        Text("Reported status: " + agent.reportedStatus).foregroundStyle(.secondary)
                    }
                    if let observed = agent.observedAt {
                        Text("Reported " + observed.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    if let agentDetails { agentDetails(agent) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption)
            Button(agent.isMain ? "Open Conversation" : "Open Activity Details") { openAgent(agent) }
                .buttonStyle(.bordered)
        }.padding(14)
    }
}

private struct WorkspaceSceneSurface: NSViewRepresentable {
    let agents: [WorkspaceAgent]
    let selectedID: String?
    let reduceMotion: Bool
    let active: Bool
    let resetGeneration: Int
    let select: (String?) -> Void
    let openLibrary: () -> Void
    let selectedBook: CapabilityLibraryItem?
    let libraryOpen: Bool
    let movementLab: Bool
    let movementGait: WorkspaceCapybaraMotion.Gait
    let movementCommand: Int
    let movementAction: String
    let movementStatus: (String) -> Void

    func makeNSView(context: Context) -> WorkspaceSceneNSView {
        let view = WorkspaceSceneNSView()
        view.apply(agents: agents, selectedID: selectedID, reduceMotion: reduceMotion, active: active)
        view.selectAgent = select; view.openLibrary = openLibrary
        view.updateLibrary(selectedBook, open: libraryOpen, reduceMotion: reduceMotion, active: active)
        view.resetCamera()
        view.movementStatusChanged = movementStatus
        view.configureMovementLab(enabled: movementLab, gait: movementGait, command: movementCommand, action: movementAction)
        return view
    }

    func updateNSView(_ view: WorkspaceSceneNSView, context: Context) {
        view.movementStatusChanged = movementStatus
        view.configureMovementLab(enabled: movementLab, gait: movementGait, command: movementCommand, action: movementAction)
        view.selectAgent = select; view.openLibrary = openLibrary
        view.updateLibrary(selectedBook, open: libraryOpen, reduceMotion: reduceMotion, active: active)
        view.apply(agents: agents, selectedID: selectedID, reduceMotion: reduceMotion, active: active)
        if view.resetGeneration != resetGeneration {
            view.resetGeneration = resetGeneration
            view.resetCamera()
        }
    }

    static func dismantleNSView(_ view: WorkspaceSceneNSView, coordinator: ()) {
        view.stopRendering()
        view.selectAgent = nil; view.openLibrary = nil
        view.scene = nil
        view.pointOfView = nil
    }
}

final class WorkspaceSceneNSView: SCNView {
    var resetGeneration = 0
    var selectAgent: ((String?) -> Void)?
    var openLibrary: (() -> Void)?
    private var bookID: String?
    private var libraryOpened = false
    private var libraryAnimationEnds = Date.distantPast
    private var hoverLibrary = false
    private var tracking: NSTrackingArea?
    private var libraryNode: SCNNode? { scene?.rootNode.childNode(withName: "library", recursively: false) }
    private(set) var workstations: [String: WorkspaceWorkstation] = [:]
    private var slotIDs: [String] = []
    private var presentedAgents: [WorkspaceAgent] = []
    private var renderingActive = true
    private(set) var movementCharacter: WorkspaceCapybaraMotion?
    var movementStatusChanged: ((String) -> Void)?
    private var movementTimer: Timer?
    private var movementLastTime: TimeInterval = 0
    private var movementLastReport: TimeInterval = 0
    private var movementCommand = -1
    private var movementEnabled = false
    private var movementSavedCamera: (yaw: Double, elevation: Double, distance: Double, target: SCNVector3)?
    private var movementReduced = false
    private var movementMarker: SCNNode?
    private var floorLength = 20.0
    private var floorCenterZ = 0.0
    private var cameraTarget = SCNVector3Zero
    private var dragDistance = 0.0
    private var isOrbiting = false
    private let cameraNode = SCNNode()
    private(set) var yaw = Double.pi / 4
    private(set) var elevation = Double.pi / 6
    private(set) var distance = 38.0

    init() {
        super.init(frame: .zero, options: nil)
        backgroundColor = NSColor(srgbRed: 0.075, green: 0.063, blue: 0.067, alpha: 1)
        antialiasingMode = .multisampling4X
        rendersContinuously = false
        isPlaying = false
        allowsCameraControl = false
        scene = Self.makeScene()
        let library = WorkspaceLibraryArtwork.alcove()
        library.position = SCNVector3(-5.6, 0, 5)
        scene?.rootNode.addChildNode(library)
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 0.1
        camera.zFar = 200
        cameraNode.camera = camera
        scene?.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        setAccessibilityElement(true)
        setAccessibilityLabel("Workspace agent diorama")
        setAccessibilityHelp("Drag to orbit. Scroll to zoom. Use Reset View to restore the camera.")
        resetCamera()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        for node in floorNodes(length: 20, centerZ: 0) { scene.rootNode.addChildNode(node) }
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .directional
        light.light?.intensity = 850
        light.eulerAngles = SCNVector3(-Double.pi / 3, -Double.pi / 4, 0)
        scene.rootNode.addChildNode(light)
        return scene
    }

    private static func floorNodes(length: Double, centerZ: Double) -> [SCNNode] {
        let material = WorkspaceAvatarFactory.material(NSColor(white: 0.18, alpha: 1))
        let platform = WorkspaceAvatarFactory.box(20, 0.25, CGFloat(length),
            at: SCNVector3(0, -0.125, centerZ), material: material)
        platform.name = "ground"
        let lineMaterial = WorkspaceAvatarFactory.material(NSColor(white: 0.38, alpha: 1), constant: true)
        var nodes = [platform]
        for x in -10...10 {
            let node = WorkspaceAvatarFactory.box(0.025, 0.006, CGFloat(length),
                at: SCNVector3(Double(x), 0.006, centerZ), material: lineMaterial)
            node.name = "grid"; nodes.append(node)
        }
        for z in Int(centerZ - length / 2)...Int(centerZ + length / 2) {
            let node = WorkspaceAvatarFactory.box(20, 0.006, 0.025,
                at: SCNVector3(0, 0.006, Double(z)), material: lineMaterial)
            node.name = "grid"; nodes.append(node)
        }
        return nodes
    }

    func apply(agents: [WorkspaceAgent], selectedID: String?, reduceMotion: Bool, active: Bool) {
        presentedAgents = agents
        renderingActive = active
        movementReduced = reduceMotion
        movementCharacter?.reducedMotion = reduceMotion
        let incoming = Set(agents.map(\.id))
        // Only a genuinely removed record disappears. Completed records keep their original slot.
        for id in Array(workstations.keys) where !incoming.contains(id) {
            workstations.removeValue(forKey: id)?.root.removeFromParentNode()
        }
        for agent in agents {
            if workstations[agent.id] == nil {
                if !slotIDs.contains(agent.id) { slotIDs.append(agent.id) }
                let index = slotIDs.firstIndex(of: agent.id) ?? 0
                let workstation = WorkspaceWorkstation(id: agent.id, index: index)
                workstation.animationChanged = { [weak self] in self?.updateRenderingActivity() }
                workstation.root.position = Self.position(for: index)
                workstations[agent.id] = workstation
                scene?.rootNode.addChildNode(workstation.root)
            }
            workstations[agent.id]?.update(agent, selected: selectedID == agent.id,
                                          reduceMotion: reduceMotion, active: active, cameraYaw: yaw)
        }
        let lastZ = slotIDs.indices.map { Double(Self.position(for: $0).z) }.min() ?? 0
        let minZ = min(-10, lastZ - 4)
        let length = 10 - minZ
        if length != floorLength {
            floorLength = length
            floorCenterZ = (10 + minZ) / 2
            for node in scene?.rootNode.childNodes ?? [] where node.name == "ground" || node.name == "grid" {
                node.removeFromParentNode()
            }
            for node in Self.floorNodes(length: length, centerZ: floorCenterZ) { scene?.rootNode.addChildNode(node) }
        }
        for station in workstations.values { station.setMovementLab(movementEnabled) }
        refreshMovementNavigation()
        updateMovementTimer()
        updateRenderingActivity()
    }

    private func updateRenderingActivity() {
        isPlaying = renderingActive && (workstations.values.contains { $0.animating } || libraryAnimationEnds > Date() || movementEnabled)
        rendersContinuously = isPlaying
        preferredFramesPerSecond = movementEnabled ? 60 : 30
        needsDisplay = true
    }

    static func position(for slot: Int) -> SCNVector3 {
        if slot == 0 { return SCNVector3(0, 0, 4) }
        let child = slot - 1
        return SCNVector3(Double(child % 3 - 1) * 6, 0, -2 - Double(child / 3) * 6)
    }

    func stopRendering() {
        renderingActive = false
        movementTimer?.invalidate(); movementTimer = nil
        libraryAnimationEnds = .distantPast
        let book = libraryNode?.childNode(withName: "selectedLibraryBook", recursively: false)
        book?.removeAllActions(); book?.opacity = 1; book?.position = SCNVector3(0.17, 0.96, 1.10)
        for agent in presentedAgents {
            workstations[agent.id]?.update(agent, selected: false, reduceMotion: true, active: false)
        }
        isPlaying = false
        rendersContinuously = false
    }

    private var fittingDistance: Double {
        let halfDiagonal = (10 + floorLength / 2) / sqrt(2)
        return max(38, (halfDiagonal + 1) * 1.12 / 0.45)
    }

    func resetCamera() {
        yaw = .pi / 4
        elevation = .pi / 6
        distance = fittingDistance
        cameraTarget = SCNVector3(0, 0, floorCenterZ)
        updateCamera()
    }

    func orbit(dx: Double, dy: Double) {
        yaw -= dx * 0.008
        // Keep the floor readable instead of allowing an edge-on or overhead view.
        elevation = min(55 * .pi / 180, max(25 * .pi / 180, elevation + dy * 0.008))
        updateCamera()
    }

    func zoom(delta: Double) {
        distance = min(max(80, fittingDistance * 2), max(16, distance * exp(delta * 0.015)))
        updateCamera()
    }

    private func updateCamera() {
        // Parallel projection keeps both ends of the floor the same size.
        // Zoom changes the viewing scale, while the camera stays outside the scene.
        cameraNode.camera?.orthographicScale = distance * 0.45 * max(1, Double(bounds.height / max(1, bounds.width)))
        let fittedDistance = max(50, distance * 2)
        cameraNode.camera?.zFar = fittedDistance + max(100, floorLength * 2)
        cameraNode.position = SCNVector3(Double(cameraTarget.x) + fittedDistance * cos(elevation) * sin(yaw),
                                         Double(cameraTarget.y) + fittedDistance * sin(elevation),
                                         Double(cameraTarget.z) + fittedDistance * cos(elevation) * cos(yaw))
        // The one-argument look(at:) uses the camera's previous worldUp.
        // Reusing that rotated vector accumulates roll during orbit gestures.
        cameraNode.look(at: cameraTarget, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateCamera()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragDistance = 0
        isOrbiting = false
    }
    override func mouseDragged(with event: NSEvent) {
        dragDistance += abs(event.deltaX) + abs(event.deltaY)
        if dragDistance > 4 { isOrbiting = true }
        if isOrbiting { orbit(dx: event.deltaX, dy: event.deltaY) }
    }
    override func mouseUp(with event: NSEvent) {
        guard !isOrbiting else { return }
        let point = convert(event.locationInWindow, from: nil)
        if movementEnabled {
            moveCapybara(at: point)
            return
        }
        if target(at: point) == .library { openLibrary?() }
        else { selectAgent?(agentID(at: point)) }
    }
    func configureMovementLab(enabled: Bool, gait: WorkspaceCapybaraMotion.Gait, command: Int, action: String) {
        if enabled && movementCharacter == nil {
            do {
                let character = WorkspaceCapybaraMotion(asset: try WorkspaceCapybaraAsset.shared.get())
                movementCharacter = character; scene?.rootNode.addChildNode(character.root)
                let ring = SCNTorus(ringRadius: 0.28, pipeRadius: 0.025)
                ring.materials = [WorkspaceAvatarFactory.material(.systemMint, constant: true)]
                let marker = SCNNode(geometry: ring); marker.position.y = 0.03; marker.isHidden = true
                scene?.rootNode.addChildNode(marker); movementMarker = marker
            } catch {
                let callback = movementStatusChanged
                Task { callback?("Character could not load: \(error.localizedDescription)") }
                return
            }
        }
        if enabled != movementEnabled {
            movementEnabled = enabled
            movementCharacter?.root.isHidden = !enabled
            movementMarker?.isHidden = true
            if !enabled {
                movementCharacter?.stop()
                if let saved = movementSavedCamera {
                    yaw=saved.yaw;elevation=saved.elevation;distance=saved.distance;cameraTarget=saved.target
                    updateCamera();movementSavedCamera=nil
                }
            }
            if enabled {
                movementSavedCamera=(yaw,elevation,distance,cameraTarget)
                // Frame the actual workspace and its furniture, without following or orbiting automatically.
                cameraTarget = SCNVector3(0, 0.6, 2); distance = 22; updateCamera()
            }
        }
        movementCharacter?.gait = gait
        movementCharacter?.reducedMotion = movementReduced
        if command != movementCommand {
            movementCommand = command
            switch action {
            case "stop": movementCharacter?.stop()
            case "turn left": movementCharacter?.turn(by: .pi / 2)
            case "turn right": movementCharacter?.turn(by: -.pi / 2)
            case "reset": movementCharacter?.reset()
            default: break
            }
        }
        for station in workstations.values { station.setMovementLab(enabled) }
        refreshMovementNavigation(); updateMovementTimer(); updateRenderingActivity()
    }

    private func refreshMovementNavigation() {
        guard let character = movementCharacter else { return }
        character.navigation.min = SIMD2(-9, Float(floorCenterZ-floorLength/2+1))
        // Desk, chair and seated agent footprints, expanded by the capybara's radius.
        character.navigation.obstacles = workstations.values.map { station in
            let p = station.root.simdPosition
            return .init(min: SIMD2(p.x-2.4,p.z-2.3), max: SIMD2(p.x+2.4,p.z+2.05))
        }
        character.navigation.obstacles.append(.init(min: SIMD2(-8.5,3), max: SIMD2(-2.6,7.4)))
    }

    private func updateMovementTimer() {
        guard renderingActive && movementEnabled else { movementTimer?.invalidate(); movementTimer=nil;return }
        guard movementTimer == nil else { return }
        movementLastTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickMovement() }
        }
        RunLoop.main.add(timer,forMode:.common);movementTimer=timer
    }
    private func tickMovement() {
        let now = ProcessInfo.processInfo.systemUptime
        movementCharacter?.update(now-movementLastTime);movementLastTime=now;needsDisplay=true
        if now-movementLastReport > 0.2, let character = movementCharacter {
            movementLastReport=now
            movementStatusChanged?(character.rejectedDestination ? "That spot is blocked. Choose open floor." : character.debug)
            if character.path.isEmpty { movementMarker?.isHidden=true }
        }
    }
    private func moveCapybara(at point: NSPoint) {
        let near = unprojectPoint(SCNVector3(point.x,point.y,0)), far = unprojectPoint(SCNVector3(point.x,point.y,1))
        let delta = SCNVector3(far.x-near.x,far.y-near.y,far.z-near.z)
        guard abs(delta.y)>0.0001 else { return }
        let t = -near.y/delta.y
        guard t>=0 else { return }
        let destination = SIMD2(Float(near.x+delta.x*t),Float(near.z+delta.z*t))
        if movementCharacter?.move(to:destination) == true {
            movementMarker?.position=SCNVector3(destination.x,0.03,destination.y);movementMarker?.isHidden=false
        }
    }

    enum HitTarget: Equatable { case library, agent(String) }
    func target(at point: NSPoint) -> HitTarget? {
        for hit in hitTest(point, options: nil) {
            var node: SCNNode? = hit.node
            while let current = node {
                if current.name == "library" { return .library }
                if let name = current.name, name.hasPrefix("agent:") { return .agent(String(name.dropFirst(6))) }
                node = current.parent
            }
        }
        return nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        let hovering = target(at: convert(event.locationInWindow, from: nil)) == .library
        guard hovering != hoverLibrary else { return }
        hoverLibrary = hovering; highlightLibrary()
        if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
    override func mouseExited(with event: NSEvent) { hoverLibrary = false; highlightLibrary(); NSCursor.arrow.set() }
    private func highlightLibrary() {
        libraryNode?.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                material.emission.contents = (hoverLibrary || libraryOpened) ? NSColor(white: 0.08, alpha: 1) : NSColor.black
            }
        }
        needsDisplay = true
    }
    func updateLibrary(_ item: CapabilityLibraryItem?, open: Bool, reduceMotion: Bool, active: Bool) {
        libraryOpened = open; highlightLibrary()
        let identity = item.map { $0.id + ":" + String($0.coverIndex) }
        guard identity != bookID else {
            if !active || reduceMotion {
                libraryAnimationEnds = .distantPast
                let book = libraryNode?.childNode(withName: "selectedLibraryBook", recursively: false)
                book?.removeAllActions(); book?.opacity = 1; book?.position = SCNVector3(0.17, 0.96, 1.10)
            }
            return
        }
        bookID = identity
        libraryNode?.childNode(withName: "selectedLibraryBook", recursively: false)?.removeFromParentNode()
        guard let item else { libraryAnimationEnds = .distantPast; updateRenderingActivity(); return }
        let book = WorkspaceLibraryArtwork.book(item)
        book.position = SCNVector3(0.17, 0.96, 1.10)
        libraryNode?.addChildNode(book)
        if !reduceMotion && active {
            book.opacity = 0; book.position.y = 0.90
            let move = SCNAction.move(to: SCNVector3(0.17, 0.96, 1.10), duration: 0.18)
            move.timingMode = .easeOut
            book.runAction(.group([move, .fadeIn(duration: 0.18)]))
            libraryAnimationEnds = Date().addingTimeInterval(0.18)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.updateRenderingActivity()
            }
        }
        updateRenderingActivity()
    }
    func agentID(at point: NSPoint) -> String? {
        for hit in hitTest(point, options: nil) {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("agent:") { return String(name.dropFirst(6)) }
                node = current.parent
            }
        }
        return nil
    }
    override func scrollWheel(with event: NSEvent) { zoom(delta: event.scrollingDeltaY) }
    override var acceptsFirstResponder: Bool { true }
}
