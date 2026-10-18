import AppKit
@testable import DioramaCore
import SceneKit
import Testing
import simd
@testable import DioramaApp

@MainActor struct OfficeSceneTests {
    private func agent(_ id: String, _ status: WorkspaceAgentStatus, tool: String = "", detail: String = "", attention: WorkspaceAttentionReason = .other,
                       edits: Bool = false, freshness: WorkspaceAgentFreshness = .live) -> SpatialAgent {
        var value = WorkspaceAgent(id: id, name: "Agent \(id)", provider: "Claude", task: "Task", action: "", status: status, reportedStatus: status.rawValue, freshness: freshness)
        value.latestTool = tool; value.latestToolDetail = detail; value.attentionReason = attention; value.turnHasEdits = edits
        value.completionKey = "turn-1"
        return SpatialAgent(projectID: "p", conversationID: "c-" + id, value: value)
    }
    /// One agent at every station, and a few resting.
    private var crew: [SpatialAgent] {
        [agent("ready", .ready, freshness: .ready), agent("plan", .working, tool: "TaskCreate"), agent("read", .working, tool: "Read"),
         agent("edit", .working, tool: "Edit", edits: true), agent("edit2", .working, tool: "Write", edits: true),
         agent("run", .working, tool: "Bash", detail: "make", edits: true), agent("test", .working, tool: "Bash", detail: "swift test", edits: true),
         agent("ask", .waiting, attention: .approval), agent("main", .done), agent("skill", .working, tool: "Skill", detail: "pdf")]
            + (0..<4).map { agent("rest\($0)", .done, freshness: .lastKnown) }
    }
    /// A chef by its agent's id (chef ids are the full agent ids).
    private func chef(_ view: DioramaSceneView, _ id: String) -> ChefAvatar? { view.chefs.first { $0.key.hasSuffix(":" + id) }?.value }
    private func settle(_ view: DioramaSceneView, seconds: Double) {
        var clock = 1000.0
        for _ in 0..<Int(seconds * 30) {
            clock += 1 / 30
            for chef in view.chefs.values { chef.update(1 / 30) }
            view.pace(now: clock); view.updateBreakRoom(now: clock); view.updateEffects()
            view.updateManager(); view.updateGong(); view.serveDiners(now: clock)
        }
    }

    /// Every agent state goes to the same station in the office as in the kitchen, with the same
    /// urgency and gestures: only the clip's props (and the needs-you strike) differ.
    @Test func officeRoutesLikeTheKitchen() throws {
        let assets = try ChefAssets.shared.get()
        let tools: [(String, String)] = [("", ""), ("Read", ""), ("Edit", ""), ("TaskCreate", ""), ("Bash", "make"), ("Bash", "swift test"), ("Skill", "pdf")]
        let reviews: [KitchenReviews.State?] = [nil, .approved, .checking, .needsFix, .shipped, .reworking, .awaiting]
        for status in [WorkspaceAgentStatus.ready, .working, .waiting, .done, .stopped, .failed, .unknown] {
            for freshness in [WorkspaceAgentFreshness.live, .lastKnown] {
                for (tool, detail) in tools {
                    for edits in [false, true] {
                        for review in reviews {
                            let a = agent("x", status, tool: tool, detail: detail, attention: .approval, edits: edits, freshness: freshness).value
                            let kitchen = SceneLayout.kitchen.work(for: a, review: review), office = SceneLayout.office.work(for: a, review: review)
                            #expect(kitchen.area == office.area && kitchen.loop == office.loop && kitchen.oneShot == office.oneShot)
                            #expect(kitchen.urgent == office.urgent && kitchen.deliversPlate == office.deliversPlate && kitchen.prelude == office.prelude)
                            #expect(Set(ChefAssets.spec.requiredClips).contains(office.loop))
                            if let hand = office.hand { #expect(assets.props[hand.node] != nil) }
                            #expect(![ChefProp.knife, .spoon].contains(office.hand))
                        }
                    }
                }
            }
        }
        // The desk bell rings as a chef arrives; nobody strikes it.
        let waiting = agent("w", .waiting, attention: .input).value
        let slot = try #require(SceneLayout.office.chefSlots["bell"]?.first)
        #expect(SceneLayout.office.intent(for: waiting, at: slot, pickup: nil, restored: false).strike == nil)
        #expect(SceneLayout.kitchen.intent(for: waiting, at: slot, pickup: nil, restored: false).strike != nil)
    }

    /// Every station has its spots on free floor that a newcomer can walk to from the elevator, and
    /// every fixture stays inside its footprint with its worktop at the chef's working height.
    @Test func officeFloorPlanIsWalkableAndFixturesFit() throws {
        let layout = SceneLayout.office
        let navigation = layout.chefNavigation, landing = layout.elevatorLanding.stand
        for area in layout.areas {
            #expect(layout.floor.contains(area.footprint), "\(area.id) inside the floor")
            let slots = try #require(layout.chefSlots[area.id])
            #expect(slots.count >= min(area.spots, 1), "\(area.id) has slots")
            for slot in slots where area.id != "elevator" {
                #expect(navigation.isFree(slot.stand), "\(slot.id) on free floor")
                #expect(navigation.route(from: landing, to: slot.stand) != nil, "\(slot.id) reachable")
            }
        }
        #expect(navigation.isFree(layout.managerDoor.stand))
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), theme: OfficeTheme.shared)
        for area in layout.areas where !["elevator", "break", "bell"].contains(area.id) {
            let node = try #require(view.scene?.rootNode.childNode(withName: area.id, recursively: false))
            var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
            node.enumerateHierarchy { child, _ in
                guard child.geometry != nil, !(child.name ?? "").hasPrefix("plant"), child.parent?.name != "plant" else { return }
                let (a, b) = child.boundingBox
                for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                    let p = child.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: nil)
                    low = simd_min(low, p); high = simd_max(high, p)
                } } }
            }
            let f = area.footprint.insetBy(dx: -0.05, dy: -0.05)
            #expect(CGFloat(low.x) >= f.minX && CGFloat(high.x) <= f.maxX && CGFloat(low.z) >= f.minY && CGFloat(high.z) <= f.maxY, "\(area.id) fixture inside its footprint")
            // The worktop under each chef's hands, a hand's reach into the station.
            for slot in layout.chefSlots[area.id] ?? [] {
                let hand = slot.stand + SIMD2(sin(slot.facing), cos(slot.facing)) * (ChefMetrics.chefCounterFront * ChefMetrics.chefScale + 0.1)
                let hits = try #require(view.scene).rootNode.hitTestWithSegment(from: SCNVector3(CGFloat(hand.x), 3, CGFloat(hand.y)), to: SCNVector3(CGFloat(hand.x), 0, CGFloat(hand.y)), options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
                let top = try #require(hits.first.map { Float($0.worldCoordinates.y) }, "\(slot.id) has a worktop")
                #expect(top >= ChefMetrics.worktopHeight - 0.02 && top <= ChefMetrics.worktopHeight + 0.06, "\(slot.id) worktop at the chef's hands: \(top)")
            }
        }
        // The lobby seats a client at every table spot.
        #expect(OfficeLobby.shared.seats.count == DioramaSceneView.dinerCount)
    }

    /// A full crew: chefs at their stations, clients in the lobby, desks lit while someone types and
    /// the rack blinking while a command runs; the bell rings for the chef that needs you.
    @Test func officeRunsAFullCrew() throws {
        _ = try ChefAssets.shared.get()
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700), theme: OfficeTheme.shared)
        view.characters = ChefCharacterModel(url: nil)
        view.apply(agents: crew, scope: "p", active: false, reducedMotion: false)
        settle(view, seconds: 25)
        #expect(view.diners.count == DioramaSceneView.dinerCount)
        #expect(view.chefs.count == crew.count)
        #expect(chef(view, "edit")?.director.station?.area == "cooking" && chef(view, "run")?.director.station?.area == "stove")
        #expect(chef(view, "ask")?.director.station?.area == "bell")
        #expect(chef(view, "main")?.dishPlacement == "pass" || chef(view, "main")?.dishPlacement == "carry")
        #expect(OfficeProps.deliverables[chef(view, "main")?.dish ?? ""] != nil)
        #expect(view.litBurners.isEmpty && view.idleBoards.isEmpty)
        #expect(!view.servedSeats.isEmpty, "a client receives the finished deliverable")
        let accessibility = view.accessibilityLabel() ?? ""
        #expect(accessibility.hasPrefix("Office layout.") && accessibility.contains("Desks: editing code"), "\(accessibility)")
    }

    /// Switching a project's scene replaces its view: the office places every chef where its agent's
    /// state puts it (no elevator ride), at the camera's home view; the kitchen comes back the same way.
    @Test func switchingScenesSwapsTheProjectsView() throws {
        _ = try ChefAssets.shared.get()
        let stage = SceneStage(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let kitchen = stage.show("P", kind: .kitchen)
        kitchen.apply(agents: crew, scope: "P", active: false, reducedMotion: false)
        let other = stage.show("Q", kind: .kitchen)
        let office = stage.show("P", kind: .office)
        #expect(office !== kitchen && office.theme.kind == .office && kitchen.superview == nil)
        #expect(stage.kitchens.count == 2 && stage.kitchens["Q"] === other && other.isHidden && !office.isHidden)
        office.apply(agents: crew, scope: "P", active: false, reducedMotion: false)
        #expect(!office.elevatorOpen)
        #expect(office.freeCamera.isHome)
        let edit = try #require(chef(office, "edit"))
        #expect(edit.director.station?.area == "cooking" || edit.director.intent?.station?.area == "cooking")
        #expect(stage.show("P", kind: .office) === office)
        #expect(stage.show("P", kind: .kitchen).theme.kind == .kitchen)
    }

    /// The choice is per project, kept across launches, and an unknown saved value reads as the kitchen.
    @Test func sceneChoiceIsPerProjectAndSaved() throws {
        let defaults = try #require(UserDefaults(suiteName: "scenes-" + UUID().uuidString))
        let scenes = ProjectScenes(defaults: defaults)
        #expect(scenes.kind(for: "a") == .kitchen && scenes.kind(for: nil) == .kitchen)
        scenes.set(.office, for: "a")
        #expect(scenes.kind(for: "a") == .office && scenes.kind(for: "b") == .kitchen)
        #expect(ProjectScenes(defaults: defaults).kind(for: "a") == .office)
        defaults.set(Data(#"{"a":"spaceship","b":"office"}"#.utf8), forKey: ProjectScenes.key)
        let restored = ProjectScenes(defaults: defaults)
        #expect(restored.kind(for: "a") == .kitchen && restored.kind(for: "b") == .office)
        #expect(ProjectScenes(defaults: nil).kind(for: "a") == .kitchen)
    }

    /// Switching tabs shows each project's own scene; the gear's choice applies at once.
    @Test func projectTabsShowTheirOwnScene() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scenes-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults(suiteName: "scene-tabs-" + UUID().uuidString))
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        projects.projects = ["A", "B"].map { DioramaProject(name: $0, folder: root.path, commonDirectory: root.path, base: "main", remote: nil) }
        let (a, b) = (projects.projects[0].id, projects.projects[1].id)
        let model = LibraryModel(projects: projects, navigation: WorkspaceNavigation(defaults: defaults), sceneDefaults: defaults)
        model.paused = true
        model.selectProjectTab(a)
        #expect(model.spatial.sceneKind == .kitchen)
        model.setScene(.office, project: a)
        #expect(model.spatial.sceneKind == .office)
        model.selectProjectTab(b)
        #expect(model.spatial.sceneKind == .kitchen)
        model.selectProjectTab(a)
        #expect(model.spatial.sceneKind == .office)
        model.selectDesktopTab(.home)
        #expect(model.spatial.sceneKind == .kitchen)
        #expect(ProjectScenes(defaults: defaults).kind(for: a) == .office)
    }

    /// Each office sound replaces a kitchen sound of the same name and variant.
    @Test func officeSoundsReplaceKitchenSounds() throws {
        let folder = try #require(SkinnedGLBAsset.resourceBundle.resourceURL?.appendingPathComponent(OfficeTheme.shared.soundFolder))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".caf") }
        #expect(files.count >= 10)
        for file in files {
            let parts = (file as NSString).deletingPathExtension.split(separator: "-")
            let sound = try #require(KitchenSound(rawValue: String(parts[0])), "\(file) names a kitchen sound")
            #expect(Int(parts[1]).map { $0 < sound.variants } == true, "\(file) is one of its variants")
        }
    }

    /// The lounge, where sounds are muted, holds every break-room spot and no other station's.
    @Test func loungeAreaCoversTheBreakRoomOnly() {
        for layout in [SceneLayout.kitchen, SceneLayout.office] {
            let lounge = layout.loungeArea
            for spot in layout.chefSlots["break"] ?? [] { #expect(lounge.contains(CGPoint(x: CGFloat(spot.stand.x), y: CGFloat(spot.stand.y))), "\(spot.id)") }
            for (area, slots) in layout.chefSlots where area != "break" {
                for slot in slots { #expect(!lounge.contains(CGPoint(x: CGFloat(slot.stand.x), y: CGFloat(slot.stand.y))), "\(slot.id) outside the lounge") }
            }
        }
    }

    /// Renders the office with a full crew (DIORAMA_OFFICE_CAPTURE=<folder>).
    @Test func captureOfficeWithCrew() throws {
        guard let folder = ProcessInfo.processInfo.environment["DIORAMA_OFFICE_CAPTURE"] else { return }
        let theme: any SceneTheme = ProcessInfo.processInfo.environment["DIORAMA_CAPTURE_SCENE"] == "kitchen" ? KitchenTheme.shared : OfficeTheme.shared
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1500, height: 900), theme: theme)
        view.characters = ChefCharacterModel(url: nil)
        view.apply(agents: crew, scope: "p", active: false, reducedMotion: false)
        settle(view, seconds: 20)
        for (name, size) in [("wide", CGSize(width: 1500, height: 900)), ("square", CGSize(width: 900, height: 900))] {
            view.frame.size = size; view.fitFloor()
            let tiff = try #require(view.snapshot().tiffRepresentation)
            try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: folder).appendingPathComponent("office-\(name).png"))
        }
        view.focusCamera(on: SIMD2(0, -2), zoom: 2.6)
        for _ in 0..<60 { view.renderer(view, updateAtTime: Double(view.chefs.count) + CACurrentMediaTime()) }
        let tiff = try #require(view.snapshot().tiffRepresentation)
        try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: folder).appendingPathComponent("office-close.png"))
    }
}
