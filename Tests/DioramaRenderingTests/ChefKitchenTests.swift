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
        #expect(assets.rig.clips.count == 48)
        #expect(Set(assets.manifest.clips.keys) == Set(assets.rig.clips.keys))
        let chef = assets.rig.makeInstance()
        #expect(chef.nodes.contains { $0.skinner?.bones.count == 26 })
        for socket in ["socket_hand.L", "socket_hand.R", "socket_carry"] { #expect(chef.bone(socket) != nil) }
        for prop in ChefProp.allCases {
            #expect(assets.props[prop.node] != nil)
            #expect(assets.manifest.attach[prop.node]?[prop.fitClip] != nil)
        }
        #expect(assets.props.count == 13)
        // The manager: fitted to the chef's skeleton, never one of the agents' characters.
        #expect(assets.staff.map(\.id) == [ChefAssets.manager] && !assets.characters.contains { $0.id == ChefAssets.manager })
        #expect(assets.rig(for: ChefAssets.manager) !== assets.rig)
        #expect(assets.manifest.stations.counterTop == KitchenLayout.chefCounterTop)
        #expect(assets.manifest.stations.counterFrontFromRoot == KitchenLayout.chefCounterFront)
        #expect(assets.manifest.height == KitchenLayout.chefHeight)
    }

    /// The characters chefs wear: each loads, has the chef's skeleton node for node, and plays
    /// the chef's clips exactly as the chef does.
    @Test func everyCharacterLoadsOnTheChefsSkeleton() throws {
        let assets = try ChefAssets.shared.get()
        #expect(assets.characters.count == 10)
        #expect(Set(assets.characters.map(\.id)).count == 10)
        for character in assets.characters {
            let rig = assets.rig(for: character.id)
            #expect(character.id == ChefAssets.classic || rig !== assets.rig, "\(character.id) fell back to the chef")
            #expect(rig.nodeNames == assets.rig.nodeNames)
            let chef = rig.makeInstance()
            #expect(chef.nodes.contains { $0.skinner?.bones.count == 26 })
            // Tangents come with the geometry: SceneKit never builds them while kitchens draw.
            #expect(chef.nodes.contains { $0.geometry?.sources(for: .tangent).first?.componentsPerVector == 4 })
            for socket in ["socket_hand.L", "socket_hand.R", "socket_carry"] { #expect(chef.bone(socket) != nil) }
            let a = rig.pose("working_chop", time: 0.3), b = assets.rig.pose("working_chop", time: 0.3)
            #expect(zip(a, b).allSatisfy { simd_distance($0.position, $1.position) < 1e-6 && abs(simd_dot($0.rotation.vector, $1.rotation.vector)) > 0.99999 })
        }
    }

    @Test func aCharacterLoadsQuickly() throws {
        let assets = try ChefAssets.shared.get()
        let entry = try #require(assets.characters.last)
        let data = try Data(contentsOf: try #require(SkinnedGLBAsset.resourceBundle.url(forResource: (entry.asset as NSString).deletingPathExtension, withExtension: "glb", subdirectory: "Chef")))
        let start = Date()
        _ = try SkinnedGLBAsset(data: data, spec: ChefAssets.spec, clipsFrom: assets.rig)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func aKitchenWearsTenDifferentCharactersBeforeAnyRepeats() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.characters = ChefCharacterModel(url: nil)
        let crowd = (0..<12).map { agent("x\($0)", .working, tool: "Edit") }
        view.apply(agents: Array(crowd.prefix(10)), active: false, reducedMotion: true)
        #expect(Set(view.chefs.values.map(\.character)).count == 10)
        view.apply(agents: crowd, active: false, reducedMotion: true)
        #expect(view.chefs.count == 12)
        // Gone and back: the same chef, the same character.
        let returning = crowd[3].id
        let worn = try #require(view.chefs[returning]).character
        view.apply(agents: crowd.filter { $0.id != returning }, active: false, reducedMotion: true)
        #expect(view.chefs[returning] == nil)
        view.apply(agents: crowd, active: false, reducedMotion: true)
        #expect(view.chefs[returning]?.character == worn)
    }

    @Test func chefLoadsQuicklyEnoughForTheMainThread() throws {
        let data = try Data(contentsOf: try #require(SkinnedGLBAsset.resourceBundle.url(forResource: "chef-animated", withExtension: "glb", subdirectory: "Chef")))
        let start = Date()
        _ = try SkinnedGLBAsset(data: data, spec: ChefAssets.spec)
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

    @Test func theTasksDishFollowsTheChefFromTastingToServing() throws {
        let assets = try ChefAssets.shared.get(), table = KitchenLayout.chefSlots
        let chef = ChefAvatar(id: "a", assets: assets, scale: KitchenLayout.chefScale, navigation: KitchenLayout.chefNavigation)
        chef.dish = "pizza"
        let board = try #require(table["cooking"]?.first), tasting = try #require(table["tasting"]?.first), serving = try #require(table["serving"]?.first)
        chef.director.place(board.stand, heading: board.facing)
        chef.director.setIntent(KitchenLayout.intent(for: agent("main", .working, tool: "Edit", edits: true).value, at: board, pickup: nil, restored: false))
        for _ in 0..<10 { chef.update(1 / 30) }
        // Chopping, the chef works on the chopped board, which stands in for the dish.
        #expect(chef.choppingOnBoard && chef.dishPlacement == "hidden")
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
        // And say so above the chef: the tag's state and line, the checks as blocks of its bar.
        let finished = agent("main", .done, freshness: .lastKnown)
        let shipped = ChefTagContent.make(finished, review: .shipped, note: "Ready to merge", checks: [.passed, .passed])
        #expect(shipped.phase == .shipped && shipped.line == "Ready to merge" && shipped.progress == .checks([.passed, .passed]))
        let broken = ChefTagContent.make(finished, review: .needsFix, note: "Needs a fix · lint failed", checks: [.passed, .failed])
        #expect(broken.phase == .needsFix && broken.phase.needsYou && broken.line == "lint failed" && broken.progress == .checks([.passed, .failed]))
        #expect(ChefTagContent.make(finished, review: .checking, note: nil).phase == .checking)
        #expect(ChefTagContent.make(finished, review: .shipped, note: "Behind main").line == "Behind main")
        #expect(ChefTagContent.make(finished, review: .awaiting).phase == .done)
        #expect(PRWatcher.checks(LinkedPullRequest(number: 1, title: "", url: "u", state: "OPEN", isDraft: false, headRefName: "b", headRefOid: "o",
                                                   statusCheckRollup: [PRCheck(name: "a", conclusion: "SUCCESS"), PRCheck(name: "b", conclusion: "FAILURE"), PRCheck(name: "c", status: "IN_PROGRESS")]))
                == [.passed, .failed, .running])
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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

    @Test func tagsShowTheNameWhatTheChefIsDoingAndHowFarAlong() {
        var working = agent("main", .working, tool: "Edit", edits: true)
        working.value.task = "Add a clamp function\nwith tests"
        // A written four-word label when there is one, a keyword label until then.
        let labels = TaskLabels(labels: [TaskLabels.key("Add a clamp function with tests"): "Add Clamp Function"])
        var tag = ChefTagContent.make(working, review: nil, labels: labels)
        #expect(tag.text == "Add Clamp Function" && tag.fullText == "Add a clamp function with tests" && !tag.stale && !tag.resting && tag.progress == .sweep)
        working.value.task = "Build a website that shows a three.js model of Salesforce Tower"
        tag = ChefTagContent.make(working, review: nil, labels: TaskLabels(labels: [:]))
        #expect(tag.text == "Build Website Three.js Model" && tag.fullText.hasPrefix("Build a website that shows"))
        #expect(TaskLabel.fallback("can you please fix the login bug on mobile safari") == "Fix Login Bug Mobile")
        // Model replies become labels only when they are labels.
        #expect(TaskLabel.clean("Warning: no stdin data received\nAdd Stats Dashboard\n") == "Add Stats Dashboard")
        #expect(TaskLabel.clean("**Fix Mobile Safari Login.**") == "Fix Mobile Safari Login")
        #expect(TaskLabel.clean("I need you to grant permissions to access the Paper design tool. However") == nil)
        #expect(TaskLabel.clean("") == nil)
        // The phase: colour and symbol for what the chef is doing, or what it needs from you.
        func phase(_ a: SpatialAgent, _ review: KitchenReviews.State? = nil) -> ChefTagContent.Phase { ChefTagContent.make(a, review: review).phase }
        #expect(phase(working) == .working && ChefTagContent.make(working, review: nil).name == "Agent main")
        #expect(phase(agent("a", .waiting, attention: .approval)) == .approval && phase(agent("a", .waiting, attention: .input)) == .waiting)
        #expect(phase(agent("a", .failed)) == .failed && phase(agent("a", .stopped)) == .stopped && phase(agent("a", .ready)) == .idle)
        #expect(phase(agent("a", .done), .awaiting) == .done && phase(agent("main", .done), .approved) == .idle)
        #expect(ChefTagContent.Phase.approval.color != ChefTagContent.Phase.waiting.color)
        #expect([ChefTagContent.Phase.waiting, .approval, .failed, .needsFix].allSatisfy(\.needsYou) && !ChefTagContent.Phase.working.needsYou)
        // The line: the live step from the activity feed; a turn just begun is starting.
        var live = agent("l", .working, tool: "Edit")
        live.value.feed = [FeedEntry(id: "s", kind: .started, title: "Turn started", time: Date())]
        #expect(phase(live) == .starting && ChefTagContent.make(live, review: nil).line == "starting…")
        live.value.feed.append(FeedEntry(id: "e", kind: .editing, title: "Edited Foo.swift", outcome: .done, time: Date()))
        live.value.lastToolAt = Date()
        let edited = ChefTagContent.make(live, review: nil)
        #expect(edited.phase == .working && edited.line == "Edited Foo.swift" && edited.progress == .sweep && edited.log.isEmpty)
        // The log holds the steps before the live one, never the live one again.
        live.value.feed.append(FeedEntry(id: "r", kind: .research, title: "Looked at Bar.swift", outcome: .done, time: Date()))
        #expect(ChefTagContent.make(live, review: nil).log == ["✓ Edited Foo.swift"])
        // Quiet for a while: thinking, with the time it has been quiet.
        let quiet = ChefTagContent.make(live, review: nil, now: Date().addingTimeInterval(30))
        #expect(quiet.phase == .thinking && quiet.line.hasPrefix("thinking · 3"))
        let resting = ChefTagContent.make(agent("a", .done, freshness: .lastKnown), review: nil)
        #expect(resting.resting && resting.stale && resting.progress == nil)
        // The checklist shows as progress for this turn only.
        func step(_ status: String, turn: String) -> SessionActivityRecord {
            SessionActivityRecord(id: UUID().uuidString, provider: "Claude", sessionID: "s", turnID: turn, nativeID: UUID().uuidString, kind: "step",
                                  title: "Step", status: status, detail: "", source: "test", observedAt: Date(), data: .null)
        }
        var snapshot = SessionActivitySnapshot()
        snapshot.records = [step("completed", turn: "t2"), step("completed", turn: "t2"), step("inProgress", turn: "t2"), step("pending", turn: "t2")]
        working.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t2")
        #expect(ChefTagContent.make(working, review: nil).progress == .steps(done: 2, total: 4))
        working.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t3")
        #expect(ChefTagContent.make(working, review: nil).progress == .sweep)
        // After feedback (turn t3) the agent ticks a step off: the open steps are this turn's
        // list again, without the steps it finished before.
        snapshot.records[2].turnID = "t3"; snapshot.records[2].status = "completed"
        working.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t3")
        #expect(ChefTagContent.make(working, review: nil).progress == .steps(done: 1, total: 2))
        #expect(working.value.planProgress == .steps(done: 1, total: 2))
        // The bar shows the steps; the footer doesn't repeat them.
        var finished = working; finished.value.status = .done
        #expect(!ChefTagContent.make(working, review: nil).footer.contains("step") && ChefTagContent.make(finished, review: .awaiting).footer.isEmpty)
        // The tab names the model; the terminal's first line is the task, the same title the agent panel shows.
        let named = ChefTagContent.make(working, review: nil, model: "GPT-6-Astra", labels: labels)
        #expect(named.model == "GPT-6-Astra" && named.text == labels.title(working))
        let row = AgentSidebar.items([AgentSidebar.Input(session: Session(id: "c", provider: .claude, url: nil, sessionID: "s", title: "Can you also animate this new 3D model", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil),
                                                          agents: [working], title: labels.title(working))], catalog: [], order: { $1 })
        #expect(row.first?.title == named.text)
        // Done counts the files the whole task changed (git, as the Changes panel does), not the last turn's edits.
        #expect(ChefTagContent.make(finished, review: .awaiting, files: 36).line == "done · 36 files")
        #expect(ChefTagContent.make(finished, review: .awaiting, files: 1).line == "done · 1 file")
        #expect(ChefTagContent.make(finished, review: .awaiting).line == "done")
        let workspace = ProjectWorkspace(id: "w", folder: "/nonexistent", branch: "b", baseCommit: "c", context: ProjectContext())
        let counts = SessionChangeCounts()
        let before = counts.revision
        counts.record(workspace, ChangesSnapshot(files: (0..<36).map { ChangedFile(path: "f\($0)", status: "Modified") }, head: "h", branch: "b", dirty: true))
        #expect(counts.count(workspace) == 36 && counts.revision == before + 1)
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

    @Test func selectingAChefRingsItFollowsItAndRecedesOtherTags() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let cook = agent("a", .working, tool: "Edit", edits: true, conversation: "c1")
        let other = agent("b", .working, tool: "Read", conversation: "c2")
        view.apply(agents: [cook, other], active: false, reducedMotion: false, now: 0)
        view.fitFloor()
        let overview = try #require(view.cameraPose)
        let chef = try #require(view.chefs[cook.id])
        view.setSelection(cook.id)
        #expect(chef.root.childNode(withName: "selection ring", recursively: false) != nil)
        // Before the camera moves: the others recede to name and symbol; one that needs you
        // keeps its whole tag.
        let mine = try #require(view.chefLabels[cook.id]), theirs = try #require(view.chefLabels[other.id])
        #expect(!mine.isHidden && mine.mode == .full && mine.selected)
        #expect(!theirs.isHidden && theirs.mode == .compact && theirs.alphaValue < 1)
        let asking = agent("b", .waiting, attention: .approval, conversation: "c2")
        view.apply(agents: [cook, asking], active: false, reducedMotion: false, now: 0.5)
        #expect(theirs.mode == .full && theirs.alphaValue == 1)
        // The camera flies in and keeps the chef in view while it walks.
        var t = 0.0
        for _ in 0..<90 { t += 1 / 30; view.renderer(view, updateAtTime: t) }
        let follow = DioramaSceneView.followPose(for: chef.root.simdPosition)
        let pose = try #require(view.cameraPose)
        #expect(simd_distance(pose.look, follow.look) < 0.1 && simd_distance(pose.eye, follow.eye) < 0.2)
        view.apply(agents: [cook, other], active: false, reducedMotion: false, now: 1)
        #expect(!mine.isHidden && view.chefs[other.id]?.root.opacity ?? 1 < 1)
        // A chef out of frame takes its tag with it instead of pinning it to the edge.
        if let head = view.projectWithoutLock(try #require(view.chefs[other.id]).root.simdPosition), !view.bounds.insetBy(dx: -24, dy: -24).contains(head) {
            #expect(theirs.isHidden)
        }
        // Letting go returns the camera to the whole kitchen and drops the ring.
        view.setSelection(nil, immediately: true)
        #expect(chef.root.childNode(withName: "selection ring", recursively: false) == nil)
        for _ in 0..<120 { t += 1 / 30; view.renderer(view, updateAtTime: t) }
        #expect(view.cameraPose == overview && !view.cameraMoving)
    }

    @Test func switchingChefsGlidesAcrossInsteadOfPullingBack() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let stage = SceneStage(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let a = stage.show("A")
        let cook = agent("a1", .working, tool: "Edit", edits: true, project: "A")
        a.apply(agents: [cook], scope: "A", active: true, reducedMotion: false)
        let chef = try #require(a.chefs[cook.id])
        let b = stage.show("B")
        #expect(a.isHidden && !b.isHidden && a !== b)
        // Coming back shows the same kitchen and the same chef, not a rebuilt room.
        #expect(stage.show("A") === a && a.chefs[cook.id] === chef && b.isHidden)
        for scope in ["C", "D", "E", "F", "G"] { stage.show(scope) }
        #expect(stage.kitchens.count == SceneStage.maxKitchens && stage.kitchens["B"] == nil && stage.kitchens["A"] != nil)
    }

    @Test func catchingUpPutsChefsWhereTheirAgentsAreWithoutReplaying() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        #expect(slots.count == 3 && slots.allSatisfy { KitchenLayout.chefNavigation.isFree($0.stand) })
        // The pantry leaves the floor in front of the elevator clear: a new chef steps out there.
        #expect(KitchenLayout.chefNavigation.isFree(KitchenLayout.elevatorLanding.stand))
        #expect(slots.allSatisfy { simd_distance($0.stand, KitchenLayout.elevatorLanding.stand) > 1.0 })
        var work = TurnWork(); work.started(tool: "Skill", detail: "diorama-release", call: "1")
        let feed = AgentActivityFeed.entries(from: [ActivityEvent(id: "1", provider: "Claude", sessionID: "s", kind: "toolStarted", source: "t", callID: "1", tool: "Skill", detail: "diorama-release")])
        #expect(feed.map(\.title) == ["Fetched diorama-release"])
    }

    @Test func emptyCuttingBoardsShowTheRestingCleaver() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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

    /// The modelled range stands in the stove's footprint, flat at the worktop on the chefs' side,
    /// with a flame on each of its six burner crowns.
    @Test func theRangeFitsItsStationAndCarriesTheFlames() throws {
        let stove = try #require(KitchenStove.shared)
        let area = try #require(KitchenLayout.areas.first { $0.id == "stove" })
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let node = try #require(view.scene?.rootNode.childNode(withName: "stove", recursively: false))
        let (low, high) = node.boundingBox
        let origin = KitchenStove.origin
        #expect(origin.x + Float(low.x) >= Float(area.footprint.minX) - 0.01 && origin.x + Float(high.x) <= Float(area.footprint.maxX) + 0.01)
        #expect(origin.z + Float(low.z) >= Float(area.footprint.minY) - 0.01 && origin.z + Float(high.z) <= Float(area.footprint.maxY) + 0.01)
        #expect(stove.burners.count == 6)
        // Burners left to right, under the chefs' stove spots, just above the worktop.
        let slots = try #require(KitchenLayout.chefSlots["stove"])
        for (index, slot) in slots.enumerated() {
            let burner = try #require(stove.burner(index))
            #expect(abs(burner.x - slot.stand.x) < 0.05)
            #expect(abs(burner.y - Float(KitchenLayout.worktopHeight)) < 0.08)
            let flame = try #require(view.scene?.rootNode.childNodes.filter { $0.name == "burner flame" }.min { simd_distance($0.simdPosition, burner) < simd_distance($1.simdPosition, burner) })
            #expect(simd_distance(flame.simdPosition, burner) < 0.02)
        }
        // Where a chef sets its pot down (0.5 chef units ahead of its spot), the top is at the worktop.
        let hits = view.scene!.rootNode.hitTestWithSegment(from: SCNVector3(slots[0].stand.x - 0.4, 2, -0.002 + 0.5 * Float(KitchenLayout.chefScale)),
                                                          to: SCNVector3(slots[0].stand.x - 0.4, 0, -0.002 + 0.5 * Float(KitchenLayout.chefScale)), options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
        let top = try #require(hits.first { sequence(first: $0.node, next: \.parent).contains { $0.name == "stove" } })
        #expect(abs(Float(top.worldCoordinates.y) - Float(KitchenLayout.worktopHeight)) < 0.03)
        // Small enough to ship.
        let url = try #require(SkinnedGLBAsset.resourceBundle.url(forResource: "stove", withExtension: "glb", subdirectory: "KitchenStations"))
        #expect(try Data(contentsOf: url).count < 1_500_000)
    }

    /// The modelled island keeps the six cutting boards where the old counter had them, on its
    /// marble at the worktop, each showing its resting cleaver.
    @Test func theIslandKeepsItsBoards() throws {
        let island = try #require(KitchenIsland.shared)
        let area = try #require(KitchenLayout.areas.first { $0.id == "cooking" })
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let node = try #require(view.scene?.rootNode.childNode(withName: "cooking", recursively: false))
        #expect(island.boards.count == 6)
        let boards = node.childNodes.filter { $0.name == "cutting board" }.sorted { $0.simdWorldPosition.x < $1.simdWorldPosition.x }
        #expect(boards.count == 6)
        let slots = try #require(KitchenLayout.chefSlots["cooking"])
        for (board, slot) in zip(boards, slots) {
            let p = board.simdWorldPosition
            #expect(abs(p.x - slot.stand.x) < 0.02)
            // Where the old counter's boards were: 0.38 in from the chefs' edge.
            #expect(abs(p.z - (Float(area.footprint.minY) + 0.38)) < 0.02)
            #expect(abs(p.y - KitchenIsland.board.y / 2 - Float(KitchenLayout.worktopHeight)) < 0.01)
        }
        #expect(view.idleBoards.count == 6)
        // Inside its footprint, and small enough to ship.
        let (low, high) = node.boundingBox
        #expect(Float(low.x) + Float(area.footprint.midX) >= Float(area.footprint.minX) - 0.01 && Float(high.x) + Float(area.footprint.midX) <= Float(area.footprint.maxX) + 0.01)
        #expect(Float(low.z) + Float(area.footprint.midY) >= Float(area.footprint.minY) - 0.01 && Float(high.z) + Float(area.footprint.midY) <= Float(area.footprint.maxY) + 0.01)
        let url = try #require(SkinnedGLBAsset.resourceBundle.url(forResource: "island", withExtension: "glb", subdirectory: "KitchenStations"))
        #expect(try Data(contentsOf: url).count < 1_500_000)
    }

    /// The floor's border edges the open floor along the furniture, never under it, except on
    /// The break room is a salon: parquet over exactly its floor (inside its low walls), and the
    /// rug lies under the lounge chairs and the standing circles, inside the room.
    @Test func theBreakRoomHasParquetAndARug() throws {
        let floor = KitchenFloor.make()
        let parquet = try #require(floor.childNode(withName: "break room parquet", recursively: false))
        let rug = try #require(floor.childNode(withName: "break room rug", recursively: false))
        let room = KitchenFloor.breakRoom
        #expect(abs(CGFloat(parquet.position.x) - room.midX) < 0.01 && abs(CGFloat(parquet.position.z) - room.midY) < 0.01)
        for wall in KitchenLayout.breakRoomWalls { #expect(!room.insetBy(dx: 0.01, dy: 0.01).intersects(wall)) }
        #expect(room.contains(KitchenFloor.rug) && rug.position.y > parquet.position.y)
        for spot in BreakRoomLayout.spots where spot.kind == .chair || { if case .circle = spot.kind { return true }; return false }() {
            #expect(KitchenFloor.rug.contains(CGPoint(x: CGFloat(spot.station.stand.x), y: CGFloat(spot.station.stand.y))), "\(spot.station)")
        }
    }

    /// the pantry side, where it runs against the wall (and the pantry stands on it).
    @Test func theFloorBorderEdgesTheFurniture() {
        let (runs, corners) = KitchenFloor.borderLayout()
        #expect(runs.count == 8 && corners.count == 7)
        let squares = corners.map { CGRect(x: $0.x, y: $0.y, width: KitchenFloor.band, height: KitchenFloor.band) }
        let furniture = KitchenLayout.areas.filter { ($0.wall != .front || $0.id == "serving") && $0.id != "pantry" }.map(\.footprint)
            + KitchenLayout.connectors + KitchenLayout.breakRoomWalls
        for piece in runs + squares {
            #expect(KitchenLayout.floor.contains(piece))
            for item in furniture { #expect(!piece.insetBy(dx: 0.01, dy: 0.01).intersects(item), "\(piece) under \(item)") }
        }
        // The pantry-side run lies against the left wall.
        #expect(runs.contains { abs($0.minX - KitchenFloor.inner.minX) < 0.01 && $0.height > $0.width })
    }

    /// The French back stations stand in their footprints, and where each chef sets its idea or
    /// plate down (0.5 chef units ahead of its spot) the marble is clear, at the worktop.
    @Test func theBackStationsKeepTheirWorktopsClear() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        for id in ["order", "prep", "tasting", "pantry"] {
            let area = try #require(KitchenLayout.areas.first { $0.id == id })
            let node = try #require(view.scene?.rootNode.childNode(withName: id, recursively: false))
            #expect(node.childNodes.first?.name == id, "\(id) uses its model")
            #expect(area.footprint.insetBy(dx: -0.01, dy: -0.01).contains(worldBounds(node)), "\(id): \(worldBounds(node))")
            for slot in try #require(KitchenLayout.chefSlots[id]) {
                // Ahead of the chef (facing its station): where it sets things down, and the
                // dish it tastes at tasting.
                let ahead = id == "tasting" ? ChefAvatar.tastingSpot.z : 0.5
                let x = slot.stand.x + sin(slot.facing) * ahead * Float(KitchenLayout.chefScale)
                let z = slot.stand.y + cos(slot.facing) * ahead * Float(KitchenLayout.chefScale)
                let hits = view.scene!.rootNode.hitTestWithSegment(from: SCNVector3(x, 3, z), to: SCNVector3(x, 0, z),
                                                                  options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
                let top = try #require(hits.first { sequence(first: $0.node, next: \.parent).contains { $0.name == id } }, "\(slot.id)")
                #expect(abs(Float(top.worldCoordinates.y) - Float(KitchenLayout.worktopHeight)) < 0.03, "\(slot.id) at \(top.worldCoordinates.y)")
            }
            let url = try #require(SkinnedGLBAsset.resourceBundle.url(forResource: id, withExtension: "glb", subdirectory: "KitchenStations"))
            #expect(try Data(contentsOf: url).count < 1_500_000)
        }
    }

    /// A node's footprint on the floor (x/z), from its geometry.
    private func worldBounds(_ node: SCNNode) -> CGRect {
        var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
        node.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            let (a, b) = g.boundingBox
            for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                let w = n.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: nil)
                lo = simd_min(lo, SIMD2(w.x, w.z)); hi = simd_max(hi, SIMD2(w.x, w.z))
            } } }
        }
        return CGRect(x: CGFloat(lo.x), y: CGFloat(lo.y), width: CGFloat(hi.x - lo.x), height: CGFloat(hi.y - lo.y))
    }

    /// The Provençal pantry still opens the pantry when clicked, and its status lights glow.
    @Test func thePantryStillOpensAndGlows() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let pantry = try #require(view.scene?.rootNode.childNode(withName: "pantry", recursively: false))
        var lights = 0
        pantry.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] where m.name == "status_light" { lights += 1; #expect(m.emission.contents != nil) }
        }
        #expect(lights > 0)
        // What a click on it finds: any part of it leads up to the node named "pantry".
        var parts = 0
        pantry.enumerateHierarchy { node, _ in if node.geometry != nil { parts += 1; #expect(sequence(first: node, next: \.parent).contains { $0.name == "pantry" }) } }
        #expect(parts > 10)
    }

    /// The modelled connecting cabinets fill exactly the gaps between the wall stations.
    @Test func theConnectingCabinetsMatchTheirPlaces() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let cabinets = try #require(view.scene?.rootNode.childNode(withName: "connecting cabinets", recursively: true))
        let bounds = worldBounds(cabinets)
        let expected = KitchenLayout.connectors.reduce(CGRect.null) { $0.union($1) }
        #expect(abs(bounds.minX - expected.minX) < 0.05 && abs(bounds.maxX - expected.maxX) < 0.05, "\(bounds) vs \(expected)")
        #expect(abs(bounds.minY - expected.minY) < 0.05 && abs(bounds.maxY - expected.maxY) < 0.05)
        // Each connector's top is at the worktop.
        for r in KitchenLayout.connectors {
            let hits = view.scene!.rootNode.hitTestWithSegment(from: SCNVector3(Float(r.midX), 3, Float(r.midY)), to: SCNVector3(Float(r.midX), 0, Float(r.midY)),
                                                              options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
            let top = try #require(hits.first)
            #expect(abs(Float(top.worldCoordinates.y) - Float(KitchenLayout.worktopHeight)) < 0.03, "\(r) hit \(top.node.name ?? "?") \(top.node.parent?.name ?? "?")")
        }
    }

    /// Two stainless sinks are set into the right wall's long run: a basin (below the worktop)
    /// at each, inside that run's footprint.
    @Test func theRightWallHasTwoSinks() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let cabinets = try #require(view.scene?.rootNode.childNode(withName: "connecting cabinets", recursively: true))
        let run = KitchenLayout.connectors[4].insetBy(dx: -0.05, dy: -0.05)
        for n in 0..<2 {
            let spot = try #require(cabinets.childNode(withName: "sink_\(n)", recursively: true)).simdWorldPosition
            #expect(run.contains(CGPoint(x: CGFloat(spot.x), y: CGFloat(spot.z))))
            let hits = view.scene!.rootNode.hitTestWithSegment(from: SCNVector3(spot.x, 3, spot.z), to: SCNVector3(spot.x, 0, spot.z),
                                                              options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
            let basin = try #require(hits.first)
            #expect(basin.node.geometry?.materials.contains { $0.name.map { $0.hasPrefix("stainless") } == true } == true)
            #expect(Float(basin.worldCoordinates.y) < Float(KitchenLayout.worktopHeight) - 0.15, "sink \(n) floor at \(basin.worldCoordinates.y)")
        }
        let file = try #require(Bundle.module.url(forResource: "connectors", withExtension: "glb", subdirectory: "KitchenStations"))
        #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize! < 1_000_000)
    }

    /// A chef that needs you strikes the gong on its way to wait (not when restored or under
    /// reduced motion), holding the mallet only while it strikes.
    @Test func chefsThatNeedYouStrikeTheGongFirst() throws {
        let table = KitchenLayout.chefSlots, bell = try #require(table["bell"]?.first)
        let d = try director()
        d.place(SIMD2(0, 2.6), heading: 0)
        d.setIntent(KitchenLayout.intent(for: agent("a", .waiting, attention: .approval).value, at: bell, pickup: nil, restored: false))
        #expect(Array(d.stepNames.prefix(5)) == ["goto:gong", "face", "grab:mallet", "once:strike_gong", "release:mallet"])
        #expect(d.stepNames.suffix(4) == ["goto:bell", "face", "once:request_input", "loop:wait_input"])
        var struckHolding = false
        for _ in 0..<(60 * 12) where d.gongStrikes == 0 { d.update(1 / 60); struckHolding = d.held.contains(.mallet) }
        #expect(d.gongStrikes == 1 && struckHolding)
        run(d, seconds: 6)
        #expect(d.station == bell && !d.held.contains(.mallet) && d.clip.name == "wait_input")
        let restored = try director()
        restored.setIntent(KitchenLayout.intent(for: agent("b", .waiting, attention: .approval).value, at: bell, pickup: nil, restored: true))
        #expect(!restored.stepNames.contains("once:strike_gong"))
        let reduced = try director(); reduced.reducedMotion = true
        reduced.setIntent(KitchenLayout.intent(for: agent("c", .failed).value, at: bell, pickup: nil, restored: false))
        #expect(!reduced.stepNames.contains("once:strike_gong"))
    }

    /// At the strike's impact the mallet's felt head is on the gong's face, near its centre, and
    /// everyone waiting stands behind or beside the gong (its face stays in view), on free floor.
    @Test func theMalletLandsOnTheGong() throws {
        let assets = try ChefAssets.shared.get()
        let area = try #require(KitchenLayout.areas.first { $0.id == "bell" })
        let gong = try #require(KitchenFixtures.make(area))
        var boss: SCNNode?
        gong.enumerateHierarchy { n, _ in if n.geometry?.materials.contains(where: { $0.name == "gong_boss" }) == true { boss = n } }
        let face = try #require(boss), (lo, hi) = face.boundingBox
        let center = face.simdConvertPosition(SIMD3(Float(lo.x + hi.x) / 2, Float(lo.y + hi.y) / 2, Float(hi.z)), to: nil)
        let chef = ChefAvatar(id: "t", assets: assets, scale: KitchenLayout.chefScale, navigation: KitchenLayout.chefNavigation)
        let strike = KitchenLayout.gongStrike, bell = try #require(KitchenLayout.chefSlots["bell"]?.first)
        chef.director.place(strike.stand, heading: strike.facing)
        chef.director.setIntent(KitchenLayout.intent(for: agent("a", .waiting, attention: .approval).value, at: bell, pickup: nil, restored: false))
        for _ in 0..<(60 * 4) where chef.director.gongStrikes == 0 { chef.update(1 / 60) }
        var mallet: SCNNode?
        chef.root.enumerateHierarchy { n, _ in if n.name == "prop_gong_mallet" { mallet = n } }
        let head = try #require(mallet).simdConvertPosition(SIMD3(0, 0, 0.46), to: nil)
        #expect(abs(head.y - center.y) < 0.15 && abs(head.x - center.x) < 0.25, "head \(head) gong \(center)")
        #expect(head.z > center.z - 0.05 && head.z < center.z + 0.2, "head \(head) gong \(center)")
        let navigation = KitchenLayout.chefNavigation
        #expect(navigation.isFree(strike.stand))
        for slot in KitchenLayout.chefSlots["bell"] ?? [] {
            // In front of the gong (the camera's side), facing it.
            let toward = KitchenLayout.gongCenter - slot.stand
            #expect(navigation.isFree(slot.stand) && slot.stand.y > KitchenLayout.gongCenter.y - 0.4, "\(slot)")
            #expect(abs(atan2(toward.x, toward.y) - slot.facing) < 0.01, "\(slot) faces the gong")
        }
    }

    @Test func theManagerVisitsWhoeverWaitedLongest() {
        let waiting = [KitchenManager.Waiting(id: "b", since: 5), KitchenManager.Waiting(id: "a", since: 3)]
        #expect(KitchenManager.next(current: nil, waiting: waiting) == "a")
        #expect(KitchenManager.next(current: "b", waiting: waiting) == "b")      // stays until answered
        #expect(KitchenManager.next(current: "c", waiting: waiting) == "a")
        #expect(KitchenManager.next(current: "a", waiting: []) == nil)           // nobody waits: leaves
    }

    /// End to end: the chef strikes the gong (it shivers), waits in front of it, the manager comes in
    /// from the dining room and they talk; once you answer the manager walks back out.
    @Test func theManagerComesWhenTheGongSounds() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var clock = 100.0
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 30) {
                clock += 1 / 30
                for chef in view.chefs.values { chef.update(1 / 30) }
                view.manager?.update(1 / 30)
                view.pace(now: clock); view.updateManager(); view.updateGong()
            }
        }
        view.apply(agents: [agent("a", .working, tool: "Edit", edits: true)], active: false, reducedMotion: false, now: clock)
        step(0.5)
        #expect(view.manager == nil)
        view.apply(agents: [agent("a", .waiting, attention: .approval, edits: true)], active: false, reducedMotion: false, now: clock)
        let chef = try #require(view.chefs.values.first)
        for _ in 0..<200 where chef.director.gongStrikes == 0 { step(0.1) }
        #expect(chef.director.gongStrikes == 1)
        let pivot = try #require(view.scene?.rootNode.childNode(withName: KitchenFixtures.gongPivot, recursively: true))
        #expect(pivot.hasActions)
        for _ in 0..<300 where view.managerTalking == nil { step(0.1) }
        let manager = try #require(view.manager)
        #expect(view.managerTalking == chef.id)
        step(1.5)
        #expect(manager.director.clip.name == "manager_talk" && chef.director.clip.name == "talk_reply")
        // They face each other.
        let between = manager.director.position - chef.director.position
        #expect(abs(ChefDirector.wrap(atan2(between.x, between.y) - chef.director.heading)) < 0.2)
        #expect(abs(ChefDirector.wrap(atan2(-between.x, -between.y) - manager.director.heading)) < 0.2)
        // You answer: the chef goes back to work and the manager leaves through the dining room.
        view.apply(agents: [agent("a", .working, tool: "Edit", edits: true)], active: false, reducedMotion: false, now: clock)
        for _ in 0..<300 where view.manager != nil { step(0.1) }
        #expect(view.manager == nil && view.managerTalking == nil)
    }

    /// Resting chefs take the machines first, then the chairs, then the circles; a machine has one
    /// user at a time, everyone gets a turn on one, and in a group mostly one talks at a time.
    @Test func theBreakRoomTakesTurnsAndConversations() throws {
        let durations = try ChefAssets.shared.get().manifest.clips.mapValues { Double($0.duration) }
        var room = BreakRoom(durations: durations)
        let ids = (0..<10).map { "c\($0)" }
        _ = room.update(resting: ids, now: 0)
        let kinds = ids.compactMap { room.kind(of: $0) }
        #expect(kinds.filter { [.arcade, .vending].contains($0) }.count == 4)
        #expect(kinds.filter { $0 == .chair }.count == 2 && kinds.count == 10)
        var machineUsers: Set<String> = [], bothTalking = 0, samples = 0
        for t in stride(from: 0.0, through: 600, by: 0.5) {
            _ = room.update(resting: ids, now: t)
            let spots = room.members.values.map(\.spot)
            #expect(Set(spots).count == spots.count) // one chef per spot, so one per machine
            for (id, kind) in ids.compactMap({ id in room.kind(of: id).map { (id, $0) } }) where [.arcade, .vending, .espresso].contains(kind) { machineUsers.insert(id) }
            for g in 0..<2 {
                let group = room.members.values.filter { room.spots[$0.spot].kind == .circle(g) }
                if group.count >= 2 { samples += 1; if group.filter({ BreakRoom.talking.contains($0.clip) }).count > 1 { bothTalking += 1 } }
            }
        }
        #expect(machineUsers.count >= 8, "\(machineUsers.sorted())")
        #expect(Double(bothTalking) < Double(samples) * 0.2)
        // A chef that leaves frees its spot; the next one in takes it.
        _ = room.update(resting: Array(ids.dropFirst()), now: 601)
        #expect(room.members.count == 9)
    }

    /// The machines stand against the far wall (facing the camera) or the left wall (facing the
    /// room), inside the room, sized from their models; every spot is free floor; each machine is
    /// on screen and unhidden in the kitchen view, and its file is small.
    @Test func theBreakRoomMachinesStandWhereTheyShow() throws {
        let room = KitchenFloor.breakRoom.insetBy(dx: -0.01, dy: -0.01)
        #expect(abs(0.43 * 1.4 - KitchenLayout.chefCounterFront * KitchenLayout.chefScale) < 0.001)
        let models = KitchenFood.models(in: "BreakRoom")
        for machine in BreakRoomLayout.machines {
            #expect(room.contains(machine.rect), "\(machine.asset)")
            if machine.facing == 0 { #expect(abs(Float(machine.rect.minY) - BreakRoomLayout.farWall) < 0.05) }
            else { #expect(abs(Float(machine.facing) - .pi / 2) < 0.01 && Float(machine.rect.minX) < BreakRoomLayout.leftWall + 0.05 + (machine.onBar ? BreakRoomLayout.coffeeBarDepth : 0)) }
            let model = try #require(models[machine.asset]), (lo, hi) = model.boundingBox
            #expect(abs(Float(hi.x - lo.x) * machine.scale - machine.size.x) < 0.05 && abs(Float(hi.z - lo.z) * machine.scale - machine.size.y) < 0.05, "\(machine.asset)")
            let file = try #require(SkinnedGLBAsset.resourceBundle.url(forResource: machine.asset, withExtension: "glb", subdirectory: "BreakRoom"))
            #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize! < 1_500_000)
        }
        let navigation = KitchenLayout.chefNavigation
        for spot in BreakRoomLayout.spots { #expect(navigation.isFree(spot.station.stand), "\(spot.station)") }
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        for machine in BreakRoomLayout.machines {
            let node = try #require(view.scene?.rootNode.childNode(withName: "break machine:" + machine.asset, recursively: true))
            let (lo, hi) = node.boundingBox
            for corner in [SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, hi.y, hi.z), SCNVector3(lo.x, hi.y, hi.z), SCNVector3(hi.x, lo.y, lo.z)] {
                let p = view.projectPoint(node.convertPosition(corner, to: nil))
                #expect(p.x >= 0 && p.x <= 1000 && p.y >= 0 && p.y <= 700, "\(machine.asset) \(p)")
            }
            // Looking at its middle from the camera, the first thing hit is the machine itself.
            let mid = node.convertPosition(SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) * 0.6, (lo.z + hi.z) / 2), to: nil)
            let eye = try #require(view.pointOfView).position
            let hit = view.scene!.rootNode.hitTestWithSegment(from: eye, to: mid, options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue]).first
            #expect(hit.map { sequence(first: $0.node, next: \.parent).contains { $0 === node } } ?? true, "\(machine.asset) hidden by \(hit?.node.name ?? "?")")
        }
    }

    /// End to end: ten resting chefs, of whom the six most recent stay; they fill the four machines
    /// and the two chairs; talking and laughing put up emoji bubbles, at most four at once.
    @Test func restingChefsPlayChatAndTakeTurns() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        var clock = 100.0, mostBubbles = 0, emoji = Set<String>()
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 10) {
                clock += 0.1
                for chef in view.chefs.values { chef.update(0.1) }
                view.pace(now: clock); view.updateBreakRoom(now: clock); view.placeBubbles(now: clock)
                mostBubbles = max(mostBubbles, view.bubbleEmoji.count); emoji.formUnion(view.bubbleEmoji.values)
            }
        }
        let resting = (0..<10).map { agent("r\($0)", .done, freshness: .lastKnown, conversation: "rest\($0)") }
        view.apply(agents: resting, active: false, reducedMotion: false, now: clock)
        step(20)
        let loops = view.chefs.values.compactMap { $0.director.intent?.loop }
        #expect(loops.filter { $0 == "play_arcade" }.count == 3, "\(loops.sorted())")
        #expect(loops.filter { $0 == "stand_sip" }.count == 1)
        let atMachines = Set(view.chefs.compactMap { id, _ in [BreakRoomLayout.Kind.arcade, .vending].contains(view.breakRoom.kind(of: id)) ? id : nil })
        #expect(atMachines.count == 4)
        #expect(view.chefs.count == DioramaSceneView.maxResting && view.chefs.values.filter { $0.director.station?.area == "break" }.count == 6)
        step(120)
        let later = Set(view.chefs.compactMap { id, _ in [BreakRoomLayout.Kind.arcade, .vending].contains(view.breakRoom.kind(of: id)) ? id : nil })
        #expect(later.count == 4)
        #expect(mostBubbles > 0 && mostBubbles <= 4 && !emoji.isEmpty, "\(emoji)")
    }

    @Test func burnersIgniteOnlyWhereChefsCook() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.apply(agents: [], scope: "p", active: false, reducedMotion: false, now: 0)
        let first = agent("first", .working, tool: "Read")
        view.apply(agents: [first], scope: "p", active: false, reducedMotion: false, now: 1)
        #expect(view.chefs[first.id]?.director.intent?.key.hasPrefix("arrival") == true)
    }

    @Test func onlyNewAgentsArriveByElevator() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let old = agent("old", .working, tool: "Edit", edits: true), new = agent("new", .working, tool: "Read")
        view.apply(agents: [old], active: false, reducedMotion: false, now: 0)
        #expect(view.chefs[old.id]?.director.intent?.station?.area == "cooking")
        view.apply(agents: [old, new], active: false, reducedMotion: false, now: 1)
        let newcomer = try #require(view.chefs[new.id])
        let door = try #require(KitchenLayout.chefSlots["elevator"]?.first)
        #expect(simd_distance(newcomer.director.position, door.stand) < 0.01)
        // First it steps out of the elevator and waves to the camera; the doors stand open.
        #expect(newcomer.director.intent?.key == "arrival-exit" && newcomer.director.intent?.station == KitchenLayout.elevatorLanding)
        #expect(newcomer.director.intent?.oneShot?.clip == "arrive_wave" && KitchenLayout.elevatorLanding.facing == 0)
        #expect(view.elevatorOpen)
        var clock = 1.0, waved = false, read = false
        for _ in 0..<(30 * 6) {
            clock += 1 / 30; newcomer.update(1 / 30); view.pace(now: clock)
            waved = waved || newcomer.director.clip.name == "arrive_wave"
            if newcomer.director.intent?.loop == "read_ticket" { read = true; break }
        }
        // Then on to the rail with its ticket.
        #expect(waved && read && newcomer.director.intent?.hand == .ticket)
        for _ in 0..<(30 * 12) { clock += 1 / 30; newcomer.update(1 / 30); view.pace(now: clock); view.frameStep(at: clock) }
        #expect(!view.elevatorOpen)
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        for point in [SIMD3<Float>(0, 0, 0), SIMD3(-9, 2.8, -6), SIMD3(8, 1, 6), SIMD3(3, 3.5, -2)] {
            let mine = try #require(view.projectWithoutLock(point))
            let scene = view.projectPoint(SCNVector3(point))
            #expect(abs(mine.x - CGFloat(scene.x)) < 1 && abs(mine.y - CGFloat(scene.y)) < 1, "\(point): \(mine) vs \(scene)")
        }
    }

    @Test func neighbouringNameTagsNeverOverlap() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        view.apply(agents: (0..<10).map { agent("r\($0)", .working, tool: "Read", conversation: "c\($0)") }, active: false, reducedMotion: false)
        let tags = view.chefLabels.values.map(\.frame)
        #expect(tags.count == 10)
        for (i, a) in tags.enumerated() { for b in tags.dropFirst(i + 1) { #expect(!a.intersects(b)) } }
    }

    @Test func crowdedTagsKeepTheOneThatNeedsYouOpen() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        // Everyone waiting at the bell stands close together.
        let cast = [agent("w", .waiting, attention: .input, conversation: "c1")] + (0..<4).map { agent("x\($0)", .working, tool: "Read", conversation: "d\($0)") }
        view.apply(agents: cast, active: false, reducedMotion: true)
        let waiting = try #require(view.chefLabels[cast[0].id])
        #expect(waiting.mode == .full)
        let frames = view.chefLabels.values.map(\.frame)
        for (i, a) in frames.enumerated() { for b in frames.dropFirst(i + 1) { #expect(!a.intersects(b)) } }
    }

    @Test func kitchenViewReconcilesChefsAndPlaysOnlyWhileActive() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.apply(agents: [], active: true, reducedMotion: false)
        // No chefs, but the restaurant's guests keep it moving while it's on screen.
        #expect(view.chefs.isEmpty && view.isPlaying)
        view.apply(agents: [], active: false, reducedMotion: false)
        #expect(!view.isPlaying)
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

    /// The scene as a PNG with its emoji bubbles drawn over it (`snapshot` renders the 3D view only).
    private func composited(_ view: DioramaSceneView) throws -> Data {
        let image = view.snapshot()
        let canvas = NSImage(size: view.bounds.size)
        canvas.lockFocus()
        image.draw(in: view.bounds)
        for placed in view.subviews.compactMap({ $0 as? ChefBubbleView }) where !placed.isHidden {
            // Drawn from a stand-alone copy: inside the scene view, caching would start from the
            // opaque scene view behind it (black offscreen), unlike the composited window.
            let bubble = ChefBubbleView(frame: placed.frame); bubble.show(placed.emoji, now: 0, reducedMotion: true)
            let rep = try #require(bubble.bitmapImageRepForCachingDisplay(in: bubble.bounds))
            // The caching buffer starts uncleared: clear it so the bubble keeps its transparency.
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.clear.set(); bubble.bounds.fill(using: .copy); NSGraphicsContext.restoreGraphicsState()
            bubble.cacheDisplay(in: bubble.bounds, to: rep)
            let frame = view.isFlipped ? CGRect(x: placed.frame.minX, y: view.bounds.height - placed.frame.maxY, width: placed.frame.width, height: placed.frame.height) : placed.frame
            rep.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        canvas.unlockFocus()
        let tiff = try #require(canvas.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    /// A clip of a chef that needs you (DIORAMA_GONG_DEMO=1): it leaves the stove, strikes the
    /// gong, waits in front of it, and the head chef walks in from the dining room to talk. Frames go
    /// to .local/demo/gong-frames (30 fps); encode them with ffmpeg.
    @Test func recordGongDemo() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_GONG_DEMO"] == "1" else { return }
        let lead = Double(ProcessInfo.processInfo.environment["DIORAMA_GONG_LEAD"] ?? "") ?? 4
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../.local/demo/gong-frames").standardized
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        view.characters = ChefCharacterModel(url: nil)
        var clock = 100.0
        func step(_ dt: Double) {
            clock += dt
            for chef in view.chefs.values { chef.update(Float(dt)) }
            view.manager?.update(Float(dt))
            view.pace(now: clock); view.updateBreakRoom(now: clock); view.updateManager(); view.updateGong(); view.updateEffects()
            // SceneKit actions (the manager's fade-in) don't run offscreen; the app shows him as he walks in.
            if let manager = view.manager, manager.root.opacity < 1 { manager.root.removeAllActions(); manager.root.opacity = 1 }
        }
        let crew = [agent("edit", .working, tool: "Edit", edits: true, conversation: "crew-edit"),
                    agent("plan", .working, tool: "TaskCreate", conversation: "crew-plan"),
                    agent("test", .working, tool: "Bash", detail: "swift test", edits: true, conversation: "crew-test")]
            + (0..<3).map { agent("r\($0)", .done, freshness: .lastKnown, conversation: "rest\($0)") }
        let busy = agent("you", .working, tool: "Bash", detail: "make", edits: true, conversation: "needs-you")
        view.apply(agents: crew + [busy], active: false, reducedMotion: false, now: clock)
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        for _ in 0..<(15 * 30) { step(1 / 30) }          // everyone settles at their stations
        // The agent asks for approval: its chef heads for the gong (the clip starts as it nears it).
        let asking = agent("you", .waiting, attention: .approval, edits: true, conversation: "needs-you")
        view.apply(agents: crew + [asking], active: false, reducedMotion: false, now: clock)
        for _ in 0..<Int(lead * 30) { step(1 / 30) }
        let camera = try #require(view.pointOfView)
        let center = SIMD3<Float>(0.8, 0.9, 5.4), elevation: Float = KitchenCameraController.elevationDegrees * .pi / 180
        let frames = 285
        // The sounds the app would play, frame by frame (as `playSounds` pans and mutes them).
        var soundLog: [String] = []
        for chef in Array(view.chefs.values) + (view.manager.map { [$0] } ?? []) { chef.heard = [] }
        for frame in 0..<frames {
            step(1 / 30)
            for chef in Array(view.chefs.values) + (view.manager.map { [$0] } ?? []) where !chef.heard.isEmpty {
                let sounds = chef.heard; chef.heard = []
                let spot = chef.director.position
                if chef.director.station?.area == "break" || view.quietArea.contains(CGPoint(x: CGFloat(spot.x), y: CGFloat(spot.y))) { continue }
                let point = view.projectWithoutLock(chef.root.simdWorldPosition)
                let x = point.map { Float($0.x / view.bounds.width) } ?? 0.5
                let level: Float = x >= 0 && x <= 1 ? 1 : 0.35
                for sound in sounds { soundLog.append(String(format: "%.4f %@ %d %.3f %.3f", Double(frame) / 30, sound.rawValue, sound.variants, (x * 2 - 1) * 0.7, sound.volume * level)) }
            }
            let distance = 13.5 - 2 * Float(frame) / Float(frames)   // a slow push in
            camera.simdPosition = center + SIMD3(0, distance * sin(elevation), distance * cos(elevation))
            camera.simdLook(at: center)
            try composited(view).write(to: folder.appendingPathComponent(String(format: "f%04d.png", frame)))
            if frame == frames - 1 { try soundLog.joined(separator: "\n").write(to: folder.appendingPathComponent("sounds.txt"), atomically: true, encoding: .utf8) }
            if frame % 15 == 0 {
                let chef = view.chefs.first { $0.key.hasSuffix(":you") }?.value
                print("GONG t=\(Double(frame) / 30)s chef=\(chef?.director.clip.name ?? "-") at=\(chef?.director.station?.id ?? "-") strikes=\(chef?.director.gongStrikes ?? 0) manager=\(view.manager.map { $0.director.station?.id ?? "walking" } ?? "-") talking=\(view.managerTalking != nil)")
            }
        }
    }

    /// A ten-second demo of the break room (DIORAMA_KITCHEN_DEMO=1): the camera close over the room,
    /// chefs at the machines, in the chairs and chatting with emoji bubbles, a machine changing
    /// hands, and a chef who just finished tasting running in to rest. Frames go to
    /// .local/demo/frames (1920 x 1080 at 30 fps); encode them with ffmpeg.
    @Test func recordBreakRoomDemo() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_KITCHEN_DEMO"] == "1" else { return }
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../.local/demo/frames").standardized
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 960, height: 540))
        var clock = 100.0
        func step(_ dt: Double) {
            clock += dt
            for chef in view.chefs.values { chef.update(Float(dt)) }
            view.pace(now: clock); view.updateBreakRoom(now: clock)
        }
        let resting = (0..<9).map { agent("r\($0)", .done, freshness: .lastKnown, conversation: "rest\($0)") }
        // The newcomer works at the Tasting pass (it hands out nothing to carry) until it finishes.
        let cook = agent("cook", .working, tool: "Bash", detail: "swift test", edits: true, conversation: "cooking")
        view.apply(agents: resting + [cook], active: false, reducedMotion: false, now: clock)
        view.layoutSubtreeIfNeeded(); view.fitFloor()
        for _ in 0..<(20 * 30) { step(1 / 30) }            // everyone settles
        // Start so the first machine hand-over lands about halfway through the clip.
        let swap = view.breakRoom.members.values.compactMap(\.turnEnds).min() ?? clock
        let finished = agent("cook", .done, freshness: .lastKnown, conversation: "cooking")
        for _ in 0..<Int(max(0, swap - 9.5 - clock) * 30) { step(1 / 30) }
        // It finishes and sets off across the kitchen, arriving on camera early in the clip.
        view.apply(agents: resting + [finished], active: false, reducedMotion: false, now: clock)
        for _ in 0..<(4 * 30) { step(1 / 30) }
        let camera = try #require(view.pointOfView)
        let center = SIMD3<Float>(-7.6, 0.9, 5.65), elevation: Float = KitchenCameraController.elevationDegrees * .pi / 180
        let frames = 300
        for frame in 0..<frames {
            step(1 / 30)
            // A slow push in over the clip.
            let distance = 8.6 - 0.9 * Float(frame) / Float(frames)
            camera.simdPosition = center + SIMD3(0, distance * sin(elevation), distance * cos(elevation))
            camera.simdLook(at: center)
            view.placeBubbles(now: clock)
            try composited(view).write(to: folder.appendingPathComponent(String(format: "f%04d.png", frame)))
        }
        #expect(view.chefs["cook"]?.director.intent?.station?.area == "break" || view.chefs.values.contains { $0.id.hasSuffix("cook") })
    }

    /// The break room with ten resting chefs at the machines, in the chairs and chatting, with
    /// their emoji bubbles drawn over the scene (DIORAMA_KITCHEN_CAPTURE=1; /tmp/diorama-kitchen-lounge*.png).
    @Test func captureBreakRoom() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_KITCHEN_CAPTURE"] == "1" else { return }
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        var clock = 100.0
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 10) {
                clock += 0.1
                for chef in view.chefs.values { chef.update(0.1) }
                view.pace(now: clock); view.updateBreakRoom(now: clock)
            }
        }
        func shot(_ name: String) throws {
            view.layoutSubtreeIfNeeded(); view.fitFloor(); view.placeBubbles(now: clock)
            try composited(view).write(to: URL(fileURLWithPath: "/tmp/diorama-kitchen-\(name).png"))
        }
        view.apply(agents: (0..<10).map { agent("r\($0)", .done, freshness: .lastKnown, conversation: "rest\($0)") }, active: false, reducedMotion: false, now: clock)
        step(24)
        try shot("lounge")
        step(9.3)
        try shot("lounge-later")
        for _ in 0..<300 where view.bubbleEmoji.count < 2 { step(0.1); view.placeBubbles(now: clock) }
        try shot("lounge-bubbles")
    }

    /// The gong and the manager: a chef mid-strike, then the manager talking with it while a
    /// second chef waits (DIORAMA_KITCHEN_CAPTURE=1; /tmp/diorama-kitchen-gong-*.png).
    @Test func captureGongAndManager() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_KITCHEN_CAPTURE"] == "1" else { return }
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        var clock = 100.0
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 30) {
                clock += 1 / 30
                for chef in view.chefs.values { chef.update(1 / 30) }
                view.manager?.update(1 / 30)
                view.pace(now: clock); view.updateManager(); view.updateGong()
            }
        }
        func shot(_ name: String) throws {
            view.layoutSubtreeIfNeeded(); view.fitFloor()
            let tiff = try #require(view.snapshot().tiffRepresentation)
            try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-kitchen-gong-\(name).png"))
        }
        let cooks = [agent("a", .working, tool: "Edit", edits: true, conversation: "g1"), agent("b", .working, tool: "Read", conversation: "g2")]
        view.apply(agents: cooks, active: false, reducedMotion: false, now: clock)
        step(0.5)
        view.apply(agents: [agent("a", .waiting, attention: .approval, edits: true, conversation: "g1"), cooks[1]], active: false, reducedMotion: false, now: clock)
        let chef = try #require(view.chefs[cooks[0].id])
        for _ in 0..<600 where chef.director.gongStrikes == 0 { step(1 / 30) }
        try shot("strike")
        view.apply(agents: [agent("a", .waiting, attention: .approval, edits: true, conversation: "g1"), agent("b", .failed, conversation: "g2")],
                   active: false, reducedMotion: false, now: clock)
        for _ in 0..<300 where view.managerTalking == nil { step(0.1) }
        step(2.2)
        view.manager?.root.removeAllActions(); view.manager?.root.opacity = 1 // actions only run while the view plays
        try shot("talk")
    }

    @Test func captureKitchenWithChefs() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_KITCHEN_CAPTURE"] == "1" else { return }
        func capture(_ agents: [SpatialAgent], _ name: String) throws {
            let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
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
            let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
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
            let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
            let cast = [agent("ask", .waiting, attention: .approval), agent("q", .waiting, attention: .input), agent("done", .done),
                        agent("e1", .working, tool: "Edit", edits: true), agent("e2", .working, tool: "Bash", detail: "npm test"),
                        agent("e3", .working, tool: "Read"), agent("e4", .working, tool: "Skill"), agent("e5", .working, tool: "Edit", edits: true)]
            view.apply(agents: cast, active: false, reducedMotion: true)
            for chef in view.chefs.values { for _ in 0..<30 { chef.update(1 / 30) } }
            for (id, emote) in zip(["e1", "e2", "e3", "e4", "e5"], [ChefEmote.note, .check, .thinking, .plus, .idea]) {
                view.chefLabels[cast.first { $0.value.id == id }!.id]?.react([emote])
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
            for overlay in view.subviews where !overlay.isHidden && overlay is ChefTagView {
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

    @Test func momentsMoveTheTagOnlyWithMotionAllowed() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let waiting = agent("w", .waiting, attention: .approval), cook = agent("c", .working, tool: "Edit", edits: true)
        view.apply(agents: [waiting, cook], active: false, reducedMotion: false)
        let tag = try #require(view.chefLabels[waiting.id])
        #expect(tag.content?.phase == .approval && tag.mode == .full && !tag.isHidden)
        // Needing you pulses; Reduce Motion stills everything.
        func animated(_ view: NSView) -> Bool { !(view.layer?.animationKeys() ?? []).isEmpty || view.subviews.contains(where: animated) }
        #expect(animated(tag))
        view.apply(agents: [waiting, cook], active: false, reducedMotion: true)
        tag.react([.alert])
        #expect(!animated(tag))
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

    @Test func choppingHappensOnTheChoppedBoard() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let cook = agent("c", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: true, now: 0)
        let chef = try #require(view.chefs[cook.id])
        // Let it reach its board and start chopping.
        var t = 0.0
        for _ in 0..<600 where chef.director.clip.name != "working_chop" { t += 1 / 30; chef.update(1 / 30); view.renderer(view, updateAtTime: t) }
        for _ in 0..<3 { chef.update(1 / 30) }
        #expect(chef.director.station?.area == "cooking" && chef.director.clip.name == "working_chop")
        #expect(chef.choppingOnBoard && chef.dishPlacement != "board")
        view.updateBoards()
        #expect(!view.idleBoards.contains(try #require(chef.director.station?.id)))
    }

    @Test func theProgressBarShowsOneBlockPerStepUnderThePill() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        var cook = agent("c", .working, tool: "Edit", edits: true)
        view.apply(agents: [cook], active: false, reducedMotion: false)
        let tag = try #require(view.chefLabels[cook.id]), bar = tag.bar
        // Working without a list: a sweep, not a fraction.
        #expect(!bar.isHidden && bar.progress == .sweep)
        func step(_ status: String) -> SessionActivityRecord {
            SessionActivityRecord(id: UUID().uuidString, provider: "Claude", sessionID: "s", turnID: "t", nativeID: UUID().uuidString, kind: "step",
                                  title: "Step", status: status, detail: "", source: "test", observedAt: Date(), data: .null)
        }
        var snapshot = SessionActivitySnapshot()
        snapshot.records = [step("completed"), step("inProgress"), step("pending"), step("pending")]
        cook.value.plan = AgentPlan.reported(in: snapshot, provider: "Claude", sessionID: "s", currentTurn: "t")
        view.apply(agents: [cook], active: false, reducedMotion: false)
        // One block per step, the done ones filled, right under the pill and as wide as it.
        #expect(!bar.isHidden && bar.progress == .steps(done: 1, total: 4) && bar.blocks == 4 && bar.filled == 1)
        #expect(bar.frame.minY == tag.pillFrame.maxY + ChefTagView.barGap && bar.frame.width == tag.pillFrame.width)
        // Idle: the name and its latest task, no bar.
        view.apply(agents: [agent("c", .ready)], active: false, reducedMotion: false)
        #expect(tag.mode == .compact && bar.isHidden && tag.alphaValue == 1)
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
        #expect(KitchenLayout.work(for: waiting.value).area == "bell" && ChefTagContent.make(waiting, review: nil).phase == .waiting)
    }
}

extension ChefKitchenTests {
    @Test func aCommandThatTestsAndBuildsVisitsBothStationsInOrder() throws {
        #expect(KitchenActivity.stations(command: "npm test && npm run build") == [.testing, .commands])
        #expect(KitchenActivity.stations(command: "npm run build; npm test") == [.commands, .testing])
        #expect(KitchenActivity.stations(command: "node - <<'NODE'\nconsole.log(1)\nNODE\nnpm test\nnpm run build") == [.commands, .testing, .commands])
        #expect(KitchenActivity.stations(command: "git status; cat math.js") == [])
        // Eli's last step: tests and a build in one command, just before finishing.
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        view.apply(agents: resters + [served], active: false, reducedMotion: false, now: 1 + DioramaSceneView.walkOff + 1)
        #expect(view.chefs[served.id] == nil && view.chefs.count == view.maxResting)
        // Feedback counts as work: a reworking chef is always in the kitchen.
        view.reviews = ["c": .reworking]
        view.apply(agents: resters + [served], active: false, reducedMotion: false, now: 40)
        #expect(view.chefs[served.id]?.director.intent?.station?.area == "prep")
    }

    @Test func everyoneWithWorkIsShownAndTheBreakRoomKeepsTheMostRecent() {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1600, height: 900))
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
        // A few seconds in: the guests settle into what they're doing.
        for step in 0..<(30 * 7) {
            view.serveDiners(now: Double(step) / 30)
            for diner in view.diners { diner.update(1 / 30) }
        }
        try save("home")
        eye0: do {
            let eye = SCNNode(); eye.camera = view.pointOfView?.camera?.copy() as? SCNCamera
            view.scene?.rootNode.addChildNode(eye); renderer.pointOfView = eye
            eye.position = SCNVector3(9, 5, 17); eye.look(at: SCNVector3(8, 0.8, 11.5)); try save("diners")
            // Close on the guests along the right-hand side.
            eye.position = SCNVector3(8.5, 4.2, 3.5); eye.look(at: SCNVector3(13.6, 0.9, -0.5)); try save("guests")
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
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let restaurant = try #require(KitchenRestaurant.shared)
        // Diners sit at the tables nearest the pass, hatless, facing their tables.
        let diners = try #require(view.scene?.rootNode.childNodes.filter { $0.name?.hasPrefix("diner:") == true })
        #expect(diners.count == DioramaSceneView.dinerCount)
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
        // The served dish takes the place of the food on that table; the guest cheers, then eats.
        #expect(view.tablePlates[0]?.isHidden == true)
        #expect(view.guests.seats[0].clip == RestaurantGuests.cheer)
        #expect(view.diners[0].director.intent?.oneShot?.clip == RestaurantGuests.cheer)
        view.serveDiners(now: 3)
        #expect(view.guests.seats[0].clip == RestaurantGuests.eat)
        // Accepted: the chef leaves the pass; the diner finishes eating, then the table clears.
        view.reviews = ["served": .approved]
        view.apply(agents: [done], active: false, reducedMotion: false, now: 2)
        for _ in 0..<30 { chef.update(1 / 30) }
        view.serveDiners(now: 3)
        #expect(view.servedSeats["served"] == 0)
        view.serveDiners(now: 3 + DioramaSceneView.dinerLinger + 1)
        #expect(view.servedSeats["served"] == nil)
        #expect(view.tablePlates[0]?.isHidden == false)
    }

    @Test func theRestaurantSeatsEveryGuestWithFoodOnEveryTable() throws {
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let assets = try ChefAssets.shared.get()
        #expect(assets.guests.count == 10)
        #expect(view.diners.count == DioramaSceneView.dinerCount)
        let worn = view.diners.map(\.character)
        #expect(Set(worn) == Set(assets.guests.map(\.id)), "every guest is seated at least once")
        #expect(view.tablePlates.count == view.diners.count && view.tablePlates.allSatisfy { $0 != nil })
        // The two repeats never share a table with their twin.
        for (seat, partner) in view.guests.partners.enumerated() {
            if let partner { #expect(worn[seat] != worn[partner]) }
        }
        // Guests are drawn but never picked as chefs.
        for diner in view.diners { #expect(diner.root.categoryBitMask == DioramaSceneView.dinerCategory) }
        // Each guest is the right character on the chef's skeleton.
        for guest in assets.guests { #expect(assets.rig(for: guest.id).nodeNames == assets.rig.nodeNames) }
    }

    @Test func guestsChatOnTheirOwnClocksAndTakeTurns() throws {
        let durations = try ChefAssets.shared.get().manifest.clips.mapValues { Double($0.duration) }
        // Two tables of two.
        let positions: [SIMD3<Float>] = [SIMD3(0, 1, 0), SIMD3(1, 1, 0), SIMD3(10, 1, 0), SIMD3(11, 1, 0)]
        var guests = RestaurantGuests(positions: positions, durations: durations)
        #expect(guests.partners == [1, 0, 3, 2])
        var seen: [Set<String>] = Array(repeating: [], count: 4)
        var changes: [[Double]] = Array(repeating: [], count: 4)
        var bothTalking = 0, samples = 0
        for step in 0..<(600 * 10) {
            let now = Double(step) / 10
            for seat in guests.update(now: now) { seen[seat].insert(guests.seats[seat].clip); changes[seat].append(now) }
            for (a, b) in [(0, 1), (2, 3)] {
                samples += 1
                if RestaurantGuests.talking.contains(guests.seats[a].clip) && RestaurantGuests.talking.contains(guests.seats[b].clip) { bothTalking += 1 }
            }
        }
        // Everyone does a bit of everything: talks, eats, laughs.
        for clips in seen { #expect(clips.isSuperset(of: ["sit_talk", "sit_eat", "sit_laugh"])) }
        // Not in lockstep: their changes don't line up.
        #expect(Set(changes[0]) != Set(changes[1]) && Set(changes[0]) != Set(changes[2]))
        // Partners rarely talk over each other.
        #expect(Double(bothTalking) / Double(samples) < 0.2)
    }

    @Test func guestCastingRepeatsAsFarApartAsPossible() {
        let seats = (0..<12).map { SIMD3<Float>(Float($0 / 2) * 4, 1, Float($0 % 2)) }
        let cast = RestaurantGuests.cast((0..<10).map { "g\($0)" }, seats: seats)
        #expect(cast.count == 12 && Set(cast).count == 10)
        for guest in Set(cast) {
            let at = cast.indices.filter { cast[$0] == guest }
            if at.count == 2 { #expect(simd_distance(seats[at[0]], seats[at[1]]) > 4) }
        }
    }
}
