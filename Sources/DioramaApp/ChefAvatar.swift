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
                        "sit_idle", "sit_sip", "sit_chat", "cover_dish",
                        "merge_ready", "merge_ready_wait", "fix_react", "fix_wait"],
        instanceName: "chef")
    static let shared: Result<ChefAssets, Error> = Result { try ChefAssets() }
    let rig: WorkspaceCapybaraAsset
    let props: [String: SCNNode]
    let manifest: ChefManifest
    init() throws {
        manifest = try ChefManifest.load()
        rig = try WorkspaceCapybaraAsset.load("chef-animated", subdirectory: "Chef", spec: Self.spec)
        props = try GLBStaticMeshes.load("chef-props", subdirectory: "Chef")
        guard Set(manifest.clips.keys).isSubset(of: Set(rig.clips.keys)) else { throw WorkspaceCapybaraAsset.AssetError.invalid("Chef manifest names clips the GLB lacks") }
    }
}

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

    @MainActor init(id: String, assets: ChefAssets, scale: Float, navigation: WorkspaceCapybaraNavigation) {
        self.id = id; asset = assets.rig; templates = assets.props; manifest = assets.manifest
        dishTemplates = KitchenFood.templates
        pantryCarry = PantryCarrier(models: PantryCarry.models)
        rig = assets.rig.makeInstance()
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
        pantryCarry.sync(wanted: ["pantry": pantryItem, "prep": prepItem].compactMapValues { $0 }, area: director.station?.area, reducedMotion: director.reducedMotion, delta: delta,
                         carrySocket: rig.bone(ChefProp.plate.socket), fit: fit.map { ($0.simdPosition, $0.simdQuaternion) },
                         floor: visual, counterTop: manifest.stations.counterTop)
        director.carriesJar = pantryCarry.carrying
    }

    /// Dresses this chef as a diner: the outfit texture on its own copy of the skinned mesh
    /// (vertex data stays shared), without the hat.
    @MainActor func dressAsDiner(_ outfit: NSImage?) {
        silent = true
        guard let node = rig.nodes.first(where: { $0.skinner != nil }), let skin = node.skinner,
              let base = node.geometry, let dressed = Self.withoutHat(base) ?? base.copy() as? SCNGeometry else { return }
        // The hat's crown follows the hat bone but its band follows the head: leave out every
        // triangle wholly above the hairline (bind pose, chef units; hair and skin end at 1.46).
        dressed.materials = base.materials.map { material in
            let copy = (material.copy() as? SCNMaterial) ?? material
            if let outfit { copy.diffuse.contents = outfit }
            return copy
        }
        let skinner = SCNSkinner(baseGeometry: dressed, bones: skin.bones, boneInverseBindTransforms: skin.boneInverseBindTransforms,
                                 boneWeights: skin.boneWeights, boneIndices: skin.boneIndices)
        skinner.skeleton = skin.skeleton
        node.geometry = dressed; node.skinner = skinner
    }

    /// Above this (bind pose, chef units) everything is hat; between `headTop` and it, the hat's
    /// band shares the height with the hair, so it goes by colour (white or teal texels).
    static let hairline: Float = 1.47, headTop: Float = 1.28
    @MainActor private static var hatlessCache: [ObjectIdentifier: SCNGeometry] = [:]
    /// The chef mesh without its hat (same vertex data), computed once per rig.
    @MainActor static func withoutHat(_ geometry: SCNGeometry) -> SCNGeometry? {
        if let cached = hatlessCache[ObjectIdentifier(geometry)] { return cached.copy() as? SCNGeometry }
        guard let positions = geometry.sources(for: .vertex).first, positions.usesFloatComponents, positions.bytesPerComponent == 4 else { return nil }
        func floats(_ source: SCNGeometrySource, _ component: Int) -> [Float] {
            source.data.withUnsafeBytes { raw in
                (0..<source.vectorCount).map { raw.load(fromByteOffset: source.dataOffset + $0 * source.dataStride + component * 4, as: Float.self) }
            }
        }
        let heights = floats(positions, 1)
        let uvSource = geometry.sources(for: .texcoord).first
        let us = uvSource.map { floats($0, 0) } ?? [], vs = uvSource.map { floats($0, 1) } ?? []
        let texture = (geometry.firstMaterial?.diffuse.contents as? NSImage).flatMap { image -> NSBitmapImageRep? in
            image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init(cgImage:))
        }
        func hatColoured(_ u: Float, _ v: Float) -> Bool {
            guard let texture else { return true }
            let x = min(texture.pixelsWide - 1, max(0, Int(u * Float(texture.pixelsWide))))
            let y = min(texture.pixelsHigh - 1, max(0, Int(v * Float(texture.pixelsHigh))))
            guard let c = texture.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            let high = max(c.redComponent, c.greenComponent, c.blueComponent), low = min(c.redComponent, c.greenComponent, c.blueComponent)
            let saturation = high > 0 ? (high - low) / high : 0
            let white = saturation < 0.22 && high > 0.5
            let teal = c.blueComponent > c.redComponent + 0.05 && c.greenComponent > c.redComponent && high > 0.2
            return white || teal
        }
        let elements = geometry.elements.map { element -> SCNGeometryElement in
            guard element.primitiveType == .triangles else { return element }
            let width = element.bytesPerIndex
            var kept = Data(); kept.reserveCapacity(element.data.count)
            element.data.withUnsafeBytes { raw in
                func index(_ k: Int) -> Int {
                    width == 4 ? Int(raw.load(fromByteOffset: k * 4, as: UInt32.self)) : width == 2 ? Int(raw.load(fromByteOffset: k * 2, as: UInt16.self)) : Int(raw.load(fromByteOffset: k, as: UInt8.self))
                }
                for t in 0..<element.primitiveCount {
                    let corners = [index(t * 3), index(t * 3 + 1), index(t * 3 + 2)]
                    guard corners.allSatisfy({ $0 < heights.count }) else { continue }
                    let low = corners.map { heights[$0] }.min() ?? 0
                    if low > hairline { continue }
                    if low > headTop, !us.isEmpty, corners.allSatisfy({ $0 < us.count }) {
                        let u = corners.map { us[$0] }.reduce(0, +) / 3, v = corners.map { vs[$0] }.reduce(0, +) / 3
                        if hatColoured(u, v) { continue }
                    }
                    kept.append(contentsOf: UnsafeRawBufferPointer(rebasing: raw[(t * 3 * width)..<((t + 1) * 3 * width)]))
                }
            }
            return SCNGeometryElement(data: kept, primitiveType: .triangles, primitiveCount: kept.count / (3 * width), bytesPerIndex: width)
        }
        let result = SCNGeometry(sources: geometry.sources, elements: elements)
        result.materials = geometry.materials
        hatlessCache[ObjectIdentifier(geometry)] = result
        return result.copy() as? SCNGeometry
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
    /// Carried and served as the plate; on the board while chopping; at tasting while tasting.
    private func syncDish(_ node: SCNNode?) {
        guard let node else { return }
        let station = director.station?.area, clip = director.clip.name
        var parent: SCNNode? = visual, position = SIMD3<Float>.zero, orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), spot: String
        if director.held.contains(.plate), let socket = rig.bone(ChefProp.plate.socket) {
            let fit = manifest.attach[ChefProp.plate.node]?[ChefProp.plate.fitClip]
            parent = socket; position = fit?.simdPosition ?? .zero; orientation = fit?.simdQuaternion ?? orientation; spot = "carry"
        } else if director.placedPlate != nil {
            position = Self.passSpot; spot = "pass"
        } else if station == "cooking", clip == "working_chop" {
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
