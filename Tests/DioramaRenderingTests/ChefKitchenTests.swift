import AppKit
import DioramaCore
import SceneKit
import Testing
import simd
@testable import DioramaApp

@MainActor struct ChefKitchenTests {
    private func agent(_ id: String, _ status: WorkspaceAgentStatus, tool: String = "", detail: String = "", attention: WorkspaceAttentionReason = .other) -> SpatialAgent {
        var value = WorkspaceAgent(id: id, name: "Agent \(id)", provider: "Claude", task: "Task", action: "", status: status, reportedStatus: status.rawValue, freshness: .live)
        value.latestTool = tool; value.latestToolDetail = detail; value.attentionReason = attention
        value.completionKey = "turn-1"
        return SpatialAgent(projectID: "p", conversationID: "c", value: value)
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
        #expect(assets.rig.clips.count == 22)
        #expect(Set(assets.manifest.clips.keys) == Set(assets.rig.clips.keys))
        let chef = assets.rig.makeInstance()
        #expect(chef.nodes.contains { $0.skinner?.bones.count == 26 })
        for socket in ["socket_hand.L", "socket_hand.R", "socket_carry"] { #expect(chef.bone(socket) != nil) }
        for prop in ChefProp.allCases {
            #expect(assets.props[prop.node] != nil)
            #expect(assets.manifest.attach[prop.node]?[prop.fitClip] != nil)
        }
        #expect(assets.props.count == 8)
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

    @Test func agentStatesMapToStations() {
        #expect(KitchenLayout.work(for: agent("a", .working, tool: "Read").value).area == "context")
        #expect(KitchenLayout.work(for: agent("a", .working, tool: "Edit").value) == .init(area: "prep", loop: "working_chop", hand: .knife))
        #expect(KitchenLayout.work(for: agent("a", .working, tool: "Bash", detail: "make").value).area == "build")
        #expect(KitchenLayout.work(for: agent("a", .working, tool: "Bash", detail: "swift test").value).hand == .spoon)
        #expect(KitchenLayout.work(for: agent("a", .waiting, attention: .approval).value).area == "attention")
        #expect(KitchenLayout.work(for: agent("a", .done).value).deliversPlate)
        #expect(KitchenLayout.work(for: agent("a", .unknown).value).area == nil)
        #expect(KitchenLayout.work(for: agent("a", .ready).value).area == "home")
    }

    @Test func slotsStayOnWalkableFloorAndAreKeptPerArea() {
        let navigation = KitchenLayout.chefNavigation, table = KitchenLayout.chefSlots
        for area in KitchenLayout.areas.map(\.id) + ["home"] {
            let slots = table[area] ?? []
            #expect(!slots.isEmpty, "\(area) has no slots")
            for slot in slots { #expect(navigation.isFree(slot.stand), "\(slot.id) is blocked") }
        }
        let first = KitchenLayout.assignSlots([("a", "prep"), ("b", "prep")], previous: [:])
        #expect(first["a"] != first["b"])
        let second = KitchenLayout.assignSlots([("b", "prep"), ("a", "prep")], previous: first)
        #expect(second == first)
        // A full area queues extra chefs behind its slots instead of stacking them.
        let crowd = (0..<8).map { ("c\($0)", Optional("test")) }
        let crowded = KitchenLayout.assignSlots(crowd, previous: [:])
        #expect(Set(crowded.values.map(\.stand.x)).count + Set(crowded.values.map(\.stand.y)).count > 2)
    }

    @Test func workingChefWalksAroundFixturesGrabsKnifeAndChops() throws {
        let d = try director(), table = KitchenLayout.chefSlots
        let home = try #require(table["home"]?.first), prep = try #require(table["prep"]?.first)
        d.place(home.stand)
        d.setIntent(KitchenLayout.intent(for: agent("a", .working, tool: "Edit").value, at: prep, pickup: nil, restored: false))
        var maxBlocked = 0
        for _ in 0..<(60 * 12) {
            d.update(1 / 60)
            if !d.navigation.obstacles.allSatisfy({ !$0.contains(d.position) }) { maxBlocked += 1 }
        }
        #expect(maxBlocked == 0)
        #expect(simd_distance(d.position, prep.stand) < 0.01)
        #expect(d.held == [.knife])
        #expect(d.clip.name == "working_chop")
        #expect(d.settled)
    }

    @Test func finishedTurnDeliversPlateToReviewOnce() throws {
        let d = try director(), table = KitchenLayout.chefSlots
        let prep = try #require(table["prep"]?.first), review = try #require(table["review"]?.first), test = try #require(table["test"]?.first)
        d.place(prep.stand, heading: prep.facing)
        let done = KitchenLayout.intent(for: agent("a", .done).value, at: review, pickup: test, restored: false)
        d.setIntent(done)
        #expect(d.stepNames.first == "goto:test")
        var carried = false
        for _ in 0..<(60 * 25) { d.update(1 / 60); carried = carried || d.held.contains(.plate) }
        #expect(carried)
        #expect(d.held.isEmpty)
        #expect(d.placedPlate == review)
        #expect(d.clip.name == "wait_review")
        // Re-delivering the same state never replays the delivery.
        d.setIntent(KitchenLayout.intent(for: agent("a", .working, tool: "Read").value, at: table["context"]?.first, pickup: nil, restored: false))
        d.setIntent(done)
        #expect(!d.stepNames.contains("once:pickup") && !d.stepNames.contains("once:present_review"))
    }

    @Test func restoredAndReducedMotionStatesSkipGestures() throws {
        let d = try director(), table = KitchenLayout.chefSlots
        let attention = try #require(table["attention"]?.first)
        d.place(attention.stand, heading: attention.facing)
        d.setIntent(KitchenLayout.intent(for: agent("a", .waiting, attention: .approval).value, at: attention, pickup: nil, restored: true))
        #expect(!d.stepNames.contains("once:request_input"))
        run(d, seconds: 1)
        #expect(d.clip.name == "wait_input")
        let reduced = try director(); reduced.reducedMotion = true
        reduced.place(attention.stand, heading: attention.facing)
        reduced.setIntent(KitchenLayout.intent(for: agent("b", .failed).value, at: attention, pickup: nil, restored: false))
        #expect(!reduced.stepNames.contains("once:error_react"))
        let live = try director()
        live.place(attention.stand, heading: attention.facing)
        live.setIntent(KitchenLayout.intent(for: agent("c", .failed).value, at: attention, pickup: nil, restored: false))
        #expect(live.stepNames.contains("once:error_react"))
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
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let agents = [agent("plan", .working, tool: "TodoWrite"), agent("read", .working, tool: "Read"), agent("edit", .working, tool: "Edit"),
                      agent("cmd", .working, tool: "Bash", detail: "make"), agent("test", .working, tool: "Bash", detail: "swift test"),
                      agent("ask", .waiting, attention: .approval), agent("done", .done), agent("idle", .ready)]
        view.apply(agents: agents, active: false, reducedMotion: false)
        for chef in view.chefs.values { for _ in 0..<30 { chef.update(1 / 30) } }
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        let tiff = try #require(view.snapshot().tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-kitchen-chefs.png"))
    }
}
