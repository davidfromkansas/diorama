import AppKit
import DioramaCore
import SceneKit
import Testing
import simd
@testable import DioramaApp

@MainActor struct ChefKitchenTests {
    private func agent(_ id: String, _ status: WorkspaceAgentStatus, tool: String = "", detail: String = "", attention: WorkspaceAttentionReason = .other,
                       edits: Bool = false, freshness: WorkspaceAgentFreshness = .live, conversation: String = "c", project: String = "p") -> SpatialAgent {
        var value = WorkspaceAgent(id: id, name: "Agent \(id)", provider: "Claude", task: "Task", action: "", status: status, reportedStatus: status.rawValue, freshness: freshness)
        value.latestTool = tool; value.latestToolDetail = detail; value.attentionReason = attention; value.turnHasEdits = edits
        value.completionKey = "turn-1"
        return SpatialAgent(projectID: project, conversationID: conversation, value: value)
    }
    private func director() throws -> ChefDirector {
        let assets = try ChefAssets.shared.get()
        return ChefDirector(clips: assets.manifest.clips, unit: KitchenLayout.chefScale, navigation: KitchenLayout.chefNavigation)
    }
    private func run(_ director: ChefDirector, seconds: Float, fps: Float = 60) {
        for _ in 0..<Int(seconds * fps) { director.update(1 / fps) }
    }

    @Test func chefAssetsLoadWithSocketsClipsAndProps() throws {
        let assets = try ChefAssets.shared.get()
        #expect(assets.rig.clips.count == 30)
        #expect(Set(assets.manifest.clips.keys) == Set(assets.rig.clips.keys))
        let chef = assets.rig.makeInstance()
        #expect(chef.nodes.contains { $0.skinner?.bones.count == 26 })
        for socket in ["socket_hand.L", "socket_hand.R", "socket_carry"] { #expect(chef.bone(socket) != nil) }
        for prop in ChefProp.allCases {
            #expect(assets.props[prop.node] != nil)
            #expect(assets.manifest.attach[prop.node]?[prop.fitClip] != nil)
        }
        #expect(assets.props.count == 11)
        #expect(assets.manifest.stations.counterTop == KitchenLayout.chefCounterTop)
        #expect(assets.manifest.stations.counterFrontFromRoot == KitchenLayout.chefCounterFront)
        #expect(assets.manifest.height == KitchenLayout.chefHeight)
        // The generalized reader still accepts the capybara.
        #expect(try WorkspaceCapybaraAsset.shared.get().makeInstance().nodes.contains { $0.skinner?.bones.count == 25 })
    }

    @Test func sampledPosesMatchKeyframesExactly() throws {
        let rig = try ChefAssets.shared.get().rig
        let clip = try #require(rig.clips["working_chop"])
        let track = try #require(clip.tracks.first { $0.path == "rotation" && $0.times.count > 4 })
        for key in [0, 3, track.times.count - 2] {
            let pose = rig.pose("working_chop", time: track.times[key])
            let v = track.values[key]
            let expected = simd_quatf(ix: v[0], iy: v[1], iz: v[2], r: v[3])
            #expect(abs(simd_dot(pose[track.node].rotation.vector, expected.vector)) > 0.99999)
        }
        // Constant unit-scale tracks are dropped at load.
        #expect(!clip.tracks.contains { $0.path == "scale" })
    }

    @Test func lifecycleMapsToStations() {
        func area(_ a: SpatialAgent) -> String? { KitchenLayout.work(for: a.value).area }
        // Before the first edit everything is prep, except tests.
        #expect(KitchenLayout.work(for: agent("a", .working, tool: "Read").value) == .init(area: "prep", loop: "researching_book", hand: .book))
        #expect(KitchenLayout.work(for: agent("a", .working, tool: "TaskCreate").value).hand == .card)
        #expect(area(agent("a", .working, tool: "Bash", detail: "make")) == "prep")
        #expect(area(agent("a", .working, tool: "Bash", detail: "swift test")) == "tasting")
        // After it: editing at the island, commands at the stove, reads keep chopping.
        #expect(KitchenLayout.work(for: agent("a", .working, tool: "Edit", edits: true).value) == .init(area: "cooking", loop: "working_chop", hand: .knife))
        #expect(area(agent("a", .working, tool: "Read", edits: true)) == "cooking")
        #expect(area(agent("a", .working, tool: "Bash", detail: "make", edits: true)) == "stove")
        #expect(area(agent("a", .working, tool: "Bash", detail: "npm test", edits: true)) == "tasting")
        #expect(area(agent("a", .waiting, attention: .approval)) == "bell")
        #expect(KitchenLayout.work(for: agent("a", .waiting, attention: .approval).value).oneShot == "request_input")
        #expect(KitchenLayout.work(for: agent("a", .waiting).value).oneShot == "blocked_react")
        let rest = KitchenLayout.work(for: agent("a", .done, freshness: .lastKnown).value)
        #expect(rest.oneShot == "sit_down" && rest.loop.hasPrefix("sit_") && (rest.loop == "sit_sip") == (rest.hand == .mug))
        #expect(area(agent("a", .failed)) == "bell")
        #expect(KitchenLayout.work(for: agent("a", .done).value).deliversPlate)
        #expect(area(agent("a", .done)) == "serving")
        #expect(area(agent("a", .done, freshness: .lastKnown)) == "break")
        #expect(area(agent("a", .working, tool: "Edit", freshness: .lastKnown)) == "break")
        #expect(area(agent("a", .stopped)) == "break")
        #expect(area(agent("a", .ready, freshness: .ready)) == "order")
        #expect(area(agent("a", .unknown)) == nil)
        #expect(KitchenLayout.work(for: agent("a", .waiting).value).urgent)
        #expect(!KitchenLayout.work(for: agent("a", .working, tool: "Edit", edits: true).value).urgent)
    }

    @Test func roomFitsTenChefsPerStationOnWalkableFloor() {
        let navigation = KitchenLayout.chefNavigation, table = KitchenLayout.chefSlots
        #expect(KitchenLayout.areas.count == 9)
        for area in KitchenLayout.areas {
            #expect(KitchenLayout.floor.contains(area.footprint), "\(area.id) leaves the floor")
            let slots = table[area.id] ?? []
            #expect(slots.count >= area.spots, "\(area.id) has \(slots.count) of \(area.spots) spots")
            for slot in slots { #expect(navigation.isFree(slot.stand), "\(slot.id) is blocked") }
            // Ten chefs sent to one station get distinct, walkable places.
            let crowd = KitchenLayout.assignSlots((0..<10).map { ("c\($0)", Optional(area.id)) }, previous: [:])
            let stands = crowd.values.map(\.stand)
            for (i, a) in stands.enumerated() { for b in stands.dropFirst(i + 1) { #expect(simd_distance(a, b) > 0.5, "\(area.id) stacks chefs") } }
        }
        // Every station reaches every other one.
        let all = KitchenLayout.areas.compactMap { table[$0.id]?.first }
        for a in all { for b in all where a.id != b.id { #expect(navigation.route(from: a.stand, to: b.stand) != nil, "\(a.id) → \(b.id)") } }
        let first = KitchenLayout.assignSlots([("a", "cooking"), ("b", "cooking")], previous: [:])
        #expect(first["a"] != first["b"])
        #expect(KitchenLayout.assignSlots([("b", "cooking"), ("a", "cooking")], previous: first) == first)
    }

    @Test func workingChefWalksAroundFixturesGrabsKnifeAndChops() throws {
        let d = try director(), table = KitchenLayout.chefSlots
        let start = try #require(table["order"]?.first), island = try #require(table["cooking"]?.last)
        d.place(start.stand)
        d.setIntent(KitchenLayout.intent(for: agent("a", .working, tool: "Edit", edits: true).value, at: island, pickup: nil, restored: false))
        // Corners may graze the walking margin, but the chef's root never enters a fixture.
        let fixtures = KitchenLayout.areas.filter { $0.id != "elevator" }.map(\.footprint) + KitchenLayout.connectors + KitchenLayout.breakRoomWalls
        var blocked = 0
        for _ in 0..<(60 * 20) {
            d.update(1 / 60)
            if fixtures.contains(where: { $0.insetBy(dx: -0.1, dy: -0.1).contains(CGPoint(x: CGFloat(d.position.x), y: CGFloat(d.position.y))) }) { blocked += 1 }
        }
        #expect(blocked == 0)
        #expect(simd_distance(d.position, island.stand) < 0.01)
        #expect(d.held == [.knife])
        #expect(d.clip.name == "working_chop")
        #expect(d.settled)
    }

    @Test func finishedTurnCarriesPlateFromIslandToServingOnce() throws {
        let d = try director(), table = KitchenLayout.chefSlots
        let island = try #require(table["cooking"]?.first), serving = try #require(table["serving"]?.first)
        d.place(island.stand, heading: island.facing)
        let done = KitchenLayout.intent(for: agent("a", .done).value, at: serving, pickup: island, restored: false)
        d.setIntent(done)
        #expect(d.stepNames.first == "goto:cooking")
        var carried = false
        for _ in 0..<(60 * 30) { d.update(1 / 60); carried = carried || d.held.contains(.plate) }
        #expect(carried)
        #expect(d.held.isEmpty)
        #expect(d.placedPlate == serving)
        #expect(d.clip.name == "wait_review")
        d.setIntent(KitchenLayout.intent(for: agent("a", .working, tool: "Read").value, at: table["prep"]?.first, pickup: nil, restored: false))
        d.setIntent(done)
        #expect(!d.stepNames.contains("once:pickup") && !d.stepNames.contains("once:present_review"))
    }

    @Test func restoredAndReducedMotionStatesSkipGestures() throws {
        let d = try director(), table = KitchenLayout.chefSlots
        let bell = try #require(table["bell"]?.first)
        d.place(bell.stand, heading: bell.facing)
        d.setIntent(KitchenLayout.intent(for: agent("a", .waiting, attention: .approval).value, at: bell, pickup: nil, restored: true))
        #expect(!d.stepNames.contains("once:request_input"))
        run(d, seconds: 1)
        #expect(d.clip.name == "wait_input")
        let reduced = try director(); reduced.reducedMotion = true
        reduced.place(bell.stand, heading: bell.facing)
        reduced.setIntent(KitchenLayout.intent(for: agent("b", .failed).value, at: bell, pickup: nil, restored: false))
        #expect(!reduced.stepNames.contains("once:error_react"))
        let live = try director()
        live.place(bell.stand, heading: bell.facing)
        live.setIntent(KitchenLayout.intent(for: agent("c", .failed).value, at: bell, pickup: nil, restored: false))
        #expect(live.stepNames.contains("once:error_react"))
    }

    @Test func chefsStayAtLeastThreeSecondsButNeedsYouIsImmediate() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var clock = 100.0
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 30) { clock += 1 / 30; for chef in view.chefs.values { chef.update(1 / 30) }; view.pace(now: clock) }
        }
        view.apply(agents: [agent("a", .working, tool: "Edit", edits: true)], active: false, reducedMotion: false, now: clock)
        step(0.5)
        let chef = try #require(view.chefs.values.first)
        #expect(chef.director.intent?.station?.area == "cooking")
        // A quick command and a read within three seconds don't move the chef.
        view.apply(agents: [agent("a", .working, tool: "Bash", detail: "make", edits: true)], active: false, reducedMotion: false, now: clock)
        step(1)
        #expect(chef.director.intent?.station?.area == "cooking")
        view.apply(agents: [agent("a", .working, tool: "Bash", detail: "make", edits: true)], active: false, reducedMotion: false, now: clock)
        step(2.5)
        #expect(chef.director.intent?.station?.area == "stove")
        // Needing you moves it at once.
        view.apply(agents: [agent("a", .waiting, attention: .approval, edits: true)], active: false, reducedMotion: false, now: clock)
        step(0.1)
        #expect(chef.director.intent?.station?.area == "bell")
    }

    @Test func seatedChefsStandUpBeforeLeavingAndCelebrateAfterServing() throws {
        let d = try director(), table = KitchenLayout.chefSlots
        let seat = try #require(table["break"]?.first), serving = try #require(table["serving"]?.first)
        d.place(seat.stand, heading: seat.facing)
        d.setIntent(KitchenLayout.intent(for: agent("a", .done, freshness: .lastKnown).value, at: seat, pickup: nil, restored: true))
        run(d, seconds: 1)
        #expect(d.clip.name.hasPrefix("sit_"))
        d.setIntent(KitchenLayout.intent(for: agent("a", .working, tool: "Read").value, at: table["prep"]?.first, pickup: nil, restored: false))
        #expect(d.stepNames.first == "once:stand_up")
        var next = KitchenLayout.intent(for: agent("a", .done, freshness: .lastKnown).value, at: seat, pickup: nil, restored: false)
        next.prelude = "celebrate_done"
        let other = try director(); other.place(serving.stand, heading: serving.facing)
        other.setIntent(next)
        #expect(other.stepNames.first == "once:celebrate_done")
        other.reducedMotion = true
        let calm = try director(); calm.reducedMotion = true; calm.place(serving.stand); calm.setIntent(next)
        #expect(!calm.stepNames.contains("once:celebrate_done"))
    }

    @Test func burnersIgniteOnlyWhereChefsCook() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let cooks = [agent("a", .working, tool: "Bash", detail: "make", edits: true), agent("b", .working, tool: "Bash", detail: "npm run build", edits: true),
                     agent("c", .working, tool: "Edit", edits: true)]
        view.apply(agents: cooks, active: false, reducedMotion: false, now: 0)
        for chef in view.chefs.values { chef.update(0.1) }
        view.updateFlames()
        #expect(view.litBurners == ["stove#0", "stove#1"])
        view.apply(agents: [cooks[2]], active: false, reducedMotion: false, now: 1)
        view.updateFlames()
        #expect(view.litBurners.isEmpty)
    }

    @Test func firstAgentInAnOpenEmptyProjectArrivesByElevator() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.apply(agents: [], scope: "p", active: false, reducedMotion: false, now: 0)
        let first = agent("first", .working, tool: "Read")
        view.apply(agents: [first], scope: "p", active: false, reducedMotion: false, now: 1)
        #expect(view.chefs[first.id]?.director.intent?.key.hasPrefix("arrival") == true)
    }

    @Test func onlyNewAgentsArriveByElevator() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let old = agent("old", .working, tool: "Edit", edits: true), new = agent("new", .working, tool: "Read")
        view.apply(agents: [old], active: false, reducedMotion: false, now: 0)
        #expect(view.chefs[old.id]?.director.intent?.station?.area == "cooking")
        view.apply(agents: [old, new], active: false, reducedMotion: false, now: 1)
        let newcomer = try #require(view.chefs[new.id])
        let door = try #require(KitchenLayout.chefSlots["elevator"]?.first)
        #expect(simd_distance(newcomer.director.position, door.stand) < 0.01)
        #expect(newcomer.director.intent?.key.hasPrefix("arrival") == true)
        #expect(newcomer.director.stepNames.first == "once:arrive_wave")
        #expect(newcomer.director.intent?.loop == "read_ticket" && newcomer.director.intent?.hand == .ticket)
        var clock = 1.0
        for _ in 0..<(30 * 12) { clock += 1 / 30; newcomer.update(1 / 30); view.pace(now: clock) }
        #expect(newcomer.director.intent?.station?.area == "prep")
        // A new conversation in the same project arrives too; another project's agents are history.
        let sibling = agent("sibling", .working, tool: "Read", conversation: "d")
        view.apply(agents: [old, new, sibling], active: false, reducedMotion: false, now: clock)
        #expect(view.chefs[sibling.id]?.director.intent?.key.hasPrefix("arrival") == true)
        let other = agent("other", .working, tool: "Read", conversation: "e", project: "q")
        view.apply(agents: [other], active: false, reducedMotion: false, now: clock)
        #expect(view.chefs[other.id]?.director.intent?.key.hasPrefix("arrival") == false)
    }

    @Test func kitchenViewReconcilesChefsAndPlaysOnlyWhileActive() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.apply(agents: [], active: true, reducedMotion: false)
        #expect(view.chefs.isEmpty && !view.isPlaying)
        let agents = [agent("a", .working, tool: "Edit"), agent("b", .working, tool: "Read"), agent("c", .waiting, attention: .input)]
        view.apply(agents: agents, active: true, reducedMotion: false)
        #expect(view.chefs.count == 3)
        #expect(view.isPlaying)
        view.apply(agents: agents, active: false, reducedMotion: false)
        #expect(!view.isPlaying && !view.rendersContinuously)
        view.apply(agents: Array(agents.prefix(1)), active: false, reducedMotion: false)
        #expect(view.chefs.count == 1)
        let crowd = (0..<20).map { agent("x\($0)", .working, tool: "Edit") }
        view.apply(agents: crowd, active: false, reducedMotion: false)
        #expect(view.chefs.count == KitchenSceneView.maxChefs)
    }

    @Test func captureKitchenWithChefs() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_KITCHEN_CAPTURE"] == "1" else { return }
        func capture(_ agents: [SpatialAgent], _ name: String) throws {
            let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
            view.apply(agents: agents, active: false, reducedMotion: false)
            for chef in view.chefs.values { for _ in 0..<30 { chef.update(1 / 30) } }
            view.updateFlames()
            view.layoutSubtreeIfNeeded(); view.fitFloor()
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        }
        try capture([agent("plan", .working, tool: "TaskCreate"), agent("read", .working, tool: "Read"), agent("edit", .working, tool: "Edit", edits: true),
                     agent("cmd", .working, tool: "Bash", detail: "make", edits: true), agent("test", .working, tool: "Bash", detail: "swift test"),
                     agent("ask", .waiting, attention: .approval), agent("done", .done), agent("rest", .done, freshness: .lastKnown),
                     agent("new", .ready, freshness: .ready)], "diorama-kitchen-stages")
        try capture((0..<10).map { agent("e\($0)", .working, tool: "Edit", edits: true) }, "diorama-kitchen-ten-cooking")
        try capture((0..<10).map { agent("r\($0)", .done, freshness: .lastKnown) }, "diorama-kitchen-break-room")
        try capture((0..<6).map { agent("e\($0)", .working, tool: "Edit", edits: true) } + (0..<4).map { agent("s\($0)", .working, tool: "Bash", detail: "make", edits: true) }, "diorama-kitchen-islands")
    }
}
