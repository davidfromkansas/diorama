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
        #expect(KitchenLayout.work(for: stale, review: .shipped).area == "serving")
        #expect(KitchenLayout.work(for: stale, review: .committed).oneShot == "cover_dish")
        #expect(KitchenLayout.work(for: stale, review: .approved).area == "break")
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

    @Test func nameTagsShowTheTaskAndOneLiveIcon() {
        var working = agent("main", .working, tool: "Edit", edits: true)
        working.value.task = "Add a clamp function\nwith tests"
        var tag = ChefTagContent.make(working, review: nil)
        #expect(tag.text == "Add a clamp function" && tag.icon == .edit && !tag.stale && !tag.resting && tag.progress == nil)
        // A fresh progress note shows the speech bubble, until the next tool call or a few seconds pass.
        let now = Date()
        working.value.lastToolAt = now.addingTimeInterval(-5); working.value.lastCommentaryAt = now.addingTimeInterval(-1)
        #expect(ChefTagContent.make(working, review: nil, now: now).icon == .commentary)
        #expect(ChefTagContent.make(working, review: nil, now: now.addingTimeInterval(5)).icon == .edit)
        working.value.lastToolAt = now
        #expect(ChefTagContent.make(working, review: nil, now: now).icon == .edit)
        // Each kind of work has its icon.
        #expect(ChefTagContent.make(agent("a", .working, tool: "Bash", detail: "npm test"), review: nil).icon == .test)
        #expect(ChefTagContent.make(agent("a", .working, tool: "Bash", detail: "npm run build"), review: nil).icon == .command)
        #expect(ChefTagContent.make(agent("a", .working, tool: "mcp__linear__create_issue"), review: nil).icon == .pantry)
        // Needing you wins; a dish waiting for review shows a check; resting chefs hide until hovered.
        #expect(ChefTagContent.make(agent("a", .waiting, attention: .approval), review: nil).icon == .help)
        #expect(ChefTagContent.make(agent("a", .done), review: .awaiting).icon == .ready)
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
        // Every dish waiting for review is shown; resting chefs only fill the rest of the cap.
        #expect(waiting.allSatisfy { view.chefs[$0.id] != nil })
        #expect(view.chefs.count == KitchenSceneView.maxChefs)
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
        try capture((0..<10).map { agent("e\($0)", .working, tool: "Edit", edits: true) }, "diorama-kitchen-ten-cooking")
        try capture((0..<10).map { agent("r\($0)", .done, freshness: .lastKnown) }, "diorama-kitchen-break-room")
        func task(_ a: SpatialAgent, _ key: String) -> SpatialAgent { var a = a; a.value.completionKey = key; return a }
        try capture((0..<6).map { task(agent("f\($0)", .working, tool: "Edit", edits: true), "codex:s\($0):turn") } + (0..<3).map { task(agent("t\($0)", .working, tool: "Bash", detail: "npm test", edits: true), "codex:t\($0):turn") }, "diorama-kitchen-food")
        try capture((0..<6).map { agent("e\($0)", .working, tool: "Edit", edits: true) } + (0..<4).map { agent("s\($0)", .working, tool: "Bash", detail: "make", edits: true) }, "diorama-kitchen-islands")
    }
}
