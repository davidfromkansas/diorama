import AppKit
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct SharedOfficeTests {
    private func agent(_ id: String, status: WorkspaceAgentStatus = .working, at: Date? = nil, freshness: WorkspaceAgentFreshness = .live) -> SpatialAgent {
        SpatialAgent(projectID:"p",conversationID:"c",value:WorkspaceAgent(id:id,name:id,provider:"Codex",task:"Build offline support",action:"Editing",status:status,reportedStatus:status.rawValue,freshness:freshness,observedAt:at))
    }
    @Test func actualFurnitureLoadsAtAuthoredDimensionsAndPawsRemainSupported() throws {
        let models = try OfficeFurnitureAssets.loaded.get()
        let distant = try OfficeFurnitureAssets.low.get()
        #expect(distant.desk.boundingBox.max.y > 0.72)
        let chair = models.chair.boundingBox, desk = models.desk.boundingBox
        #expect(abs(Double(chair.max.y-chair.min.y)-1.0182)<0.01)
        #expect(abs(Double(desk.max.x-desk.min.x)-1.47015)<0.01)
        let station = OfficeWorkstation(id:"fit")
        #expect(station.assetsAvailable)
        #expect(station.avatar.root.scale.x == station.avatar.root.scale.y && station.avatar.root.scale.y == station.avatar.root.scale.z)
        let rig = try #require(station.avatar.capybaraRig)
        for side in ["L","R"] {
            let hand = try #require(rig.bone("hand."+side))
            #expect(hand.worldPosition.y > 0.73 && hand.worldPosition.y < 0.80)
            #expect(hand.worldPosition.z > -0.13 && hand.worldPosition.z < 0.05)
        }
    }
    @Test func workstationFitSnapshots() throws {
        let station = OfficeWorkstation(id:"fit")
        let occupant = OfficeOccupant(agent:agent("fit"),assignment:"Offline support")
        station.update(occupant,selected:false,reduced:true,active:false,distant:false)
        station.label.isHidden=true
        let scene=SCNScene();scene.rootNode.addChildNode(station.root)
        let floor=SCNFloor();floor.firstMaterial=WorkspaceAvatarFactory.material(NSColor(white:0.92,alpha:1));scene.rootNode.addChildNode(SCNNode(geometry:floor))
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=700;scene.rootNode.addChildNode(ambient)
        let sun=SCNNode();sun.light=SCNLight();sun.light?.type = .directional;sun.light?.intensity=900;sun.eulerAngles=SCNVector3(-0.7,-0.6,0);scene.rootNode.addChildNode(sun)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.orthographicScale=1.05;scene.rootNode.addChildNode(camera)
        let view=SCNView(frame:NSRect(x:0,y:0,width:900,height:900));view.scene=scene;view.pointOfView=camera;view.backgroundColor = .white;view.antialiasingMode = .multisampling4X
        for (name,position) in [("front",SCNVector3(0,1.0,4)),("side",SCNVector3(4,1.0,0)),("office",SCNVector3(2,4,-3))] {
            camera.position=position;camera.look(at:SCNVector3(0,0.64,0.12))
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/diorama-workstation-\(name).png"))
        }
    }
    @Test func defaultFurnitureFormsTwoCenteredRowsOfEight() {
        let layout = SharedOfficeLayout()
        #expect(layout.desks.count == 16)
        for desk in layout.desks {
            let originalZ = desk.slot < 8 ? -1.4 : 1.4
            #expect(abs(desk.z-originalZ)<0.03)
            #expect(abs(desk.yaw)<0.0001)
            if let baked = OfficeBakedLayout.transforms["desk:\(desk.slot)"] {
                #expect(desk.x == baked.x && desk.z == baked.z)
            }
        }
    }

    @Test func fixedDeskCapacityRetainsExistingAssignments() {
        var layout=SharedOfficeLayout();layout.register(["a","b","c","d"])
        let original=layout.assignments
        layout.register((0..<200).map { "worker-\($0)" })
        for (id,desk) in original { #expect(layout.assignments[id] == desk) }
        #expect(Set(layout.assignments.values.map { "\($0.x):\($0.z)" }).count == 16)
        #expect(layout.assignments.values.allSatisfy { abs($0.x)<=6.651 && abs($0.z)>=1.3999 })
        let oldWidth=layout.halfWidth;layout.register(["a"]);#expect(layout.halfWidth == oldWidth)
    }
    private func team(_ agents: [SpatialAgent]) -> SpatialTeam {
        let session = Session(id: "c", provider: .codex, url: nil, sessionID: "c", title: "Offline support", project: "/tmp/shared-office",
                              modified: Date(), bytes: 0, archived: false, parentID: nil, classification: .conversation)
        return SpatialTeam(projectID: "p", session: session, agents: agents)
    }
    @Test func completionRetentionHasNoTimeLimitAndPreservesUncertainty() {
        let now = Date(timeIntervalSince1970: 20_000)
        let recent = agent("recent", status: .done, at: now.addingTimeInterval(-1799))
        let expired = agent("old", status: .done, at: now.addingTimeInterval(-1800))
        let unknownCompletion = agent("unknown", status: .done)
        let stale = agent("stale", freshness: .lastKnown)
        let waiting = agent("wait", status: .waiting)
        let failed = agent("failure", status: .failed)
        let agents = [recent,expired,unknownCompletion,stale,waiting,failed,recent]
        let roster = OfficeRoster(teams: [team(agents)], now: now)
        #expect(Set(roster.occupants.map(\.id)) == Set([recent,expired,unknownCompletion,stale,waiting,failed].map(\.id)))
        #expect(roster.occupants.first { $0.id == stale.id }?.agent.fresh == false)
        #expect(OfficeRoster(teams: [team(agents)], now: now, including: expired.id).occupants.contains { $0.id == expired.id })
        #expect(OfficeRoster(teams: [team(agents)], now: now, conversation: "c").occupants.count == 6)
        #expect(roster.occupants.allSatisfy { $0.destination.expanded && $0.destination.officeReturn == .project("p") })
    }
    @Test func sharedFloorRetainsNodesAcrossHomeAndStateChanges() throws {
        #expect(OfficeFurnitureAssets.lowAvatar != nil)
        _ = try OfficeFurnitureAssets.low.get()
        let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let agents = (0..<64).map { agent("agent-\($0)", status: $0 % 4 == 0 ? .waiting : .working) }
        var world = SpatialWorld(projects: [.init(id: "p", name: "Shared office", teams: [team(agents)])])
        view.apply(world: world, focus: .project("p"), active: true, reducedMotion: true, reset: 0)
        let visibleID = try #require(view.officeWorkstations.keys.sorted().first)
        let station = try #require(view.officeWorkstations[visibleID])
        #expect(view.officeWorkstations.count == 16)
        #expect(station.animating == false)
        #expect(view.scene?.rootNode.childNodes.flatMap(\.childNodes).filter { $0.name?.hasPrefix("sharedFloor:") == true }.count == 1)
        view.apply(world: world, focus: .portfolio, active: false, reducedMotion: false, reset: 0)
        #expect(view.officeWorkstations[visibleID] === station)
        #expect(!view.isPlaying)
        world.projects[0].teams[0].agents.reverse()
        view.apply(world: world, focus: .project("p"), active: true, reducedMotion: true, reset: 0)
        #expect(view.officeWorkstations[visibleID] === station)
        #expect(view.officeWorkstations.values.allSatisfy { !$0.root.isHidden })
        let tiff = try #require(view.snapshot().tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-shared-office-64.png"))
        view.suspend()
        #expect(view.officeWorkstations.values.allSatisfy { !$0.animating })
    }

    @Test func emptyOfficeHasFurnitureAndFillsReservedSeatsWithoutMovingThem() throws {
        let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        var world = SpatialWorld(projects: [.init(id: "p", name: "Empty office", teams: [])])
        view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        #expect(view.officeWorkstations.isEmpty)
        let arcade = try #require(view.scene?.rootNode.childNode(withName: "officeArcade", recursively: true))
        #expect(abs(Double(arcade.worldPosition.z) - OfficeBakedLayout.transforms["officeArcade"]!.z) < 0.001)
        #expect(arcade.worldPosition.x > 8 && arcade.worldPosition.x < 9.36)
        #expect(abs(arcade.boundingBox.max.y - arcade.boundingBox.min.y - 1.9) < 0.01)
        let pinball = try #require(view.scene?.rootNode.childNode(withName: "officePinball", recursively: true))
        #expect(abs(Double(pinball.worldPosition.z) - OfficeBakedLayout.transforms["officePinball"]!.z) < 0.001)
        #expect(abs(pinball.boundingBox.max.y - pinball.boundingBox.min.y - 1.9) < 0.01)
        #expect(abs(pinball.worldPosition.x + pinball.boundingBox.max.x - 9.35) < 0.01)
        #expect(pinball.worldPosition.z + pinball.boundingBox.min.z > arcade.worldPosition.z + arcade.boundingBox.max.z + 0.2)
        #expect(view.scene?.rootNode.childNode(withName: "officeLeisureArea", recursively: true) == nil)
        #expect(view.emptyOfficeDesks.count == SharedOfficeLayout.minimumDeskCount)
        #expect(view.pose.elevation < 0.6)
        let reserved = try #require(view.emptyOfficeDesks[0]).root.position
        let tiff = try #require(view.snapshot().tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-empty-office.png"))
        let overview = view.pose
        view.move(to: SpatialCameraPose(x: 0, y: 0, z: 0, scale: 2.5, yaw: -.pi / 4, elevation: .pi / 3), animated: false)
        let closeTiff = try #require(view.snapshot().tiffRepresentation)
        let closeBitmap = try #require(NSBitmapImageRep(data: closeTiff))
        try #require(closeBitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-floor-seams.png"))
        view.move(to: overview, animated: false)
        let worker = agent("first")
        world.projects[0].teams = [team([worker])]
        view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        let station = try #require(view.officeWorkstations[worker.id])
        #expect(station.root.position.x == reserved.x && station.root.position.z == reserved.z)
        #expect(view.emptyOfficeDesks.count == SharedOfficeLayout.minimumDeskCount - 1)
        world.projects[0].teams = []
        view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        #expect(view.emptyOfficeDesks.count == SharedOfficeLayout.minimumDeskCount)
        #expect(view.emptyOfficeDesks[0]?.root.position.x == reserved.x)
    }

    @Test func idleAgentsReleaseDesksAndRestoreBoundedAssignments() throws {
        var layout = SharedOfficeLayout()
        let workers = (0..<64).map { OfficeOccupant(agent: agent("worker-\($0)", status: .done), assignment: "Finished") }
        layout.place(workers)
        #expect(layout.standing.count == 64)
        #expect(layout.leisureSlots.count == 18)
        #expect(layout.assignments.isEmpty)
        #expect(layout.desks.count == 16)
        let original = layout.leisureSlots
        let resumedID = try #require(original.keys.sorted().first)
        let resumed = workers.map { person -> OfficeOccupant in
            guard person.id == resumedID else { return person }
            var next = person.agent; next.value.status = .working; next.value.reportedStatus = "working"
            return .init(agent: next, assignment: "Resumed")
        }
        layout.place(resumed)
        #expect(layout.assignments[resumedID] != nil)
        #expect(layout.leisureSlots[resumedID] == nil)
        for (id,slot) in original where id != resumedID { #expect(layout.leisureSlots[id] == slot) }
        let restored = try JSONDecoder().decode(SharedOfficeLayout.Saved.self, from: JSONEncoder().encode(layout.saved))
        #expect(SharedOfficeLayout(saved: restored).saved.deskSlots == layout.saved.deskSlots)
        #expect(SharedOfficeLayout(saved: restored).leisureSlots == layout.leisureSlots)
    }

    @Test func staleWaitingFailureAndReservedFurniture() throws {
        var layout = SharedOfficeLayout()
        let working = OfficeOccupant(agent: agent("worker"), assignment: "Work")
        layout.place([working])
        let desk = try #require(layout.assignments[working.id])
        let stale = OfficeOccupant(agent: agent("worker", status: .done, freshness: .lastKnown), assignment: "Work")
        layout.place([stale]); #expect(!layout.standing.contains(working.id))
        let done = OfficeOccupant(agent: agent("worker", status: .done), assignment: "Work")
        layout.place([done]); #expect(layout.standing.contains(working.id))
        let station = OfficeWorkstation(id: working.id)
        let chair = station.chair
        station.place(desk: desk, standingAt: layout.standingPosition(working.id), animated: false)
        station.update(done, selected: true, reduced: true, active: false, distant: false)
        #expect(station.standing && station.chair === chair)
        #expect(station.avatar.root.position.y == 0)
        #expect(abs(station.person.worldPosition.x + 3) < 0.001 && abs(station.person.worldPosition.z - 8) < 0.001)
        for status in [WorkspaceAgentStatus.waiting, .failed, .working] {
            layout.place([OfficeOccupant(agent: agent("worker", status: status), assignment: "Work")])
            #expect(!layout.standing.contains(working.id))
        }
        station.place(desk: desk, standingAt: nil, animated: false)
        #expect(!station.standing && station.avatar.root.position.y > 0.23)
        #expect(station.chair === chair)
    }

    @Test func finishedOfficeSnapshots() throws {
        for count in [4, 64] {
            let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
            let agents = (0..<count).map { agent("finished-\($0)", status: .done) }
            let world = SpatialWorld(projects: [.init(id: "p", name: "Finished office", teams: [team(agents)])])
            view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
            #expect(view.officeWorkstations.count == min(count,18))
            #expect(view.officeWorkstations.values.allSatisfy { $0.standing })
            let original = view.pose
            for angle in 0..<4 {
                var pose = original; pose.yaw += Double(angle) * .pi / 2
                // Fit the entire expanded floor for fixture inspection.
                pose.scale *= 1.5
                view.move(to: pose, animated: false)
                let image = try #require(view.snapshot().tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: image))
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-standing-\(count)-\(angle).png"))
            }
            view.suspend()
        }
    }

}
