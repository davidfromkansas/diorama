import AppKit
import SceneKit
import SwiftUI
import simd
import DioramaCore

/// Shown on every cold launch, before the workspace. Play hands off to account setup or Home.
struct StartScreen: View {
    let controller: ExecutionController
    let play: () -> Void
    @State private var info: WireValue = .null

    var body: some View {
        VStack(spacing: 0) {
            StartChefView().frame(width: 440, height: 330)
                .accessibilityElement().accessibilityLabel("A tiny chef waves, shrugs, and looks around in place")
            Text("diorama").font(.custom("Arial", size: 80).bold()).tracking(-4.4)
                .foregroundStyle(StartPalette.ink).padding(.top, 8).padding(.bottom, 48)
            Button(action: play) {
                Label { Text("Play") } icon: { Image(systemName: "play.fill").font(.system(size: 18)) }
            }
            .buttonStyle(StartPlayButtonStyle()).keyboardShortcut(.defaultAction).pointingHand()
            VStack(spacing: 26) {
                HStack(spacing: 16) {
                    StartProviderCard(brand: .codex, state: state("codex"))
                    StartProviderCard(brand: .claude, state: state("claude"))
                }
                Text("We use the logins, settings, and skills you already have.")
                    .font(.custom("Arial", size: 16)).foregroundStyle(StartPalette.secondary)
            }.padding(.top, 64)
        }
        .padding(.horizontal, 24).padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StartPalette.background).ignoresSafeArea()
        .environment(\.colorScheme, .light)
        .task { await watchConnections() }
    }

    private func state(_ key: String) -> AgentConnectionState {
        AgentConnectionState.resolve(installed: AgentExecutable.resolve(key) != nil, connected: info[key].bool,
                                     checking: info == .null || info[key + "Checking"].bool, error: info[key + "Error"].string)
    }

    /// Provider checks only run once the router connects, so start it, then follow the checks while
    /// the screen is up (another caller may already be connecting, and sign-ins can land later).
    private func watchConnections() async {
        Task { if !controller.connected { await controller.connect() } }
        while !Task.isCancelled {
            let updated = await controller.connectionInfo()
            // Until a check has run, nothing reads as connected or checking, which would look signed out.
            let settled = !controller.connecting && (controller.connected || controller.error != nil)
                && !updated["codexChecking"].bool && !updated["claudeChecking"].bool
            if updated != .null && (settled || updated["codex"].bool || updated["claude"].bool) { info = updated }
            do { try await Task.sleep(for: .seconds(settled ? 2 : 0.3)) } catch { return }
        }
    }
}

private enum StartPalette {
    static let background = Color(red: 0xf5/255, green: 0xf5/255, blue: 0xf7/255)
    static let ink = Color(red: 0x22/255, green: 0x23/255, blue: 0x2b/255)
    static let secondary = Color(red: 0x62/255, green: 0x65/255, blue: 0x70/255)
    static let accent = Color(red: 0x65/255, green: 0x55/255, blue: 0xc8/255)
    static let accentHover = Color(red: 0x74/255, green: 0x64/255, blue: 0xd6/255)
    static let accentEdge = Color(red: 0x4c/255, green: 0x3f/255, blue: 0x9c/255)
}

/// A small branded card showing one provider's connection.
private struct StartProviderCard: View {
    enum Brand {
        case codex, claude
        var name: String { self == .codex ? "OpenAI Codex" : "Claude Code" }
        var mark: String { self == .codex ? "OpenAI" : "Claude" }
        var ink: Color { self == .codex ? Color(red: 0x1f/255, green: 0x1d/255, blue: 0x2b/255) : .white }
        var fill: LinearGradient {
            switch self {
            case .codex: LinearGradient(colors: [Color(red: 0xd3/255, green: 0xe5/255, blue: 0xff/255), Color(red: 0xdc/255, green: 0xc4/255, blue: 0xf6/255)], startPoint: .top, endPoint: .bottom)
            case .claude: LinearGradient(colors: [Color(red: 0xd9/255, green: 0x77/255, blue: 0x57/255), Color(red: 0xc6/255, green: 0x6a/255, blue: 0x4c/255)], startPoint: .top, endPoint: .bottom)
            }
        }
        var image: NSImage? {
            guard let url = Bundle.module.url(forResource: mark, withExtension: "svg", subdirectory: "ConnectorBrand"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.isTemplate = true
            return image
        }
    }
    let brand: Brand
    let state: AgentConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let mark = brand.image { Image(nsImage: mark).resizable().scaledToFit() }
                else { Image(systemName: "sparkles").resizable().scaledToFit() }
            }.frame(width: 22, height: 22).accessibilityHidden(true)
            Spacer(minLength: 14)
            Text(brand.name).font(.custom("Arial", size: 15).bold()).lineLimit(1)
            HStack(spacing: 6) {
                if state == .checking { ProgressView().controlSize(.mini).tint(brand.ink) }
                else { Image(systemName: state == .connected ? "powercord" : "exclamationmark.circle").font(.system(size: 11, weight: .semibold)) }
                Text(status).font(.custom("Arial", size: 13))
            }.opacity(0.85).padding(.top, 5)
        }
        .foregroundStyle(brand.ink)
        .padding(14)
        .frame(width: 176, height: 108, alignment: .leading)
        .background(brand.fill, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.12)))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        .saturation(state == .connected || state == .checking ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(brand.name), \(status)")
    }
    private var status: String {
        switch state {
        case .connected: "Connected"
        case .checking: "Checking…"
        case .missing: "Not installed"
        case .signedOut: "Sign in needed"
        case .unavailable: "Not connected"
        }
    }
}

/// A chunky button that sits on a darker ledge: lifts on hover, presses into the ledge on click.
private struct StartPlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PlayButton(configuration: configuration) }
    private struct PlayButton: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            let lift: CGFloat = reduceMotion ? 0 : configuration.isPressed ? 3 : hovering ? -2 : 0
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(StartPalette.accentEdge).offset(y: 5)
                configuration.label
                    .labelStyle(StartPlayLabelStyle())
                    .font(.custom("Arial", size: 22).bold()).foregroundStyle(.white)
                    .frame(width: 220, height: 64)
                    .background(hovering ? StartPalette.accentHover : StartPalette.accent, in: RoundedRectangle(cornerRadius: 18))
                    .offset(y: lift)
            }
            .frame(width: 220, height: 64)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.14), value: lift)
                .animation(.easeOut(duration: 0.14), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
private struct StartPlayLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 14) { configuration.icon; configuration.title } }
}

/// The animated chef: an orthographic SceneKit view cycling through a few idle gestures.
private struct StartChefView: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.delegate = context.coordinator
        view.rendersContinuously = true
        view.isPlaying = true
        context.coordinator.load()
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) { context.coordinator.setReducedMotion(reduceMotion) }
    static func dismantleNSView(_ view: SCNView, coordinator: StartChefAnimator) {
        view.isPlaying = false; view.rendersContinuously = false; view.delegate = nil
    }
    func makeCoordinator() -> StartChefAnimator { StartChefAnimator() }
}

/// Built on the main thread; afterwards updated only on SceneKit's render thread under `lock`.
nonisolated final class StartChefAnimator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    static let spec = WorkspaceCapybaraAsset.Spec(skeletonRoot: "chef_rig", jointCount: 26, requiredClips: sequence.map(\.0), instanceName: "chef")
    /// Clip and seconds to hold it, matching the start-screen prototype.
    static let sequence: [(String, Float)] = [
        ("idle_available", 2.4), ("request_input", 1.2), ("wait_input", 2.4),
        ("idle_available", 2.4), ("blocked_react", 1.2), ("blocked_wait", 3.2),
        ("idle_available", 2.4), ("unknown_wait", 4),
    ]
    static let oneShots: Set<String> = ["request_input", "blocked_react"]
    static let fade: Float = 0.25

    let scene = SCNScene()
    let camera = SCNNode()
    private let lock = NSLock()
    private var rig: WorkspaceCapybaraAsset.Instance?
    private var reducedMotion = false
    private var index = 0, clipTime: Float = 0
    private var previous: (name: String, time: Float)?
    private var fadeElapsed: Float = 0
    private var lastTime: TimeInterval?

    @MainActor override init() {
        super.init()
        let lens = SCNCamera(); lens.usesOrthographicProjection = true; lens.orthographicScale = 1.15
        lens.zNear = 0.1; lens.zFar = 30
        camera.camera = lens
        camera.simdPosition = SIMD3(0.25, 1.22, 6); camera.simdLook(at: SIMD3(0, 0.95, 0))
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650; ambient.light?.color = NSColor(white: 0.96, alpha: 1)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 1250; key.light?.color = NSColor(red: 1, green: 0.957, blue: 0.91, alpha: 1)
        key.simdPosition = SIMD3(-3, 5, 5); key.simdLook(at: .zero)
        let rim = SCNNode(); rim.light = SCNLight(); rim.light?.type = .directional
        rim.light?.intensity = 700; rim.light?.color = NSColor(red: 0.85, green: 0.867, blue: 1, alpha: 1)
        rim.simdPosition = SIMD3(3, 3, -2); rim.simdLook(at: .zero)
        for light in [ambient, key, rim] { scene.rootNode.addChildNode(light) }
        scene.rootNode.addChildNode(Self.contactShadow())
    }

    /// Parses the bundled chef off the main thread, then adds it to the scene.
    @MainActor func load() {
        guard let url = WorkspaceCapybaraAsset.resourceBundle.url(forResource: "chef-animated", withExtension: "glb", subdirectory: "Chef") else { return }
        Task.detached(priority: .userInitiated) { [self] in
            guard let data = try? Data(contentsOf: url), let asset = try? WorkspaceCapybaraAsset(data: data, spec: Self.spec) else { return }
            await MainActor.run {
                let instance = asset.makeInstance()
                instance.root.enumerateHierarchy { node, _ in if node.geometry != nil { node.castsShadow = false } }
                instance.apply(asset.pose(Self.sequence[0].0, time: 0))
                lock.withLock { rig = instance }
                scene.rootNode.addChildNode(instance.root)
            }
        }
    }

    @MainActor func setReducedMotion(_ value: Bool) {
        lock.withLock {
            guard reducedMotion != value else { return }
            reducedMotion = value; index = 0; clipTime = 0; previous = nil
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.withLock {
            let delta = Float(lastTime.map { min(time - $0, 0.05) } ?? 0); lastTime = time
            guard let rig else { return }
            if reducedMotion {
                // Hold one readable idle pose instead of looping decorative motion.
                rig.apply(rig.pose("idle_available", time: 0.8)); return
            }
            clipTime += delta
            if clipTime >= Self.sequence[index].1 {
                previous = (Self.sequence[index].0, sample(Self.sequence[index].0, clipTime))
                fadeElapsed = 0; clipTime = 0
                index = (index + 1) % Self.sequence.count
            }
            let name = Self.sequence[index].0
            var pose = rig.pose(name, time: sample(name, clipTime))
            if let from = previous {
                fadeElapsed += delta
                if fadeElapsed < Self.fade {
                    previous = (from.name, from.time + delta)
                    let earlier = rig.pose(from.name, time: sample(from.name, from.time + delta))
                    pose = zip(earlier, pose).map { $0.blended(with: $1, weight: fadeElapsed / Self.fade) }
                } else { previous = nil }
            }
            rig.apply(pose)
        }
    }

    /// One-shot gestures hold their last frame; everything else loops.
    private func sample(_ name: String, _ time: Float) -> Float {
        guard Self.oneShots.contains(name), let duration = rig?.asset.clips[name]?.duration, duration > 0 else { return time }
        return min(time, duration - 0.0001)
    }

    @MainActor private static func contactShadow() -> SCNNode {
        let size = 128
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let colors = [NSColor(red: 40/255, green: 30/255, blue: 65/255, alpha: 0.24), NSColor(red: 40/255, green: 30/255, blue: 65/255, alpha: 0)]
            NSGradient(colors: colors)?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        let plane = SCNPlane(width: 1.25, height: 1)
        let material = SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents = image
        material.writesToDepthBuffer = false; material.blendMode = .alpha
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.simdEulerAngles = SIMD3(-.pi / 2, 0, 0); node.simdPosition = SIMD3(0, 0.005, 0)
        return node
    }
}
