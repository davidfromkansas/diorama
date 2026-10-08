import AppKit
@testable import DioramaCore
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
        #expect(assets.rig.clips.count == 34)
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

    @Test func chefLoadsQuicklyEnoughForTheMainThread() throws {
        let data = try Data(contentsOf: try #require(WorkspaceCapybaraAsset.resourceBundle.url(forResource: "chef-animated", withExtension: "glb", subdirectory: "Chef")))
        let start = Date()
        _ = try WorkspaceCapybaraAsset(data: data, spec: ChefAssets.spec)
        let seconds = Date().timeIntervalSince(start)
        print("chef rig load: \(Int(seconds * 1000)) ms")
        // Was ~6 s (quadratic JSON casting) in release builds; generous bound for debug test builds.
        #expect(seconds < 2)
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
        // Installs, builds and scripts cook at the stove even before the first edit.
        #expect(area(agent("a", .working, tool: "Bash", detail: "make")) == "stove")
        #expect(area(agent("a", .working, tool: "computer_use")) == "tasting")
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

    @Test func everyBundledDishLoadsNormalizedAndLight() throws {
        #expect(KitchenFood.ids == ["cheeseburger", "peking_duck", "pizza", "spaghetti"])
        for (id, dish) in KitchenFood.templates {
            var vertices = 0, textured = false
            dish.enumerateHierarchy { node, _ in
                guard let geometry = node.geometry else { return }
                vertices += geometry.sources(for: .vertex).first?.vectorCount ?? 0
                textured = textured || (geometry.sources(for: .texcoord).first != nil && geometry.materials.first?.diffuse.contents is NSImage)
            }
            let (low, high) = dish.boundingBox
            #expect(textured, "\(id) lost its textures")
            #expect(vertices > 0 && vertices <= 20_000, "\(id) has \(vertices) vertices")
            #expect(abs(max(high.x - low.x, high.z - low.z) - 1) < 0.02 && abs(low.y) < 0.01, "\(id) is not normalized")
        }
    }

    @Test func eachTaskGetsAStableDishWithEqualOdds() {
        let ids = KitchenFood.ids
        #expect(KitchenFood.dish(for: "codex:s1:turn-1") == KitchenFood.dish(for: "codex:s1:turn-1"))
        var counts: [String: Int] = [:]
        for i in 0..<4000 { counts[KitchenFood.dish(for: "codex:session-\(i % 97):turn-\(i)")!, default: 0] += 1 }
        for id in ids { #expect(abs(Double(counts[id, default: 0]) / 4000 - 1 / Double(ids.count)) < 0.03, "\(id): \(counts[id, default: 0])") }
        #expect(KitchenFood.dish(for: "x", among: []) == nil)
    }

    @Test func theTasksDishFollowsTheChefFromBoardToTastingToServing() throws {
        let assets = try ChefAssets.shared.get(), table = KitchenLayout.chefSlots
        let chef = ChefAvatar(id: "a", assets: assets, scale: KitchenLayout.chefScale, navigation: KitchenLayout.chefNavigation)
        chef.dish = "pizza"
        let board = try #require(table["cooking"]?.first), tasting = try #require(table["tasting"]?.first), serving = try #require(table["serving"]?.first)
        chef.director.place(board.stand, heading: board.facing)
        chef.director.setIntent(KitchenLayout.intent(for: agent("main", .working, tool: "Edit", edits: true).value, at: board, pickup: nil, restored: false))
        for _ in 0..<10 { chef.update(1 / 30) }
        #expect(chef.dishPlacement == "board")
        chef.director.place(tasting.stand, heading: tasting.facing)
        chef.director.setIntent(KitchenLayout.intent(for: agent("main", .working, tool: "Bash", detail: "npm test", edits: true).value, at: tasting, pickup: nil, restored: false))
        for _ in 0..<10 { chef.update(1 / 30) }
        #expect(chef.dishPlacement == "tasting")
        chef.director.setIntent(KitchenLayout.intent(for: agent("main", .done).value, at: serving, pickup: tasting, restored: false))
        var carried = false
        for _ in 0..<(30 * 30) { chef.update(1 / 30); carried = carried || chef.dishPlacement == "carry" }
        #expect(carried)
        #expect(chef.dishPlacement == "pass")
        // Without dishes the kitchen keeps the old plate prop.
        chef.dish = nil; chef.update(0)
        #expect(chef.dishPlacement == "none")
    }

    @Test func reviewStateKeepsFinishedWorkAtTheServingWindow() {
        let stale = agent("main", .done, freshness: .lastKnown).value
        #expect(KitchenLayout.work(for: stale).area == "break")
        #expect(KitchenLayout.work(for: stale, review: .awaiting).area == "serving")
        // Committed, merged, or marked done: accepted, so the chef celebrates and rests.
        for accepted in [KitchenReviews.State.committed, .merged, .approved] {
            let work = KitchenLayout.work(for: stale, review: accepted)
            #expect(work.area == "break" && work.prelude == "celebrate_done")
            #expect(KitchenLayout.intent(for: stale, at: nil, pickup: nil, restored: false, review: accepted).prelude == "celebrate_done")
            // Shown from history it just sits there.
            #expect(KitchenLayout.intent(for: stale, at: nil, pickup: nil, restored: true, review: accepted).prelude == nil)
        }
        // A pull request: CI tastes it, a problem rings the bell, a green one waits at the pass.
        #expect(KitchenLayout.work(for: stale, review: .checking).area == "tasting")
        #expect(KitchenLayout.work(for: stale, review: .needsFix).area == "bell")
        #expect(KitchenLayout.work(for: stale, review: .shipped).area == "serving")
        // With their own animations: a facepalm then head-scratching, a fist pump then hands on hips.
        #expect(KitchenLayout.work(for: stale, review: .needsFix).oneShot == "fix_react" && KitchenLayout.work(for: stale, review: .needsFix).loop == "fix_wait")
        #expect(KitchenLayout.work(for: stale, review: .shipped).oneShot == "merge_ready" && KitchenLayout.work(for: stale, review: .shipped).loop == "merge_ready_wait")
        // And say so above the chef: a badge on the name tag.
        #expect(ChefTagContent.Badge.make(.shipped, note: "Ready to merge")?.text == "Ready to merge")
        #expect(ChefTagContent.Badge.make(.needsFix, note: "Needs a fix · test failed")?.text == "Needs a fix")
        #expect(ChefTagContent.Badge.make(.checking, note: nil) == .testing)
        #expect(ChefTagContent.Badge.make(.shipped, note: "Behind main") == .other("Behind main"))
        #expect(ChefTagContent.Badge.make(.awaiting, note: nil) == nil)
        // Feedback sends the chef back to work, not to the break room, before the new turn is reported.
        #expect(KitchenLayout.work(for: stale, review: .reworking).area == "prep")
        // Live work always wins over an old review.
        #expect(KitchenLayout.work(for: agent("main", .working, tool: "Edit", edits: true).value, review: .awaiting).area == "cooking")
        let reviews = KitchenReviews(defaults: UserDefaults(suiteName: "reviews-" + UUID().uuidString)!)
        reviews.set("c", .awaiting); #expect(reviews.state("c") == .awaiting)
        reviews.set("c", .approved, note: "Merged"); #expect(reviews.state("c") == .approved)
        reviews.clear("c"); #expect(reviews.state("c") == nil)
    }

    @Test func recentUnreviewedDishesWaitAtTheWindowButOldOnesRest() async throws {
        let reviews = KitchenReviews(defaults: UserDefaults(suiteName: "reviews-" + UUID().uuidString)!)
        var recent = agent("main", .done, freshness: .lastKnown, conversation: "recent")
        recent.value.meaningfulUpdatedAt = Date().addingTimeInterval(-3600)
        var old = agent("main", .done, freshness: .lastKnown, conversation: "old")
        old.value.meaningfulUpdatedAt = Date().addingTimeInterval(-3 * 86400)
        reviews.observe([recent, old]); try await Task.sleep(for: .milliseconds(50))
        #expect(reviews.state("recent") == .awaiting && reviews.state("old") == nil)
        // A dish already approved isn't reopened.
        reviews.set("recent", .approved)
        reviews.observe([recent]); try await Task.sleep(for: .milliseconds(50))
        #expect(reviews.state("recent") == .approved)
    }

    @Test func feedbackKeepsTheChefWorkingUntilTheNextTurnFinishes() async throws {
        let reviews = KitchenReviews(defaults: UserDefaults(suiteName: "reviews-" + UUID().uuidString)!)
        var done = agent("main", .done)
        done.value.completionKey = "turn-1"
        reviews.observe([done]); try await Task.sleep(for: .milliseconds(50))
        #expect(reviews.state(done.conversationID) == .awaiting)
        reviews.set(done.conversationID, .reworking)
        // The finished turn is still reported for a moment; it must not reopen the review.
        reviews.observe([done]); try await Task.sleep(for: .milliseconds(50))
        #expect(reviews.state(done.conversationID) == .reworking)
        // The new turn's live work takes over, and its completion waits at the window again.
        reviews.observe([agent("main", .working)]); try await Task.sleep(for: .milliseconds(50))
        #expect(reviews.state(done.conversationID) == nil)
        done.value.completionKey = "turn-2"
        reviews.observe([done]); try await Task.sleep(for: .milliseconds(50))
        #expect(reviews.state(done.conversationID) == .awaiting)
    }

    @Test func servingWindowSuggestsAPlainCommitSubject() {
        #expect(ServingWindowView.defaultMessage("Read README.md and math.js first. Then add multiply.") == "Read README.md and math.js first")
        #expect(ServingWindowView.defaultMessage("Add a divide function to math\nand run the build") == "Add a divide function to math")
        let long = ServingWindowView.defaultMessage(String(repeating: "word ", count: 30))
        #expect(long.count <= 72 && !long.contains("…"))
    }

    @Test func roomFitsTenChefsPerStationOnWalkableFloor() {
        let navigation = KitchenLayout.chefNavigation, table = KitchenLayout.chefSlots
        #expect(KitchenLayout.areas.count == 10)
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
        // While it walks to the stove, switching back to editing doesn't turn it around mid-trip.
        view.apply(agents: [agent("a", .working, tool: "Edit", edits: true)], active: false, reducedMotion: false, now: clock)
        step(0.3)
        #expect(chef.director.station == nil && chef.director.intent?.station?.area == "stove")
        // It arrives, works the minimum dwell, then moves on.
        step(8)
        #expect(chef.director.intent?.station?.area == "cooking")
        // Needing you moves it at once.
        view.apply(agents: [agent("a", .waiting, attention: .approval, edits: true)], active: false, reducedMotion: false, now: clock)
        step(0.1)
        #expect(chef.director.intent?.station?.area == "bell")
    }

    @Test func everyChefOwnsItsSpotAndQueuedChefsStepInWhenOneFrees() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var clock = 100.0
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 30) { clock += 1 / 30; for chef in view.chefs.values { chef.update(1 / 30) }; view.pace(now: clock) }
        }
        func spot(_ a: SpatialAgent) -> String? { view.chefs[a.id]?.director.intent?.station?.id }
        var cooks = (0..<7).map { agent("c\($0)", .working, tool: "Edit", edits: true) }
        view.apply(agents: cooks, active: false, reducedMotion: false, now: clock)
        step(0.5)
        let spots = cooks.compactMap(spot)
        #expect(Set(spots).count == 7)
        #expect(spots.filter { !$0.contains("~") }.count == 6)
        let queued = try #require(cooks.first { spot($0)?.contains("~") == true })
        // c0 switches to the stove but keeps its board while it works out the minimum dwell…
        cooks[0] = agent("c0", .working, tool: "Bash", detail: "make", edits: true)
        let board = try #require(spot(cooks[0]))
        view.apply(agents: cooks, active: false, reducedMotion: false, now: clock)
        let newcomer = agent("n", .working, tool: "Edit", edits: true)
        view.apply(agents: cooks + [newcomer], active: false, reducedMotion: false, now: clock)
        #expect(spot(newcomer) != board)
        // …then leaves for a free burner, and the queued chef takes the freed board.
        step(12)
        #expect(spot(cooks[0])?.hasPrefix("stove#") == true)
        #expect(spot(queued) == board || spot(newcomer) == board)
        let all = (cooks + [newcomer]).compactMap(spot)
        #expect(Set(all).count == all.count)
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

    @Test func nameTagsShowAShortTaskAndEmotesShowState() {
        var working = agent("main", .working, tool: "Edit", edits: true)
        working.value.task = "Add a clamp function\nwith tests"
        // A written four-word label when there is one, a keyword label until then.
        let labels = TaskLabels(labels: [TaskLabels.key("Add a clamp function with tests"): "Add Clamp Function"])
        var tag = ChefTagContent.make(working, review: nil, labels: labels)
        #expect(tag.text == "Add Clamp Function" && tag.fullText == "Add a clamp function with tests" && !tag.stale && !tag.resting && tag.progress == nil)
        working.value.task = "Build a website that shows a three.js model of Salesforce Tower"
        tag = ChefTagContent.make(working, review: nil, labels: TaskLabels(labels: [:]))
        #expect(tag.text == "Build Website Three.js Model" && tag.fullText.hasPrefix("Build a website that shows"))
        #expect(TaskLabel.fallback("can you please fix the login bug on mobile safari") == "Fix Login Bug Mobile")
        // Model replies become labels only when they are labels.
        #expect(TaskLabel.clean("Warning: no stdin data received\nAdd Stats Dashboard\n") == "Add Stats Dashboard")
        #expect(TaskLabel.clean("**Fix Mobile Safari Login.**") == "Fix Mobile Safari Login")
        #expect(TaskLabel.clean("I need you to grant permissions to access the Paper design tool. However") == nil)
        #expect(TaskLabel.clean("") == nil)
        // Lasting emotes: needing you, a dish at the pass; nothing while simply working or resting.
        #expect(ChefEmote.lasting(working, review: nil) == nil)
        #expect(ChefEmote.lasting(agent("a", .waiting, attention: .approval), review: nil) == .alert)
        #expect(ChefEmote.lasting(agent("a", .waiting, attention: .input), review: nil) == .question)
        // A pull request that needs a fix shows a wrench; one ready to merge, a check.
        #expect(ChefEmote.lasting(agent("a", .done), review: .needsFix) == .wrench)
        #expect(ChefEmote.lasting(agent("a", .done), review: .shipped) == .check)
        #expect(ChefEmote.lasting(agent("a", .done), review: .awaiting) == .star)
        #expect(ChefEmote.lasting(agent("main", .done), review: .approved) == nil)
        let resting = ChefTagContent.make(agent("a", .done, freshness: .lastKnown), review: nil)
        #expect(resting.resting && resting.stale)
        // The checklist shows as progress for this turn only.
        func step(_ status: String, turn: String) -> SessionActivityRecord {
            SessionActivityRecord(id: UUID().uuidString, provider: "Claude", sessionID: "s", turnID: turn, nativeID: UUID().uuidString, kind: "step",
                                  title: "Step", status: status, detail: "", source: "test", observedAt: Date(), data: .null)
        }
        var snapshot = SessionActivitySnapshot()
        snapshot.records = [step("completed", turn: "t2"), step("completed", turn: "t2"), step("inProgress", turn: "t2"), step("pending", turn: "t2")]
        working.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t2")
        #expect(ChefTagContent.make(working, review: nil).progress == 0.5)
        working.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t3")
        #expect(ChefTagContent.make(working, review: nil).progress == nil)
        // After feedback (turn t3) the agent ticks a step off: the open steps are this turn's
        // list again, without the steps it finished before.
        snapshot.records[2].turnID = "t3"; snapshot.records[2].status = "completed"
        working.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t3")
        #expect(ChefTagContent.make(working, review: nil).progress == 0.5)
        #expect(working.value.planProgress == .steps(done: 1, total: 2))
    }

    @Test func armedSkillsGoAsStructuredCodexSkillsOrAsNamesInTheText() {
        let deploy = CapabilityInput(name: "diorama-release", path: "/skills/diorama-release/SKILL.md", kind: "skill")
        let plugin = CapabilityInput(name: "figma:figma-use", path: "/plugins/figma/SKILL.md", kind: "skill")
        let known: [WireValue] = [.object(["name": .string("diorama-release"), "path": .string(deploy.path), "enabled": .bool(true)])]
        let codex = ArmedSkillsRow.split([deploy, plugin], provider: .codex, known: known)
        #expect(codex.structured == [deploy] && codex.text == "$figma-use")
        // Claude has no structured skill input: it runs them as slash commands.
        let claude = ArmedSkillsRow.split([deploy, plugin], provider: .claude, known: known)
        #expect(claude.structured.isEmpty && claude.text == "/diorama-release /figma:figma-use")
    }

    @Test func selectingAChefRingsItFollowsItAndHidesOtherTags() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let cook = agent("a", .working, tool: "Edit", edits: true, conversation: "c1")
        let other = agent("b", .working, tool: "Read", conversation: "c2")
        view.apply(agents: [cook, other], active: false, reducedMotion: false, now: 0)
        view.fitFloor()
        let overview = try #require(view.cameraPose)
        let chef = try #require(view.chefs[cook.id])
        view.setSelection(cook.id)
        #expect(chef.root.childNode(withName: "selection ring", recursively: false) != nil)
        // The camera flies in and keeps the chef in view while it walks.
        var t = 0.0
        for _ in 0..<90 { t += 1 / 30; view.renderer(view, updateAtTime: t) }
        let follow = KitchenSceneView.followPose(for: chef.root.simdPosition)
        let pose = try #require(view.cameraPose)
        #expect(simd_distance(pose.look, follow.look) < 0.1 && simd_distance(pose.eye, follow.eye) < 0.2)
        view.apply(agents: [cook, other], active: false, reducedMotion: false, now: 1)
        let shown = view.chefLabels.filter { !$0.value.isHidden }.map(\.key)
        #expect(shown == [cook.id])
        #expect(view.chefs[other.id]?.root.opacity ?? 1 < 1)
        // Letting go returns the camera to the whole kitchen and drops the ring.
        view.setSelection(nil, immediately: true)
        #expect(chef.root.childNode(withName: "selection ring", recursively: false) == nil)
        for _ in 0..<120 { t += 1 / 30; view.renderer(view, updateAtTime: t) }
        #expect(view.cameraPose == overview && !view.cameraMoving)
    }

    @Test func switchingChefsGlidesAcrossInsteadOfPullingBack() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let a = agent("a", .working, tool: "Edit", edits: true, conversation: "c1"), b = agent("b", .working, tool: "Read", conversation: "c2")
        view.apply(agents: [a, b], active: false, reducedMotion: false, now: 0)
        view.fitFloor()
        view.setSelection(a.id)
        var t = 0.0
        for _ in 0..<90 { t += 1 / 30; view.renderer(view, updateAtTime: t) }
        let height = try #require(view.cameraPose?.eye.y)
        // Changing conversations clears the focus for a moment before the new chef is chosen.
        view.setSelection(nil); view.setSelection(b.id)
        var highest: Float = 0
        for _ in 0..<60 { t += 1 / 30; view.renderer(view, updateAtTime: t); highest = max(highest, view.cameraPose?.eye.y ?? 0) }
        #expect(view.selectedID == b.id)
        #expect(highest < height + 0.05)
    }

    @Test func aSkillFetchedInPassingStillGetsAPantryVisit() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var cook = agent("a", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[cook.id])
        var t = 0.0
        while t < 5 { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [cook], active: false, reducedMotion: false, now: t) }
        var work = TurnWork(); work.started(tool: "exec_command", detail: "cat /x/skills/release/SKILL.md", call: "s")
        cook.value.turnWork = work
        var visited = false
        while t < 25 { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [cook], active: false, reducedMotion: false, now: t); visited = visited || chef.director.station?.area == "pantry" }
        #expect(visited)
        #expect(chef.director.intent?.station?.area == "cooking")
    }

    @Test func historyLoadingAfterARelaunchOwesNoVisits() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var done = agent("a", .done)
        view.apply(agents: [done], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[done.id])
        var t = 0.0
        while t < 5 { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [done], active: false, reducedMotion: false, now: t) }
        // The saved history arrives: a test run and a skill, long finished.
        var work = TurnWork(); work.started(tool: "Bash", detail: "npm test", call: "1"); work.finished(call: "1", failed: false)
        work.started(tool: "exec_command", detail: "cat /x/skills/a/SKILL.md", call: "2")
        done.value.turnWork = work
        var areas = Set<String>()
        while t < 25 { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [done], active: false, reducedMotion: false, now: t); areas.insert(chef.director.intent?.station?.area ?? "") }
        #expect(areas == ["serving"])
    }

    @Test func everyTestRunGetsTastedEvenWhenTheAgentMovesOnAtOnce() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var cook = agent("a", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[cook.id])
        func run(from start: Double, seconds: Double) {
            var t = start
            while t < start + seconds { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [cook], active: false, reducedMotion: false, now: t) }
        }
        run(from: 0, seconds: 5)
        #expect(chef.director.station?.area == "cooking")
        // A test fails within a second and the agent is already editing again.
        var work = TurnWork(); work.started(tool: "Bash", detail: "npm test", call: "t1"); work.finished(call: "t1", failed: true)
        cook.value.turnWork = work
        var visited = false
        var t = 5.0
        while t < 25 { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [cook], active: false, reducedMotion: false, now: t); visited = visited || chef.director.station?.area == "tasting" }
        #expect(visited)
        // After tasting, the chef goes back to what the agent is doing now.
        #expect(chef.director.intent?.station?.area == "cooking")
    }

    @Test func aQuickTurnStillCooksBeforeItServes() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var cook = agent("a", .working, tool: "Read", detail: "math.js")
        view.apply(agents: [cook], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[cook.id])
        var t = 0.0
        func run(seconds: Double, _ body: (String) -> Void = { _ in }) {
            let end = t + seconds
            while t < end { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [cook], active: false, reducedMotion: false, now: t); body(chef.director.station?.area ?? "") }
        }
        run(seconds: 8)
        #expect(chef.director.station?.area == "prep")
        // The agent edits, runs its test and finishes within a second.
        var work = TurnWork()
        work.started(tool: "Edit", detail: "math.js", call: "e1"); work.finished(call: "e1", failed: false)
        cook.value.turnWork = work; cook.value.latestTool = "Edit"; cook.value.turnHasEdits = true
        run(seconds: 0.3)
        work.started(tool: "Bash", detail: "npm test", call: "t1"); work.finished(call: "t1", failed: false)
        cook.value.turnWork = work; cook.value.latestTool = "Bash"; cook.value.latestToolDetail = "npm test"
        run(seconds: 0.3)
        cook.value.status = .done
        var visits: [String] = []
        run(seconds: 30) { if $0 != "" && visits.last != $0 { visits.append($0) } }
        #expect(visits.first(where: { $0 != "prep" }) == "cooking")
        #expect(visits.contains("tasting") && visits.last == "serving")
    }

    @Test func eachProjectKeepsItsKitchenWhileYouLookElsewhere() throws {
        let stage = KitchenStage(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let a = stage.show("A")
        let cook = agent("a1", .working, tool: "Edit", edits: true, project: "A")
        a.apply(agents: [cook], scope: "A", active: true, reducedMotion: false)
        let chef = try #require(a.chefs[cook.id])
        let b = stage.show("B")
        #expect(a.isHidden && !b.isHidden && a !== b)
        // Coming back shows the same kitchen and the same chef, not a rebuilt room.
        #expect(stage.show("A") === a && a.chefs[cook.id] === chef && b.isHidden)
        for scope in ["C", "D", "E", "F", "G"] { stage.show(scope) }
        #expect(stage.kitchens.count == KitchenStage.maxKitchens && stage.kitchens["B"] == nil && stage.kitchens["A"] != nil)
    }

    @Test func catchingUpPutsChefsWhereTheirAgentsAreWithoutReplaying() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var cook = agent("a", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[cook.id])
        #expect(chef.director.intent?.station?.area == "cooking")
        // While nobody watched, the agent finished its turn.
        cook.value.status = .done
        view.apply(agents: [cook], active: false, reducedMotion: false, now: 10)
        view.catchUp()
        let director = chef.director
        let station = try #require(director.intent?.station)
        #expect(station.area == "serving" && simd_distance(director.position, station.stand) < 0.01)
        // The dish is already on the pass: no walk over and no presenting gesture to replay.
        #expect(director.placedPlate == station && !director.held.contains(.plate))
    }

    @Test func dishesWaitingForReviewQueueWithPlatesInsteadOfDisappearing() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let resting = (0..<6).map { agent("r\($0)", .done, freshness: .lastKnown, conversation: "rest\($0)") }
        let waiting = (0..<8).map { agent("w\($0)", .done, conversation: "dish\($0)") }
        view.apply(agents: resting + waiting, active: false, reducedMotion: false, now: 0)
        for _ in 0..<(30 * 20) { for chef in view.chefs.values { chef.update(1 / 30) } }
        // Every dish waiting for review is shown, and resting chefs up to the break room's seats.
        #expect(waiting.allSatisfy { view.chefs[$0.id] != nil })
        #expect(view.chefs.count == waiting.count + min(resting.count, view.maxResting))
        let line = waiting.compactMap { view.chefs[$0.id]?.director }.filter { $0.intent?.station?.id.contains("~") == true }
        #expect(line.count == 3)
        #expect(line.allSatisfy { $0.held.contains(.plate) && $0.clip.name == "carry_idle" })
        // Fifteen dishes all stay reachable, past the usual cap.
        let many = (0..<15).map { agent("m\($0)", .done, conversation: "many\($0)") }
        view.apply(agents: many, active: false, reducedMotion: false, now: 1)
        #expect(view.chefs.count == 15)
    }

    @Test func chefsFetchSkillsAndMCPToolsFromThePantry() throws {
        let fetching = agent("a", .working, tool: "mcp__linear__create_issue", edits: true).value
        #expect(KitchenLayout.work(for: fetching).area == "pantry")
        let slots = try #require(KitchenLayout.chefSlots["pantry"])
        #expect(slots.count == 4 && slots.allSatisfy { KitchenLayout.chefNavigation.isFree($0.stand) })
        var work = TurnWork(); work.started(tool: "Skill", detail: "diorama-release", call: "1")
        let feed = AgentActivityFeed.entries(from: [ActivityEvent(id: "1", provider: "Claude", sessionID: "s", kind: "toolStarted", source: "t", callID: "1", tool: "Skill", detail: "diorama-release")])
        #expect(feed.map(\.title) == ["Fetched diorama-release"])
    }

    @Test func emptyCuttingBoardsShowTheRestingCleaver() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.updateBoards()
        #expect(view.idleBoards.count == 6)
        view.apply(agents: [agent("a", .working, tool: "Edit", edits: true)], active: false, reducedMotion: false, now: 0)
        for chef in view.chefs.values { chef.update(0.1) }
        view.updateBoards()
        let used = try #require(view.chefs.values.first?.director.station?.id)
        #expect(view.idleBoards.count == 5 && !view.idleBoards.contains(used))
        view.apply(agents: [], active: false, reducedMotion: false, now: 1)
        view.updateBoards()
        #expect(view.idleBoards.count == 6)
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

    @Test func lockFreeProjectionMatchesSceneKit() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        for point in [SIMD3<Float>(0, 0, 0), SIMD3(-9, 2.8, -6), SIMD3(8, 1, 6), SIMD3(3, 3.5, -2)] {
            let mine = try #require(view.projectWithoutLock(point))
            let scene = view.projectPoint(SCNVector3(point))
            #expect(abs(mine.x - CGFloat(scene.x)) < 1 && abs(mine.y - CGFloat(scene.y)) < 1, "\(point): \(mine) vs \(scene)")
        }
    }

    @Test func neighbouringNameTagsNeverOverlap() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        view.apply(agents: (0..<10).map { agent("r\($0)", .working, tool: "Read", conversation: "c\($0)") }, active: false, reducedMotion: false)
        let tags = view.chefLabels.values.map(\.frame)
        #expect(tags.count == 10)
        for (i, a) in tags.enumerated() { for b in tags.dropFirst(i + 1) { #expect(!a.intersects(b)) } }
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
        #expect(view.chefs.count == 20)
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
        try capture((0..<8).map { task(agent("w\($0)", .done, conversation: "dish\($0)"), "codex:w\($0):turn") }, "diorama-kitchen-serving-line")
        do {
            let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
            let cooks = [agent("sel", .working, tool: "Edit", edits: true, conversation: "s1"), agent("x", .working, tool: "Read", conversation: "s2"),
                         agent("y", .working, tool: "Bash", detail: "npm test", conversation: "s3")]
            view.apply(agents: cooks, active: false, reducedMotion: false)
            for chef in view.chefs.values { for _ in 0..<30 { chef.update(1 / 30) } }
            view.layoutSubtreeIfNeeded(); view.fitFloor()
            view.setSelection(cooks[0].id)
            func shot(_ name: String) throws {
                let tiff = try #require(view.snapshot().tiffRepresentation)
                try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
            }
            view.renderer(view, updateAtTime: 0.01); try shot("diorama-kitchen-selected-start")
            var t = 0.01
            for _ in 0..<90 { t += 1 / 30; view.renderer(view, updateAtTime: t) }
            view.apply(agents: cooks, active: false, reducedMotion: false)
            try shot("diorama-kitchen-selected-follow")
        }
        do {
            // Emotes: lasting (needs you, a dish ready) and brief reactions.
            let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
            let cast = [agent("ask", .waiting, attention: .approval), agent("q", .waiting, attention: .input), agent("done", .done),
                        agent("e1", .working, tool: "Edit", edits: true), agent("e2", .working, tool: "Bash", detail: "npm test"),
                        agent("e3", .working, tool: "Read"), agent("e4", .working, tool: "Skill"), agent("e5", .working, tool: "Edit", edits: true)]
            view.apply(agents: cast, active: false, reducedMotion: true)
            for chef in view.chefs.values { for _ in 0..<30 { chef.update(1 / 30) } }
            for (id, emote) in zip(["e1", "e2", "e3", "e4", "e5"], [ChefEmote.note, .check, .thinking, .plus, .idea]) {
                view.chefEmotes[cast.first { $0.value.id == id }!.id]?.react([emote])
            }
            view.layoutSubtreeIfNeeded(); view.fitFloor()
            view.apply(agents: cast, active: false, reducedMotion: true)
            // The scene snapshot has no overlays; draw the tags and emotes over it.
            let scene = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let scale = CGFloat(scene.width) / view.bounds.width
            let context = try #require(CGContext(data: nil, width: scene.width, height: scene.height, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(scene, in: CGRect(x: 0, y: 0, width: scene.width, height: scene.height))
            context.interpolationQuality = .none
            for overlay in view.subviews where !overlay.isHidden && (overlay is ChefTagView || overlay is ChefEmoteView) {
                guard let layer = overlay.layer else { continue }
                context.saveGState()
                let y = view.isFlipped ? view.bounds.height - overlay.frame.maxY : overlay.frame.minY
                context.translateBy(x: overlay.frame.minX * scale, y: y * scale)
                context.scaleBy(x: scale, y: scale)
                if overlay.isFlipped { context.translateBy(x: 0, y: overlay.bounds.height); context.scaleBy(x: 1, y: -1) }
                layer.render(in: context)
                context.restoreGState()
            }
            let image = try #require(context.makeImage())
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-kitchen-emotes.png"))
        }
        try capture((0..<10).map { agent("e\($0)", .working, tool: "Edit", edits: true) }, "diorama-kitchen-ten-cooking")
        try capture((0..<10).map { agent("r\($0)", .done, freshness: .lastKnown) }, "diorama-kitchen-break-room")
        func task(_ a: SpatialAgent, _ key: String) -> SpatialAgent { var a = a; a.value.completionKey = key; return a }
        try capture((0..<6).map { task(agent("f\($0)", .working, tool: "Edit", edits: true), "codex:s\($0):turn") } + (0..<3).map { task(agent("t\($0)", .working, tool: "Bash", detail: "npm test", edits: true), "codex:t\($0):turn") }, "diorama-kitchen-food")
        try capture((0..<6).map { agent("e\($0)", .working, tool: "Edit", edits: true) } + (0..<4).map { agent("s\($0)", .working, tool: "Bash", detail: "make", edits: true) }, "diorama-kitchen-islands")
    }
}

extension ChefKitchenTests {
    @Test func momentsReactToWhatChanged() {
        var before = agent("a", .working, tool: "Edit", edits: true).value
        var after = before
        #expect(ChefMoment.detect(previous: nil, current: after).isEmpty)
        #expect(ChefMoment.detect(previous: before, current: after).isEmpty)
        // Tests passing and failing, a failed command, a skill fetched.
        var work = TurnWork()
        work.started(tool: "Bash", detail: "npm test", call: "t1"); work.finished(call: "t1", failed: false)
        after.turnWork = work
        #expect(ChefMoment.detect(previous: before, current: after) == [.check])
        before = after
        work.started(tool: "Bash", detail: "npm test", call: "t2"); work.finished(call: "t2", failed: true)
        work.started(tool: "Skill", detail: "frontend-design", call: "s1")
        after.turnWork = work
        #expect(Set(ChefMoment.detect(previous: before, current: after)) == [.angry, .plus])
        // A plan appears, then a step is ticked off.
        func step(_ status: String) -> SessionActivityRecord {
            SessionActivityRecord(id: UUID().uuidString, provider: "Codex", sessionID: "s", turnID: "t", nativeID: UUID().uuidString, kind: "step",
                                  title: "Step", status: status, detail: "", source: "test", observedAt: Date(), data: .null)
        }
        var snapshot = SessionActivitySnapshot()
        snapshot.records = [step("inProgress"), step("pending"), step("pending")]
        before = after
        after.plan = AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", currentTurn: "t")
        #expect(ChefMoment.detect(previous: before, current: after) == [.idea])
        before = after
        snapshot.records[0].status = "completed"
        after.plan = AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", currentTurn: "t")
        #expect(ChefMoment.detect(previous: before, current: after) == [.note])
        // Needing you, a question, the dish done.
        before = after; after.status = .waiting; after.attentionReason = .approval
        #expect(ChefMoment.detect(previous: before, current: after) == [.alert])
        before = after; after.attentionReason = .input
        #expect(ChefMoment.detect(previous: before, current: after) == [.question])
        before = after; after.status = .done
        #expect(ChefMoment.detect(previous: before, current: after) == [.star])
        // Quiet for a while: thinking.
        var quiet = agent("q", .working, tool: "Edit").value
        let now = Date()
        quiet.lastToolAt = now.addingTimeInterval(-25)
        #expect(ChefMoment.silent(quiet, now: now))
        quiet.lastToolAt = now.addingTimeInterval(-5)
        #expect(!ChefMoment.silent(quiet, now: now))
    }

    @Test func emotesQueueOneAtATimeAndReturnToTheLastingState() throws {
        let view = ChefEmoteView(frame: .zero)
        view.setLasting(.star)
        #expect(view.showing == .star)
        let now = Date()
        view.react([.note, .alert, .check], now: now)
        // Highest priority first; the others wait their turn.
        #expect(view.showing == .alert)
        // Repeats within a few seconds are dropped.
        view.react([.alert], now: now.addingTimeInterval(1))
        #expect(view.showing == .alert)
        #expect(ChefEmote.image(ChefEmote.check.glyph, color: ChefEmote.check.color)?.width == 13)
    }

    @Test func emotesSitAboveTheirTagAndHideWithIt() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let waiting = agent("w", .waiting, attention: .approval), cook = agent("c", .working, tool: "Edit", edits: true)
        view.apply(agents: [waiting, cook], active: false, reducedMotion: false)
        let emote = try #require(view.chefEmotes[waiting.id]), tag = try #require(view.chefLabels[waiting.id])
        #expect(emote.lasting == .alert && !emote.isHidden)
        #expect(emote.frame.midX == tag.frame.midX)
        #expect(view.isFlipped ? emote.frame.maxY <= tag.frame.minY : emote.frame.minY >= tag.frame.maxY)
        #expect(view.chefEmotes[cook.id]?.lasting == nil)
    }
}

extension ChefKitchenTests {
    @Test func labelsFollowEachTurnsRequestAndKeepTheirPlaceMeanwhile() {
        let task = "Build a website that shows a three.js model of Salesforce Tower"
        let labels = TaskLabels(labels: [TaskLabels.key(task): "Salesforce Tower Website",
                                         TaskLabels.key(task + "\u{1F}" + "Also add a moon that rises and sets"): "Add Moon To Tower"])
        #expect(labels.label(agent: "a", for: task, latest: task, provider: .claude) == "Salesforce Tower Website")
        // A new request this turn: its written label.
        #expect(labels.label(agent: "a", for: task, latest: "Also add a moon that rises and sets", provider: .claude) == "Add Moon To Tower")
        // "ok, go ahead" carries no new work: the label stays.
        #expect(labels.label(agent: "a", for: task, latest: "ok, go ahead", provider: .claude) == "Add Moon To Tower")
        // A request without a written label yet keeps the chef's current one (no generator in tests).
        #expect(labels.label(agent: "a", for: task, latest: "Make the windows glow at night", provider: .claude) == "Add Moon To Tower")
        #expect(TaskLabel.isAcknowledgement("yes please continue") && TaskLabel.isAcknowledgement("LGTM!") && !TaskLabel.isAcknowledgement("yes, and add tests"))
        #expect(TaskLabel.prompt(task, latest: "Add a moon").contains("Latest request: <latest>Add a moon</latest>"))
    }

    @Test func theProgressBarSitsBetweenTheTagAndTheChefOnlyWithAList() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var cook = agent("c", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: false)
        let bar = try #require(view.chefBars[cook.id]), tag = try #require(view.chefLabels[cook.id])
        #expect(bar.isHidden && bar.fraction == nil)
        func step(_ status: String) -> SessionActivityRecord {
            SessionActivityRecord(id: UUID().uuidString, provider: "Claude", sessionID: "s", turnID: "t", nativeID: UUID().uuidString, kind: "step",
                                  title: "Step", status: status, detail: "", source: "test", observedAt: Date(), data: .null)
        }
        var snapshot = SessionActivitySnapshot()
        snapshot.records = [step("completed"), step("inProgress"), step("pending"), step("pending")]
        cook.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t")
        view.apply(agents: [cook], active: false, reducedMotion: false)
        #expect(!bar.isHidden && bar.fraction == 0.25)
        let emote = try #require(view.chefEmotes[cook.id])
        // Emote above the tag, the bar below it (nearer the head), all centred.
        #expect(bar.frame.midX == tag.frame.midX)
        if view.isFlipped { #expect(bar.frame.minY >= tag.frame.maxY) } else { #expect(bar.frame.maxY <= tag.frame.minY) }
        _ = emote
    }
}

extension ChefKitchenTests {
    @Test func aQuestionLeftForYouSendsTheChefToTheBell() {
        let asked = [Entry(id: "u", kind: "You", text: "Add a stats dashboard. Ask me which colour theme first.", timestamp: nil),
                     Entry(id: "q1", kind: "Assistant", text: "Which colour theme should the dashboard use?", timestamp: nil),
                     Entry(id: "q2", kind: "Assistant", text: "Which colour theme should the dashboard use?", timestamp: nil)]
        // The turn ended on the question without changing anything: it needs your answer.
        #expect(WorkspaceAgentPresentation.awaitsAnswer(agent("a", .done).value, entries: asked))
        // Waiting for the answer mid-turn (Codex sleeps after an asynchronous question).
        #expect(WorkspaceAgentPresentation.awaitsAnswer(agent("a", .working, tool: "sleep").value, entries: asked))
        #expect(!WorkspaceAgentPresentation.awaitsAnswer(agent("a", .working, tool: "Edit").value, entries: asked))
        // Work delivered with a closing offer is a dish, not a question.
        var delivered = agent("a", .done).value
        var work = TurnWork(); work.started(tool: "Edit", detail: "dashboard.html", call: "e"); delivered.turnWork = work
        #expect(!WorkspaceAgentPresentation.awaitsAnswer(delivered, entries: asked))
        // Once you answer, it isn't waiting any more.
        #expect(!WorkspaceAgentPresentation.awaitsAnswer(agent("a", .done).value, entries: asked + [Entry(id: "a", kind: "You", text: "Dark blue", timestamp: nil)]))
        // The repeated question shows once in the conversation.
        let rows = ConversationHistory.rows(asked, mode: .conversation)
        let assistantEntries = rows.flatMap(\.entries).filter { $0.kind == "Assistant" }.count
        #expect(assistantEntries == 1)
        let detailedEntries = ConversationHistory.rows(asked, mode: .detailed).flatMap(\.entries).count
        #expect(detailedEntries == 3)
        // At the bell with a question emote.
        var waiting = agent("a", .done); waiting.value.status = .waiting; waiting.value.attentionReason = .input
        #expect(KitchenLayout.work(for: waiting.value).area == "bell" && ChefEmote.lasting(waiting, review: nil) == .question)
    }
}

extension ChefKitchenTests {
    @Test func aCommandThatTestsAndBuildsVisitsBothStationsInOrder() throws {
        #expect(KitchenActivity.stations(command: "npm test && npm run build") == [.testing, .commands])
        #expect(KitchenActivity.stations(command: "npm run build; npm test") == [.commands, .testing])
        #expect(KitchenActivity.stations(command: "node - <<'NODE'\nconsole.log(1)\nNODE\nnpm test\nnpm run build") == [.commands, .testing, .commands])
        #expect(KitchenActivity.stations(command: "git status; cat math.js") == [])
        // Eli's last step: tests and a build in one command, just before finishing.
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var cook = agent("e", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[cook.id])
        var t = 0.0
        func run(seconds: Double, _ body: (String) -> Void = { _ in }) {
            let end = t + seconds
            while t < end { chef.update(1 / 30); t += 1 / 30; view.apply(agents: [cook], active: false, reducedMotion: false, now: t); body(chef.director.station?.area ?? "") }
        }
        run(seconds: 6)
        var work = TurnWork()
        work.started(tool: "Bash", detail: "npm test && npm run build", call: "c"); work.finished(call: "c", failed: false)
        cook.value.turnWork = work; cook.value.latestTool = "Bash"; cook.value.latestToolDetail = "npm test && npm run build"
        run(seconds: 0.3)
        cook.value.status = .done
        var visits: [String] = []
        run(seconds: 40) { if $0 != "" && visits.last != $0 { visits.append($0) } }
        let tasting = try #require(visits.firstIndex(of: "tasting")), stove = try #require(visits.firstIndex(of: "stove"))
        #expect(tasting < stove && visits.last == "serving")
    }
}

extension ChefKitchenTests {
    @Test func codexAsyncQuestionSendsTheChefToTheBellWhateverTheLastWords() {
        // Codex asked with request_user_input_async, then ended its turn on a statement.
        var question = Entry(id: "q", kind: "Assistant", text: "Should quantities be shown in metric or imperial?\n- Metric\n- Imperial", timestamp: nil)
        question.asksYou = true
        let asked = [Entry(id: "u", kind: "You", text: "Build a recipe scaler. Ask me metric or imperial first.", timestamp: nil), question,
                     Entry(id: "w", kind: "Assistant", text: "I'll wait for your metric or imperial preference before continuing.", timestamp: nil)]
        #expect(WorkspaceAgentPresentation.awaitsAnswer(agent("a", .done).value, entries: asked))
        // Without the question tool, a statement is not a question.
        #expect(!WorkspaceAgentPresentation.awaitsAnswer(agent("a", .done).value, entries: [asked[0], asked[2]]))
        #expect(!WorkspaceAgentPresentation.awaitsAnswer(agent("a", .done).value, entries: asked + [Entry(id: "a", kind: "You", text: "Imperial", timestamp: nil)]))
    }

    @Test func codexAsyncQuestionKeepsItsMessageInTheTranscript() {
        let lines = [
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input_async","arguments":"{}","call_id":"call_q","turn_id":"t"}}"#,
            #"{"type":"event_msg","payload":{"type":"item_completed","turn_id":"t","item":{"type":"AgentMessage","id":"call_q","content":[{"type":"Text","text":"Metric or imperial?"}],"delivery":"async","questions":[{"title":"Metric or imperial?","options":["Metric","Imperial"]}]}}}"#,
            #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call_q","output":"{\"accepted\":true}","turn_id":"t"}}"#,
        ]
        let transcript = CodexTranscriptNormalizer.parse(Data((lines.joined(separator: "\n") + "\n").utf8), scope: "s", start: 0, limit: 100)
        let shown = transcript.entries.filter { $0.kind != "Event" }
        #expect(shown.count == 1)
        #expect(shown.first?.kind == "Assistant" && shown.first?.text == "Metric or imperial?" && shown.first?.asksYou == true)
    }

    @Test func aChefWithHistoryNeverArrivesByElevator() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.apply(agents: [], scope: "p", active: false, reducedMotion: false, now: 0)
        let cook = agent("a", .working, tool: "Read")
        view.apply(agents: [cook], scope: "p", active: false, reducedMotion: false, now: 1)
        #expect(view.chefs[cook.id]?.director.intent?.key.hasPrefix("arrival") == true)
        // Pushed out (the cap, a review state) and back for a new turn: it walks back to work
        // from where it stood instead of riding the elevator again.
        let stood = try #require(view.chefs[cook.id]?.director.position)
        view.apply(agents: [], scope: "p", active: false, reducedMotion: false, now: 2)
        view.apply(agents: [cook], scope: "p", active: false, reducedMotion: false, now: 3)
        let back = try #require(view.chefs[cook.id])
        #expect(back.director.intent?.key.hasPrefix("arrival") == false && back.director.intent?.station?.area == "prep")
        #expect(simd_distance(back.director.position, stood) < 0.01)
        // A conversation you already followed up on is not new either.
        var followed = agent("b", .working, tool: "Read", conversation: "d"); followed.value.latestRequest = "Use imperial units"
        view.apply(agents: [cook, followed], scope: "p", active: false, reducedMotion: false, now: 4)
        #expect(view.chefs[followed.id]?.director.intent?.key.hasPrefix("arrival") == false)
    }

    @Test func acceptedWorkWalksToTheBreakRoomEvenWhenItIsFull() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        // The break room is full of chefs who rested more recently than this one finished.
        let resters = (0..<view.maxResting).map { index -> SpatialAgent in
            var rester = agent("r\(index)", .done, freshness: .lastKnown, conversation: "r\(index)")
            rester.value.meaningfulUpdatedAt = Date(timeIntervalSinceNow: -Double(index)); return rester
        }
        var served = agent("main", .done, conversation: "c"); served.value.meaningfulUpdatedAt = Date(timeIntervalSinceNow: -3600)
        view.reviews = ["c": .awaiting]
        view.apply(agents: resters + [served], active: false, reducedMotion: false, now: 0)
        #expect(view.chefs[served.id] != nil && resters.allSatisfy { view.chefs[$0.id] != nil })
        // Marked done: it still celebrates and walks off.
        view.reviews = ["c": .approved]
        view.apply(agents: resters + [served], active: false, reducedMotion: false, now: 1)
        let chef = try #require(view.chefs[served.id])
        #expect(chef.director.intent?.station?.area == "break" && chef.director.intent?.prelude == "celebrate_done")
        // Once it has had time to sit down, only the most recent resters keep the seats.
        view.apply(agents: resters + [served], active: false, reducedMotion: false, now: 1 + KitchenSceneView.walkOff + 1)
        #expect(view.chefs[served.id] == nil && view.chefs.count == view.maxResting)
        // Feedback counts as work: a reworking chef is always in the kitchen.
        view.reviews = ["c": .reworking]
        view.apply(agents: resters + [served], active: false, reducedMotion: false, now: 40)
        #expect(view.chefs[served.id]?.director.intent?.station?.area == "prep")
    }

    @Test func everyoneWithWorkIsShownAndTheBreakRoomKeepsTheMostRecent() {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let working = (0..<16).map { agent("w\($0)", .working, tool: "Edit", edits: true, conversation: "w\($0)") }
        let idle = (0..<(view.maxResting + 4)).map { index -> SpatialAgent in
            var rester = agent("i\(index)", .done, freshness: .lastKnown, conversation: "i\(index)")
            rester.value.meaningfulUpdatedAt = Date(timeIntervalSince1970: Double(index) * 60); return rester
        }
        view.apply(agents: working + idle, active: false, reducedMotion: false, now: 0)
        #expect(working.allSatisfy { view.chefs[$0.id] != nil })
        // The newest idle conversations rest; the oldest four aren't shown.
        #expect(idle.suffix(view.maxResting).allSatisfy { view.chefs[$0.id] != nil })
        #expect(idle.prefix(4).allSatisfy { view.chefs[$0.id] == nil })
    }
}

extension ChefKitchenTests {
    @Test func aHeldChefDanglesSquirmsAndWalksBackWhenPutDown() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let cook = agent("a", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[cook.id])
        for _ in 0..<300 { chef.update(1 / 30) } // walk to the cooking station
        let start = chef.director.position
        #expect(chef.director.station?.area == "cooking")
        chef.held = ChefAvatar.Hold(target: SIMD2(2, 1), point: start)
        let arm = try #require(chef.rig.bone("upperarm.L"))
        var arms: [simd_quatf] = []
        for frame in 0..<90 {
            chef.update(1 / 30)
            if frame == 60 || frame == 75 { arms.append(arm.simdOrientation) }
        }
        // Lifted off the floor, carried toward the pointer, its director paused.
        #expect(chef.root.simdPosition.y > 0.5 && simd_distance(SIMD2(chef.root.simdPosition.x, chef.root.simdPosition.z), SIMD2(2, 1)) < 0.1)
        #expect(chef.director.position == start && chef.animating)
        // Squirming: the arms keep moving.
        #expect(abs(arms[0].angle - arms[1].angle) > 0.01 || simd_length(arms[0].axis - arms[1].axis) > 0.01)
        // Put down away from its station, it isn't there any more and walks back.
        let floor = view.freeFloor(near: SIMD2(2, 1))
        chef.release(at: floor)
        #expect(chef.held == nil && chef.director.position == floor && chef.director.station == nil)
        #expect(chef.director.stepNames.contains("goto:cooking"))
        chef.update(1 / 30)
        #expect(chef.root.simdPosition.y == 0)
    }

    @Test func pointerRaysMeetTheFloorWhereTheSceneProjects() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        for point in [SIMD3<Float>(0, 0, 0), SIMD3(-6, 0, -3), SIMD3(5, 2.6, 4), SIMD3(3, 2.6, -2)] {
            let screen = try #require(view.projectWithoutLock(point))
            let hit = try #require(view.floorRay(screen, planeY: point.y))
            #expect(simd_distance(hit, SIMD2(point.x, point.z)) < 0.02, "\(point): \(hit)")
        }
        // Counters and walls aren't floor: a drop there lands next to them.
        let navigation = KitchenLayout.chefNavigation
        let counter = try #require(navigation.obstacles.first.map { ($0.min + $0.max) / 2 })
        #expect(!navigation.isFree(counter))
        let landed = view.freeFloor(near: counter)
        #expect(navigation.isFree(landed) && simd_distance(landed, counter) < 6)
    }

    @Test func onlyIdleMainConversationsGoInTheTrash() {
        let library = LibraryModel()
        library.sessions = [Session(id: "c", provider: .codex, url: nil, sessionID: "c", title: "T", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)]
        #expect(library.archiveBlocker(agent("main", .done)) == nil)
        #expect(library.archiveBlocker(agent("main", .working, tool: "Edit")) == "Stop Agent main first")
        #expect(library.archiveBlocker(agent("helper", .done)) == "Sub-agents can't be archived")
        #expect(library.archiveBlocker(agent("main", .done, conversation: "missing")) != nil)
        // Restored from a previous run (nothing in flight): finished work still goes in the trash.
        library.execution.tasks["c"] = ExecutedTask(id: "c", title: "T", folder: "/tmp", parentID: nil, phase: .disconnected, error: "Previous run")
        #expect(library.archiveBlocker(agent("main", .done)) == nil)
        // Cut off mid-turn, or running: not until it stops.
        library.execution.tasks["c"]?.requiresReconciliation = true
        #expect(library.archiveBlocker(agent("main", .done)) == "Stop Agent main first")
        library.execution.tasks["c"]?.requiresReconciliation = false; library.execution.tasks["c"]?.phase = .working
        #expect(library.archiveBlocker(agent("main", .done)) == "Stop Agent main first")
    }
}

extension ChefKitchenTests {
    @Test func aClaudeArchiveFromAnyWindowSurvivesTheOwnersRescans() {
        let owner = LibraryModel(), window = LibraryModel(sharedOwner: owner)
        let wren = Session(id: "Claude Code:wren-test", provider: .claude, url: nil, sessionID: "wren-test", title: "Wren", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        owner.sessions = [wren]
        window.archivedHere.insert(wren.id)
        #expect(owner.archivedHere.contains(wren.id) && owner.sessions.first?.archived == true)
        // The owner's next rescan reads the transcript as not archived; it stays archived.
        owner.sessions = [wren]
        #expect(window.sessions.first?.archived == true)
        window.archivedHere.remove(wren.id)
        owner.sessions = [wren]
        #expect(window.sessions.first?.archived == false)
        // Codex too: a stale thread list (state database, or the previous scan reused) can't bring it back.
        let remy = Session(id: "Codex:remy-test", provider: .codex, url: nil, sessionID: "remy-test", title: "Remy", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        window.archivedHere.insert(remy.id)
        owner.sessions = [remy]
        #expect(window.sessions.first?.archived == true)
        window.archivedHere.remove(remy.id)
    }
}

extension ChefKitchenTests {
    @Test func aHeldChefFollowsThePointerPastTheWallsToTheTrash() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        // Up in the top-right corner, where the trash sits, outside the kitchen's walls.
        let corner = CGPoint(x: 960, y: 660)
        let held = try #require(view.grabPoint(corner))
        let half = SIMD2(Float(KitchenLayout.floor.width / 2), Float(KitchenLayout.floor.height / 2))
        #expect(abs(held.x) > half.x || abs(held.y) > half.y)
        // Its head is right under the pointer.
        let head = SIMD3(held.x, (ChefAvatar.liftHeight + 1.7) * KitchenLayout.chefScale, held.y)
        let shown = try #require(view.projectWithoutLock(head))
        #expect(abs(shown.x - corner.x) < 2 && abs(shown.y - corner.y) < 2)
        // Put down out there, it lands on free floor inside the walls.
        let landed = view.freeFloor(near: view.insideWalls(held))
        #expect(abs(landed.x) < half.x && abs(landed.y) < half.y && KitchenLayout.chefNavigation.isFree(landed))
    }
}

extension ChefKitchenTests {
    @Test func theRestaurantSurroundsTheKitchen() throws {
        let restaurant = try #require(KitchenRestaurant.shared)
        // Twelve diner seats, nearest the serving pass first, each facing its table.
        #expect(restaurant.seats.count == 12)
        let pass = SIMD2<Float>(6.9, 7.0)
        let distances = restaurant.seats.map { simd_distance($0.stand, pass) }
        #expect(distances == distances.sorted())
        for seat in restaurant.seats {
            // Beside the kitchen, where the home camera sees them, not out front.
            #expect(abs(seat.stand.x) > Float(KitchenLayout.floor.maxX) && abs(seat.stand.y) < Float(KitchenLayout.floor.maxY), "\(seat.id) sits beside the kitchen")
            #expect(simd_distance(SIMD2(seat.dish.x, seat.dish.z), seat.stand) < 0.6 && seat.dish.y > 0.9)
        }
        // The right-hand side, next to the serving pass, fills first.
        #expect(restaurant.seats.prefix(6).allSatisfy { $0.stand.x > 0 })
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        #expect(view.scene?.rootNode.childNode(withName: "restaurant", recursively: false) != nil)
        // In a wide window every diner's table is in the home view.
        for seat in restaurant.seats {
            let point = try #require(view.projectWithoutLock(seat.dish))
            #expect(view.bounds.insetBy(dx: 4, dy: 4).contains(point), "\(seat.id) at \(point)")
        }
        guard let path = ProcessInfo.processInfo.environment["DIORAMA_RESTAURANT_CAPTURE"] else { return }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = view.scene; renderer.pointOfView = view.pointOfView
        func save(_ name: String) throws {
            let image = renderer.snapshot(atTime: 2, with: CGSize(width: 1600, height: 900), antialiasingMode: .multisampling4X)
            try image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }?
                .write(to: URL(fileURLWithPath: path + name + ".png"))
        }
        try save("home")
        eye0: do {
            let eye = SCNNode(); eye.camera = view.pointOfView?.camera?.copy() as? SCNCamera
            view.scene?.rootNode.addChildNode(eye); renderer.pointOfView = eye
            eye.position = SCNVector3(9, 5, 17); eye.look(at: SCNVector3(8, 0.8, 11.5)); try save("diners")
            renderer.pointOfView = view.pointOfView
        }
        // Looking back from the terrace, and from the canal side.
        let eye = SCNNode(); eye.camera = view.pointOfView?.camera?.copy() as? SCNCamera
        view.scene?.rootNode.addChildNode(eye); renderer.pointOfView = eye
        eye.position = SCNVector3(8, 16, 30); eye.look(at: SCNVector3(4, 0, 6)); try save("terrace")
        eye.position = SCNVector3(30, 18, 4); eye.look(at: SCNVector3(10, 0, 2)); try save("side")
    }
}

extension ChefKitchenTests {
    @Test func glbNodePositionsSurviveNumbersThatArentExactFloats() throws {
        // JSONSerialization hands back doubles; `as? [Float]` used to drop the whole position.
        let node = try #require(JSONSerialization.jsonObject(with: Data(#"{"translation":[-15.5,0.027108989655971527,15.5],"scale":[1,1.0000000001,1]}"#.utf8)) as? [String: Any])
        let pose = GLBDocument.restPose(node)
        #expect(simd_distance(pose.position, SIMD3(-15.5, 0.0271, 15.5)) < 0.001)
        #expect(simd_distance(pose.scale, SIMD3(1, 1, 1)) < 0.001)
    }
}

extension ChefKitchenTests {
    @Test func aServedDishGoesToADinerUntilTheWorkIsAccepted() throws {
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let restaurant = try #require(KitchenRestaurant.shared)
        // Diners sit at the tables nearest the pass, hatless, facing their tables.
        let diners = try #require(view.scene?.rootNode.childNodes.filter { $0.name?.hasPrefix("diner:") == true })
        #expect(diners.count == KitchenSceneView.dinerCount)
        let first = try #require(diners.first { $0.name == "diner:" + restaurant.seats[0].id })
        #expect(simd_distance(SIMD2(first.simdPosition.x, first.simdPosition.z), restaurant.seats[0].stand) < 0.05)
        // A finished task: its chef carries the dish to the pass and sets it down.
        let done = agent("main", .done, conversation: "served")
        view.reviews = ["served": .awaiting]
        view.apply(agents: [done], active: false, reducedMotion: false, now: 0)
        let chef = try #require(view.chefs[done.id])
        for _ in 0..<(30 * 30) where chef.director.placedPlate == nil { chef.update(1 / 30) }
        #expect(chef.director.placedPlate != nil)
        view.serveDiners(now: 1)
        #expect(view.servedSeats["served"] == 0)
        // Accepted: the chef leaves the pass; the diner finishes eating, then the table clears.
        view.reviews = ["served": .approved]
        view.apply(agents: [done], active: false, reducedMotion: false, now: 2)
        for _ in 0..<30 { chef.update(1 / 30) }
        view.serveDiners(now: 3)
        #expect(view.servedSeats["served"] == 0)
        view.serveDiners(now: 3 + KitchenSceneView.dinerLinger + 1)
        #expect(view.servedSeats["served"] == nil)
    }
}
