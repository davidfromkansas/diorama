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
                        "sit_idle", "sit_sip", "sit_chat", "cover_dish"],
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
@MainActor final class ChefAvatar {
    let id: String
    let root = SCNNode()
    let visual = SCNNode()
    let rig: WorkspaceCapybaraAsset.Instance
    let director: ChefDirector
    private let assets: ChefAssets
    private var props: [ChefProp: SCNNode] = [:]
    private var token = -1
    private var last: (name: String, time: Float, loop: Bool)?
    private var fading: (name: String, time: Float, loop: Bool)?
    private var fadeElapsed: Float = 0
    private var fadeDuration: Float = 0

    init(id: String, assets: ChefAssets, scale: Float, navigation: WorkspaceCapybaraNavigation) {
        self.id = id; self.assets = assets
        rig = assets.rig.makeInstance()
        director = ChefDirector(clips: assets.manifest.clips, unit: scale, navigation: navigation)
        root.name = "agent:" + id
        visual.simdScale = SIMD3(repeating: scale)
        visual.addChildNode(rig.root)
        root.addChildNode(visual)
    }

    /// True while anything visibly changes: walking, one-shots, crossfades, or looping clips
    /// (frozen under reduced motion).
    var animating: Bool { !(director.settled && fading == nil && director.reducedMotion) }

    func update(_ delta: Float) {
        director.update(delta)
        root.simdPosition = SIMD3(director.position.x, 0, director.position.y)
        root.simdOrientation = simd_quatf(angle: director.heading, axis: SIMD3(0, 1, 0))
        let command = director.clip
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
    }

    private func sampleTime(_ name: String, _ time: Float, loop: Bool) -> Float {
        let duration = assets.rig.clips[name]?.duration ?? 0
        guard duration > 0 else { return 0 }
        // Reduced motion holds a stable, readable pose instead of looping decorative motion.
        if director.reducedMotion && loop && !ChefDirector.locomotionClips.contains(name) { return duration * 0.35 }
        return loop ? time : min(time, duration - 0.0001)
    }

    private func syncProps() {
        for prop in ChefProp.allCases {
            if director.held.contains(prop) {
                guard let socket = rig.bone(prop.socket), let node = node(for: prop) else { continue }
                if node.parent !== socket {
                    node.removeFromParentNode(); socket.addChildNode(node)
                    let fit = assets.manifest.attach[prop.node]?[prop.fitClip]
                    node.simdPosition = fit?.simdPosition ?? .zero
                    node.simdOrientation = fit?.simdQuaternion ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }
            } else if prop == .plate, director.placedPlate != nil, let node = node(for: prop) {
                // Left on the pass in front of the chef, in chef units (slot depth 0.57).
                if node.parent !== visual {
                    node.removeFromParentNode(); visual.addChildNode(node)
                    node.simdPosition = SIMD3(0, assets.manifest.stations.counterTop, 0.57)
                    node.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }
            } else {
                props[prop]?.removeFromParentNode()
            }
        }
    }

    private func node(for prop: ChefProp) -> SCNNode? {
        if let node = props[prop] { return node }
        guard let template = assets.props[prop.node] else { return nil }
        let node = template.clone(); node.name = prop.node
        props[prop] = node
        return node
    }
}
