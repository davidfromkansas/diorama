import SceneKit
import simd

/// Shared chef resources, loaded once: skinned rig, prop templates and manifest.
@MainActor final class ChefAssets {
    static let spec = WorkspaceCapybaraAsset.Spec(
        skeletonRoot: "chef_rig", jointCount: 26,
        requiredClips: ["idle_available", "walk", "run", "carry_idle", "carry_walk", "planning_recipe", "researching_book",
                        "working_chop", "waiting_tool", "testing_dish", "request_input", "wait_input", "blocked_wait",
                        "error_react", "present_review", "wait_review", "unknown_wait", "cancel_cleanup", "pickup",
                        "blocked_react", "celebrate_done", "arrive_wave", "read_ticket", "sit_down", "stand_up",
                        "sit_idle", "sit_sip", "sit_chat", "sit_talk", "sit_laugh", "sit_gesture", "sit_eat", "sit_cheer", "cover_dish",
                        "merge_ready", "merge_ready_wait", "fix_react", "fix_wait", "strike_gong", "talk_reply", "manager_talk",
                        "play_arcade", "use_vending", "brew_espresso", "stand_sip", "stand_listen", "stand_laugh"],
        instanceName: "chef")
    static let shared: Result<ChefAssets, Error> = Result { try ChefAssets() }
    let rig: WorkspaceCapybaraAsset
    let props: [String: SCNNode]
    let manifest: ChefManifest
    /// Every character a chef can wear: the original chef first, then the characters fitted to
    /// its skeleton (`chef-variants.json`, built by assets/chef/build_variants.sh).
    let characters: [ChefCharacter]
    static let classic = "classic"
    private var loaded: [String: WorkspaceCapybaraAsset] = [:]
    private var preloading = false
    init() throws {
        manifest = try ChefManifest.load()
        rig = try WorkspaceCapybaraAsset.load("chef-animated", subdirectory: "Chef", spec: Self.spec)
        props = try GLBStaticMeshes.load("chef-props", subdirectory: "Chef")
        guard Set(manifest.clips.keys).isSubset(of: Set(rig.clips.keys)) else { throw WorkspaceCapybaraAsset.AssetError.invalid("Chef manifest names clips the GLB lacks") }
        let fitted = WorkspaceCapybaraAsset.resourceBundle.url(forResource: "chef-variants", withExtension: "json", subdirectory: "Chef")
            .flatMap { try? JSONDecoder().decode(ChefCharacterList.self, from: Data(contentsOf: $0)).characters } ?? []
        characters = [ChefCharacter(id: Self.classic, name: "Chef", asset: "chef-animated.glb")] + fitted
        guests = WorkspaceCapybaraAsset.resourceBundle.url(forResource: "guest-list", withExtension: "json", subdirectory: "Restaurant")
            .flatMap { try? JSONDecoder().decode(ChefCharacterList.self, from: Data(contentsOf: $0)).characters }?
            .map { ChefCharacter(id: Self.guestPrefix + $0.id, name: $0.name, asset: $0.asset, folder: "Restaurant") } ?? []
        staff = WorkspaceCapybaraAsset.resourceBundle.url(forResource: "staff-list", withExtension: "json", subdirectory: "Chef")
            .flatMap { try? JSONDecoder().decode(ChefCharacterList.self, from: Data(contentsOf: $0)).characters }?
            .map { ChefCharacter(id: Self.staffPrefix + $0.id, name: $0.name, asset: $0.asset) } ?? []
    }
    /// Kitchen staff (`Chef/staff-list.json`): the manager, who comes over to talk with chefs
    /// that struck the gong. Never worn by an agent's chef.
    let staff: [ChefCharacter]
    static let staffPrefix = "staff:"
    static let manager = staffPrefix + "manager"
    /// The restaurant's guests (`Restaurant/guest-list.json`): characters on the chef's skeleton
    /// that sit at the tables outside. Never worn by an agent's chef.
    let guests: [ChefCharacter]
    static let guestPrefix = "guest:"
    /// A character's rig: its own mesh and textures, the chef's skeleton and clips. Loaded the
    /// first time a chef wears it (`preload` warms them all off the main thread); the original
    /// chef stands in for one that can't load.
    func rig(for character: String) -> WorkspaceCapybaraAsset {
        if character == Self.classic { return rig }
        if let asset = loaded[character] { return asset }
        guard let entry = (characters + guests + staff).first(where: { $0.id == character }), let url = url(entry),
              let asset = try? WorkspaceCapybaraAsset(data: Data(contentsOf: url), spec: Self.spec, clipsFrom: rig) else { return rig }
        loaded[character] = asset
        return asset
    }
    /// Load every character in the background, so a new chef never waits on its files.
    func preload() {
        guard !preloading else { return }
        preloading = true
        let base = rig, spec = Self.spec
        let pending = (characters + guests + staff).filter { $0.id != Self.classic && loaded[$0.id] == nil }.compactMap { c in url(c).map { (c.id, $0) } }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            for (id, url) in pending {
                guard let data = try? Data(contentsOf: url),
                      let asset = try? WorkspaceCapybaraAsset(data: data, spec: spec, clipsFrom: base) else { continue }
                await MainActor.run { if self?.loaded[id] == nil { self?.loaded[id] = asset } }
            }
        }
    }
    private func url(_ character: ChefCharacter) -> URL? {
        WorkspaceCapybaraAsset.resourceBundle.url(forResource: (character.asset as NSString).deletingPathExtension, withExtension: "glb", subdirectory: character.folder)
    }
}

/// A chef character: an id (what agents are assigned) and its asset.
nonisolated struct ChefCharacter: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let asset: String
    /// The resource folder its asset is in.
    var folder = "Chef"
    private enum CodingKeys: String, CodingKey { case id, name, asset }
    init(id: String, name: String, asset: String, folder: String = "Chef") {
        self.id = id; self.name = name; self.asset = asset; self.folder = folder
    }
}
private nonisolated struct ChefCharacterList: Decodable { let characters: [ChefCharacter] }

/// One rendered chef. Navigation (position, heading) applies to `root`, which is never scaled;
/// `visual` scales the skinned model so props and attach offsets scale with it. Each chef owns its
/// skeleton and props; geometry, textures and clips are shared.
/// Updated on SceneKit's render thread (see KitchenSceneView's renderer delegate) and created
/// and steered on the main thread, always under the kitchen's chef lock.
nonisolated final class ChefAvatar: @unchecked Sendable {
    let id: String
    let root = SCNNode()
    let visual = SCNNode()
    let rig: WorkspaceCapybaraAsset.Instance
    let director: ChefDirector
    private let asset: WorkspaceCapybaraAsset
    private let templates: [String: SCNNode]
    private let manifest: ChefManifest
    private let dishTemplates: [String: SCNNode]
    /// What it fetched from the pantry, carried to the next station (see `PantryCarry`).
    let pantryCarry: PantryCarrier
    /// What its agent is fetching; set under the kitchen's chef lock.
    var pantryItem: PantryCarry.Item?
    /// The plate it carries out of the prep area (its current step); set under the chef lock.
    var prepItem: PantryCarry.Item?
    /// The dish this chef's task prepares (see `KitchenFood`); set under the kitchen's chef lock.
    var dish: String?
    private var dishNode: (id: String, node: SCNNode)?
    private var dishSpot = ""
    /// Dish diameter in chef units (about the old plate prop's footprint).
    static let dishSize: Float = 0.76
    /// Where the dish sits relative to the chef, in chef units: on the cutting board under the
    /// knife while chopping, and under the spoon's dip point while tasting.
    static let boardSpot = SIMD3<Float>(-0.05, 0.605, 0.7)
    static let tastingSpot = SIMD3<Float>(-0.1, 0.585, 0.66)
    /// Served dishes sit across the pass, in front of the serving window's overhead beam, so
    /// they stay visible from the kitchen camera.
    static let passSpot = SIMD3<Float>(0, 0.585, 1.0)
    private var props: [ChefProp: SCNNode] = [:]
    private var token = -1
    private var last: (name: String, time: Float, loop: Bool)?
    private var fading: (name: String, time: Float, loop: Bool)?
    private var fadeElapsed: Float = 0
    private var fadeDuration: Float = 0
    /// Sounds cued since the scene last collected them (`KitchenSound`), and the clip time they
    /// were last checked at.
    var heard: [KitchenSound] = []
    /// Picked up by the pointer: lifted off the floor, following `target`, squirming. Its
    /// director pauses meanwhile and re-plans from where the chef is put down.
    struct Hold {
        var target: SIMD2<Float>
        var point: SIMD2<Float>
        var time: Float = 0
        var swing = SIMD2<Float>.zero
        /// 0…1 while it shrinks into the trash.
        var trashing: Float? = nil
    }
    var held: Hold?
    /// Restaurant diners reuse the chef (without its hat, in their own outfit) and make no kitchen foley.
    var silent = false
    static let liftHeight: Float = 0.8
    static let surprise: Float = 0.9
    private let baseScale: Float
    private let squirmBones: [String: SCNNode]
    private var soundClip: (token: Int, time: Float)?

    /// The character this chef wears (`ChefAssets.characters`).
    let character: String

    @MainActor init(id: String, assets: ChefAssets, scale: Float, navigation: WorkspaceCapybaraNavigation, character: String = ChefAssets.classic) {
        self.id = id; self.character = character
        asset = assets.rig(for: character); templates = assets.props; manifest = assets.manifest
        dishTemplates = KitchenFood.templates
        pantryCarry = PantryCarrier(models: PantryCarry.models)
        rig = asset.makeInstance()
        director = ChefDirector(clips: assets.manifest.clips, unit: scale, navigation: navigation)
        baseScale = scale
        let instance = rig
        squirmBones = Dictionary(uniqueKeysWithValues: ["hips", "spine", "chest", "head", "upperarm.L", "upperarm.R",
            "forearm.L", "forearm.R", "thigh.L", "thigh.R"].compactMap { name in instance.bone(name).map { (name, $0) } })
        root.name = "agent:" + id
        visual.simdScale = SIMD3(repeating: scale)
        visual.addChildNode(rig.root)
        root.addChildNode(visual)
    }

    /// True while anything visibly changes: walking, one-shots, crossfades, or looping clips
    /// (frozen under reduced motion).
    var animating: Bool { held != nil || !(director.settled && fading == nil && director.reducedMotion) }

    func update(_ delta: Float) {
        if held != nil { updateHeld(delta); return }
        director.update(delta)
        root.simdPosition = SIMD3(director.position.x, 0, director.position.y)
        root.simdOrientation = simd_quatf(angle: director.heading, axis: SIMD3(0, 1, 0))
        let command = director.clip
        listen(command)
        if command.token != token {
            token = command.token
            fading = last; fadeElapsed = 0; fadeDuration = command.fade
        }
        let time = sampleTime(command.name, director.clipTime, loop: command.loop)
        var pose = rig.pose(command.name, time: time)
        if var previous = fading {
            fadeElapsed += max(0, delta)
            if fadeElapsed < fadeDuration {
                previous.time += max(0, delta)
                fading = previous
                let weight = fadeElapsed / fadeDuration
                let from = rig.pose(previous.name, time: sampleTime(previous.name, previous.time, loop: previous.loop))
                pose = zip(from, pose).map { $0.blended(with: $1, weight: weight) }
            } else { fading = nil }
        }
        rig.apply(pose)
        last = (command.name, time, command.loop)
        syncProps()
        let fit = manifest.attach[ChefProp.plate.node]?[ChefProp.plate.fitClip]
        // What there is to pick up where: the pantry's resource, prep's plate, and each station's own
        // item (order rail, cooking island, stove).
        var wanted = ["pantry": pantryItem, "prep": prepItem].compactMapValues { $0 }
        for area in ["order", "cooking", "stove"] { wanted[area] = PantryCarry.stationItem(area: area) }
        let delivering = director.held.contains(.plate) || director.intent?.pickup != nil
        pantryCarry.sync(wanted: wanted, area: director.station?.area, reducedMotion: director.reducedMotion, delta: delta,
                         carrySocket: rig.bone(ChefProp.plate.socket), fit: fit.map { ($0.simdPosition, $0.simdQuaternion) },
                         floor: visual, counterTop: manifest.stations.counterTop, delivering: delivering)
        director.carriesJar = pantryCarry.carrying
    }

    /// Picked up: a startled jolt, then legs paddling in the air (`run`) with the body, head and
    /// arms wriggling on top, swinging against the drag. Reduced motion only sways gently.
    private func updateHeld(_ delta: Float) {
        guard var hold = held else { return }
        let dt = max(0, delta)
        if hold.time == 0 { fading = last; fadeElapsed = 0; fadeDuration = 0.12 }
        hold.time += dt
        let previous = hold.point
        hold.point += (hold.target - hold.point) * min(1, dt * 16)
        let velocity = dt > 0 ? (hold.point - previous) / dt : .zero
        // The body trails the hand: it swings against the motion and settles back.
        hold.swing += (simd_clamp(velocity * -0.08, SIMD2(repeating: -0.5), SIMD2(repeating: 0.5)) - hold.swing) * min(1, dt * 8)
        let lift = Self.liftHeight * baseScale * min(1, hold.time / 0.15)
        let reduced = director.reducedMotion
        let sway: Float = reduced ? 0.04 * sin(hold.time * 2) : 0
        root.simdPosition = SIMD3(hold.point.x, lift, hold.point.y)
        let yaw = simd_quatf(angle: director.heading, axis: SIMD3(0, 1, 0))
        let tilt = simd_quatf(angle: hold.swing.y + sway, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: -hold.swing.x, axis: SIMD3(0, 0, 1))
        root.simdOrientation = tilt * yaw
        if let trashing = hold.trashing {
            hold.trashing = min(1, trashing + dt / 0.35)
            visual.simdScale = SIMD3(repeating: baseScale * max(0.001, 1 - hold.trashing! * hold.trashing!))
        }
        held = hold
        let startled = hold.time < Self.surprise && !reduced
        let name = reduced ? "idle_available" : startled ? "blocked_react" : "run"
        if !startled, !reduced, last?.name == "blocked_react" { fading = last; fadeElapsed = 0; fadeDuration = 0.15 }
        let time = reduced ? 0 : startled ? hold.time : sampleTime("run", (hold.time - Self.surprise) * 1.3, loop: true)
        var pose = rig.pose(name, time: time)
        if var previous = fading {
            fadeElapsed += dt
            if fadeElapsed < fadeDuration {
                previous.time += dt; fading = previous
                let from = rig.pose(previous.name, time: sampleTime(previous.name, previous.time, loop: previous.loop))
                pose = zip(from, pose).map { $0.blended(with: $1, weight: fadeElapsed / fadeDuration) }
            } else { fading = nil }
        }
        rig.apply(pose)
        if !reduced { squirm(hold.time) }
        last = (name, time, name != "blocked_react")
        syncProps()
    }
    /// Wriggles layered over the clip, each bone at its own rhythm so it never looks mechanical.
    private func squirm(_ t: Float) {
        let ease = min(1, t / 0.4)
        func wiggle(_ bone: String, _ amount: Float, _ speed: Float, _ phase: Float) {
            guard let node = squirmBones[bone] else { return }
            let a = amount * ease * sin(t * speed + phase), b = amount * 0.6 * ease * sin(t * speed * 0.73 + phase * 1.7)
            node.simdOrientation = node.simdOrientation * simd_quatf(angle: a, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: b, axis: SIMD3(0, 0, 1))
        }
        wiggle("hips", 0.18, 9, 0); wiggle("spine", 0.14, 11, 1.1); wiggle("chest", 0.12, 8, 2.3)
        wiggle("head", 0.32, 13, 0.4)
        wiggle("upperarm.L", 0.7, 12, 0); wiggle("upperarm.R", 0.7, 12, 3.1)
        wiggle("forearm.L", 0.5, 15, 1.2); wiggle("forearm.R", 0.5, 15, 4.0)
        wiggle("thigh.L", 0.3, 10, 0.6); wiggle("thigh.R", 0.3, 10, 3.7)
    }
    /// Puts the chef down at `point` (on the floor) and lets its director carry on from there.
    func release(at point: SIMD2<Float>) {
        held = nil
        visual.simdScale = SIMD3(repeating: baseScale)
        director.putDown(at: point)
        token = -1 // crossfade from the dangle into whatever the director plays
    }

    /// Collects the sound cues the clip passed this frame. Held loops under reduced motion are silent.
    private func listen(_ command: ChefClipCommand) {
        defer { soundClip = (command.token, director.clipTime) }
        if silent { return }
        guard let meta = manifest.clips[command.name], meta.duration > 0 else { return }
        if director.reducedMotion, command.loop, !ChefDirector.locomotionClips.contains(command.name) { return }
        let now = director.clipTime / meta.duration
        var from: Float = -1
        if let previous = soundClip, previous.token == command.token {
            from = previous.time / meta.duration
            if now < from { from -= 1 } // wrapped
        }
        heard += KitchenSound.crossed(command.name, markers: meta.markers, from: from, to: now)
    }

    private func sampleTime(_ name: String, _ time: Float, loop: Bool) -> Float {
        let duration = asset.clips[name]?.duration ?? 0
        guard duration > 0 else { return 0 }
        // Reduced motion holds a stable, readable pose instead of looping decorative motion.
        if director.reducedMotion && loop && !ChefDirector.locomotionClips.contains(name) { return duration * 0.35 }
        return loop ? time : min(time, duration - 0.0001)
    }

    private func syncProps() {
        let dish = currentDish()
        syncDish(dish)
        for prop in ChefProp.allCases {
            // With dishes available, the task's dish stands in for the plate prop.
            if prop == .plate, dish != nil { props[prop]?.removeFromParentNode(); continue }
            if director.held.contains(prop) {
                guard let socket = rig.bone(prop.socket), let node = node(for: prop) else { continue }
                if node.parent !== socket {
                    node.removeFromParentNode(); socket.addChildNode(node)
                    let fit = manifest.attach[prop.node]?[prop.fitClip]
                    node.simdPosition = fit?.simdPosition ?? .zero
                    node.simdOrientation = fit?.simdQuaternion ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }
            } else if prop == .plate, director.placedPlate != nil, let node = node(for: prop) {
                // Left on the pass in front of the chef, in chef units (slot depth 0.57).
                if node.parent !== visual {
                    node.removeFromParentNode(); visual.addChildNode(node)
                    node.simdPosition = SIMD3(0, manifest.stations.counterTop, 0.57)
                    node.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }
            } else {
                props[prop]?.removeFromParentNode()
            }
        }
    }

    private func currentDish() -> SCNNode? {
        guard let id = dish, let template = dishTemplates[id] else {
            dishNode?.node.removeFromParentNode(); dishNode = nil; return nil
        }
        if dishNode?.id != id {
            dishNode?.node.removeFromParentNode()
            let node = template.clone(); node.simdScale = SIMD3(repeating: Self.dishSize)
            dishNode = (id, node); dishSpot = ""
        }
        return dishNode?.node
    }
    /// The chopped board is on the counter: it stands in for the dish on the cutting board.
    var choppingOnBoard: Bool { pantryCarry.placement == .counter && pantryCarry.item?.kind == .board }
    /// Carried and served as the plate; on the board while chopping (unless the chopped board is
    /// there); at tasting while tasting.
    private func syncDish(_ node: SCNNode?) {
        guard let node else { return }
        let station = director.station?.area, clip = director.clip.name
        var parent: SCNNode? = visual, position = SIMD3<Float>.zero, orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), spot: String
        if director.held.contains(.plate), let socket = rig.bone(ChefProp.plate.socket) {
            let fit = manifest.attach[ChefProp.plate.node]?[ChefProp.plate.fitClip]
            parent = socket; position = fit?.simdPosition ?? .zero; orientation = fit?.simdQuaternion ?? orientation; spot = "carry"
        } else if director.placedPlate != nil {
            position = Self.passSpot; spot = "pass"
        } else if station == "cooking", clip == "working_chop", !choppingOnBoard {
            position = Self.boardSpot; spot = "board"
        } else if station == "tasting", clip == "testing_dish" {
            position = Self.tastingSpot; spot = "tasting"
        } else {
            parent = nil; spot = "hidden"
        }
        guard spot != dishSpot else { return }
        dishSpot = spot
        node.removeFromParentNode()
        guard let parent else { return }
        parent.addChildNode(node)
        node.simdPosition = position; node.simdOrientation = orientation
    }
    /// Where the dish currently is ("carry", "pass", "board", "tasting" or "hidden"), for tests.
    var dishPlacement: String { dishNode == nil ? "none" : dishSpot.isEmpty ? "hidden" : dishSpot }

    private func node(for prop: ChefProp) -> SCNNode? {
        if let node = props[prop] { return node }
        guard let template = templates[prop.node] else { return nil }
        let node = template.clone(); node.name = prop.node
        props[prop] = node
        return node
    }
}
