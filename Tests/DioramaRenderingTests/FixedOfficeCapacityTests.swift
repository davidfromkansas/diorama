import AppKit
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct FixedOfficeCapacityTests {
    private func occupant(_ index: Int, status: WorkspaceAgentStatus = .working, time: Double? = nil) -> OfficeOccupant {
        var value = WorkspaceAgent(id: String(format: "a%03d", index), name: "Agent \(index)", provider: "Codex", task: "Capacity fixture", action: "Activity", status: status, reportedStatus: status.rawValue, freshness: .live, observedAt: nil)
        value.meaningfulUpdatedAt = time.map { Date(timeIntervalSince1970: $0) }
        value.meaningfulEventID = "event-\(index)-\(time ?? 0)"
        return .init(agent: .init(projectID: "fixed", conversationID: "c", value: value), assignment: "Fixture")
    }
    private func changed(_ occupant: OfficeOccupant, _ edit: (inout WorkspaceAgent) -> Void) -> OfficeOccupant {
        var agent = occupant.agent; edit(&agent.value)
        return .init(agent: agent, assignment: occupant.assignment)
    }
    @Test func boundariesAndFixedBounds() {
        for count in [0,16,17,18,19,64] {
            var layout = SharedOfficeLayout()
            let desks = layout.desks
            layout.place((0..<count).map { occupant($0) })
            #expect(layout.assignments.count == min(count,16))
            #expect(layout.desks == desks)
            #expect(layout.floorMinZ == -5.4 && layout.floorMaxZ == 23.1)
            layout.place((0..<count).map { occupant($0,status:.done) })
            #expect(layout.leisureSlots.count == min(count,18))
            #expect(layout.assignments.isEmpty)
            #expect(layout.desks == desks)
            #expect(layout.floorMinZ == -5.4 && layout.floorMaxZ == 23.1)
        }
    }
    @Test func priorityRecencyReplayAndStableSurvivors() {
        var layout = SharedOfficeLayout()
        var roster = (0..<20).map { occupant($0,time:Double($0)) }
        roster[0] = changed(roster[0]) { $0.status = .failed }
        roster[1] = changed(roster[1]) { $0.status = .waiting; $0.attentionReason = .approval }
        layout.place(roster)
        #expect(layout.assignments[roster[0].id] != nil)
        #expect(layout.assignments[roster[1].id] != nil)
        #expect(layout.assignments[roster[19].id] != nil)
        #expect(layout.assignments[roster[2].id] == nil)
        roster = (0..<20).map { occupant($0,status:.done,time:Double($0+100)) }
        layout.place(roster)
        #expect(layout.leisureSlots[roster[0].id] == nil)
        let original = layout.leisureSlots
        let previous = roster[0]
        roster[0] = occupant(0,status:.done,time:500)
        layout.place(roster)
        #expect(layout.leisureSlots[roster[0].id] != nil)
        #expect(layout.leisureSlots[roster[2].id] == nil)
        for (id, slot) in original where id != roster[2].id { #expect(layout.leisureSlots[id] == slot) }
        let selected = layout.leisureSlots
        roster[0] = previous
        layout.place(roster,now:Date(timeIntervalSince1970:10000))
        #expect(layout.leisureSlots == selected)
        roster[3] = changed(roster[3]) { $0.task = "A renamed task"; $0.observedAt = Date() }
        layout.place(roster,now:Date(timeIntervalSince1970:20000))
        #expect(layout.leisureSlots == selected)
    }
    @Test func staleUpdatesAndRestartPreservePlacement() throws {
        var layout = SharedOfficeLayout()
        var roster = (0..<40).map { occupant($0,status:$0<20 ? .working : .done,time:Double($0)) }
        layout.place(roster)
        let original = layout.saved
        for i in roster.indices {
            roster[i] = changed(roster[i]) { $0.status = .unknown; $0.freshness = .unavailable; $0.meaningfulUpdatedAt = Date() }
        }
        layout.place(roster)
        #expect(layout.assignments.mapValues(\.slot) == original.deskSlots)
        #expect(layout.leisureSlots == original.leisureSlots)
        let saved = try JSONDecoder().decode(SharedOfficeLayout.Saved.self,from:JSONEncoder().encode(original))
        var restored = SharedOfficeLayout(saved:saved)
        restored.place((0..<40).reversed().map { occupant($0,status:$0<20 ? .working : .done,time:Double($0)) })
        #expect(restored.assignments.mapValues(\.slot) == original.deskSlots)
        #expect(restored.leisureSlots == original.leisureSlots)
    }
    @Test func deskReuseAndLegacyMigration() throws {
        var layout = SharedOfficeLayout()
        let first = occupant(0)
        layout.place([first])
        let old = layout.assignments[first.id]
        layout.place([occupant(0,status:.done)])
        #expect(layout.assignments.isEmpty)
        layout.place([occupant(0),occupant(1)])
        #expect(layout.assignments[first.id] == old)
        #expect(Set(layout.assignments.values.map(\.slot)).count == 2)
        let ids = (0..<64).map { occupant($0).id }
        let legacy = SharedOfficeLayout.Saved(order:ids,standingSlots:[:],standing:[],knownPlacements:Set(ids),centralRadius:100)
        var migrated = SharedOfficeLayout(saved:legacy)
        migrated.place((0..<64).map { occupant($0) })
        #expect(migrated.assignments.count == 16 && migrated.desks.count == 16)
        #expect(migrated.floorMaxZ == 23.1)
    }
    @Test func hiddenAgentsOpenWithoutSpawningOrChangingCamera() throws {
        let roster = (0..<64).map { occupant($0,status:$0<32 ? .working : .done,time:Double($0)) }
        let session = Session(id:"c",provider:.codex,url:nil,sessionID:"c",title:"Fixture",project:"/tmp/fixed",modified:Date(),bytes:0,archived:false,parentID:nil,classification:.conversation)
        let team = SpatialTeam(projectID:"fixed",session:session,agents:roster.map(\.agent))
        let world = SpatialWorld(projects:[.init(id:"fixed",name:"Fixed",teams:[team])])
        let view = SpatialSceneView(); view.frame = NSRect(x:0,y:0,width:1200,height:800)
        view.apply(world:world,focus:.project("fixed"),active:false,reducedMotion:true,reset:0)
        defer { view.tearDown() }
        #expect(view.officeWorkstations.count == 34)
        #expect(view.officeWorkstations.values.filter(\.showsFurniture).count == 16)
        #expect(view.emptyOfficeDesks.isEmpty)
        #expect(OfficeRoster(teams:[team],now:Date()).occupants.count == 64)
        let hidden = try #require(roster.first { view.officeWorkstations[$0.id] == nil })
        let camera = view.pose
        view.apply(world:world,focus:hidden.destination,active:false,reducedMotion:true,reset:0)
        #expect(view.pose == camera)
        #expect(view.officeWorkstations.count == 34 && view.officeWorkstations[hidden.id] == nil)
        #expect(view.officeWorkstations.values.allSatisfy { $0.leisureMotion?.target?.kind != .conversation })
        let tiff = try #require(view.snapshot().tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data:tiff))
        try #require(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/diorama-fixed-64.png"))
    }
    @Test func noOverflowAnchorsAndBlockedLeisureIsHidden() throws {
        let furniture = OfficeLoungeAssets.make().childNodes.flatMap { $0.name == "officeTVLounge" ? $0.childNodes : [$0] }
        let anchors = OfficeLeisureAnchors.targets(furniture:furniture,overflow:0)
        #expect(anchors.count == 18 && anchors.allSatisfy { $0.kind != .conversation })
        var nav = WorkspaceCapybaraNavigation()
        nav.obstacles = [.init(min:SIMD2(-100,-100),max:SIMD2(100,100))]
        #expect(anchors.allSatisfy { OfficeLeisureAnchors.accessible($0,navigation:nav) == nil })
    }

    @Test func outOfBoundsEditsAreRecoveredAndClamped() throws {
        let suite = "fixed-office-"+UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName:suite)); defer { defaults.removePersistentDomain(forName:suite) }
        let original = OfficeEditTransform(x:80,z:90,rotationRadians:0.4)
        defaults.set(try JSONEncoder().encode(["p":["fixture":original]]),forKey:"officeLayoutDraft.v1")
        let node = SCNNode(geometry:SCNBox(width:2,height:1,length:4,chamferRadius:0))
        let item = OfficeLayoutEditor.Item(id:"fixture",label:"Fixture",node:node,ignored:nil,width:2,depth:4) { value in
            node.position = SCNVector3(value.x,0,value.z); node.eulerAngles.y = value.rotationRadians
        }
        let editor = OfficeLayoutEditor(); editor.defaults = defaults
        editor.configure(project:"p",items:[item],floor:.init(minX:-10,maxX:10,minZ:-5.4,maxZ:23.1))
        let bounded = try #require(editor.drafts["p"]?["fixture"])
        #expect(bounded.x < 9 && bounded.z < 23)
        #expect(bounded.rotationRadians == original.rotationRadians)
        let recovery = try JSONDecoder().decode([String:[String:OfficeEditTransform]].self,from:#require(defaults.data(forKey:"officeLayoutDraft.fixedBoundsBackup.v1")))
        #expect(recovery["p"]?["fixture"] == original)
        editor.toggle(); editor.choose("fixture"); editor.rotate(clockwise:false)
        for x in [-1.0,1.0] { for z in [-2.0,2.0] {
            let p = node.convertPosition(SCNVector3(x,0,z),to:nil)
            #expect(p.x <= 9.351 && p.x >= -9.901 && p.z <= 23.001 && p.z >= -4.751)
        } }
    }
}
