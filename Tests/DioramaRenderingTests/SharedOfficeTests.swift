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
    @Test func deskExpansionNeverMovesExistingAssignmentsOrUsesConversationGrouping() {
        var layout=SharedOfficeLayout();layout.register(["a","b","c","d"])
        let original=layout.assignments
        layout.register((0..<200).map { "worker-\($0)" })
        for (id,desk) in original { #expect(layout.assignments[id] == desk) }
        #expect(Set(layout.assignments.values.map { "\($0.x):\($0.z)" }).count == 204)
        #expect(layout.assignments.values.allSatisfy { abs($0.x)>=2.3 && abs($0.z)>=2.5 })
        let oldWidth=layout.halfWidth;layout.register(["a"]);#expect(layout.halfWidth == oldWidth)
    }
    private func team(_ agents: [SpatialAgent]) -> SpatialTeam {
        let session = Session(id: "c", provider: .codex, url: nil, sessionID: "c", title: "Offline support", project: "/tmp/shared-office",
                              modified: Date(), bytes: 0, archived: false, parentID: nil, classification: .conversation)
        return SpatialTeam(projectID: "p", session: session, agents: agents)
    }
    @Test func completionRetentionUsesReportedTimeAndPreservesUncertainty() {
        let now = Date(timeIntervalSince1970: 20_000)
        let recent = agent("recent", status: .done, at: now.addingTimeInterval(-1799))
        let expired = agent("old", status: .done, at: now.addingTimeInterval(-1800))
        let unknownCompletion = agent("unknown", status: .done)
        let stale = agent("stale", freshness: .lastKnown)
        let waiting = agent("wait", status: .waiting)
        let failed = agent("failure", status: .failed)
        let agents = [recent,expired,unknownCompletion,stale,waiting,failed,recent]
        let roster = OfficeRoster(teams: [team(agents)], now: now)
        #expect(Set(roster.occupants.map(\.id)) == Set([recent,stale,waiting,failed].map(\.id)))
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
        let station = try #require(view.officeWorkstations[agents[0].id])
        #expect(view.officeWorkstations.count == 64)
        #expect(station.animating == false)
        #expect(view.scene?.rootNode.childNodes.flatMap(\.childNodes).filter { $0.name?.hasPrefix("sharedFloor:") == true }.count == 1)
        view.apply(world: world, focus: .portfolio, active: false, reducedMotion: false, reset: 0)
        #expect(view.officeWorkstations[agents[0].id] === station)
        #expect(!view.isPlaying)
        world.projects[0].teams[0].agents.reverse()
        view.apply(world: world, focus: .project("p"), active: true, reducedMotion: true, reset: 0)
        #expect(view.officeWorkstations[agents[0].id] === station)
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

}
