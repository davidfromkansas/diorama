import AppKit
import SceneKit
import simd
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct WorkspaceMotionTests {
    private func agent(_ status: WorkspaceAgentStatus, freshness: WorkspaceAgentFreshness = .live) -> WorkspaceAgent {
        var value = WorkspaceAgent.ready
        value.status = status; value.freshness = freshness
        return value
    }

    @Test func attentionLabelsUseOnlyTheOwnersExplicitState() {
        for provider in [Provider.codex, .claude] {
            for (phase, message) in [(ExecutionPhase.approval, "Needs Approval 🚨"), (.input, "Needs Your Input 💬")] {
                var task = ExecutedTask(id: "root", title: "Task", folder: "/tmp", attached: true)
                task.provider = provider; task.phase = phase
                var snapshot = SessionActivitySnapshot()
                for (id, status) in [("generic", "blocked"), ("approval", "awaiting_approval"), ("input", "waiting_for_input")] {
                    snapshot.apply(SessionActivityRecord(id: id, provider: provider.rawValue, sessionID: "root", turnID: nil,
                        nativeID: id, parentID: "root", kind: "agent", title: id, status: status, detail: "",
                        source: "Fixture", recordedAt: nil, observedAt: Date(), data: .null))
                }
                let result = WorkspaceAgentPresentation.agents(title: "Task", sources: [
                    WorkspaceActivitySource(provider: provider, sessionID: "root", snapshot: snapshot, task: task)
                ])
                #expect(result[0].overheadMessage == message)
                #expect(result[1].overheadMessage == "Waiting")
                #expect(result[2].overheadMessage == "Needs Approval 🚨")
                #expect(result[3].overheadMessage == "Needs Your Input 💬")
            }
        }
        for status in [WorkspaceAgentStatus.ready, .working, .done, .stopped] {
            #expect(agent(status).overheadMessage == nil)
        }
        #expect(agent(.failed).overheadMessage == "Something went wrong ⚠️")
        #expect(agent(.unknown).overheadMessage == "Status unknown")
        #expect(agent(.waiting, freshness: .lastKnown).overheadMessage == "Last known")
        #expect(agent(.unknown, freshness: .unverified).overheadMessage == "Connection lost")
    }

    @Test func repeatedUpdatesDoNotReplayAndInterruptionRemovesOldGestures() async throws {
        let view = WorkspaceSceneNSView()
        func update(_ value: WorkspaceAgent, active: Bool = true, reduced: Bool = false) {
            view.apply(agents: [value], selectedID: nil, reduceMotion: reduced, active: active)
        }
        update(agent(.working))
        let station = try #require(view.workstations["main"])
        #expect(station.motion.gesture == .typing && view.isPlaying)
        var waiting = agent(.waiting); waiting.attentionReason = .approval
        update(waiting)
        #expect(station.motion.gesture == .wave)
        let generation = station.motion.generation
        waiting.action = "A new activity description"
        update(waiting)
        #expect(station.motion.generation == generation)
        #expect(station.avatar.rightArm?.action(forKey: "typing") == nil)
        try await Task.sleep(for: .milliseconds(1350))
        #expect(!station.animating && !view.isPlaying && !view.rendersContinuously)
        #expect(abs(simd_dot(station.avatar.rightArm!.simdOrientation.vector, station.avatar.orientation(for: station.avatar.rightArm!, x: -.pi / 2).vector)) > 0.9999)
        let direction = station.avatar.body!.eulerAngles.y
        update(waiting)
        #expect(station.avatar.body!.eulerAngles.y == direction)
        update(agent(.working))
        update(agent(.failed))
        #expect(station.motion.gesture == .failure)
        update(agent(.stopped))
        #expect(station.avatar.head?.action(forKey: "failure") == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!view.isPlaying)
        #expect(abs(simd_dot(station.avatar.leftArm!.simdOrientation.vector, station.avatar.orientation(for: station.avatar.leftArm!, x: .pi / 2).vector)) > 0.9999)
    }

    @Test func terminalSnapshotsHistoryAndViewReentryStayStill() async throws {
        let view = WorkspaceSceneNSView()
        func update(_ value: WorkspaceAgent, active: Bool = true, reduced: Bool = false) {
            view.apply(agents: [value], selectedID: nil, reduceMotion: reduced, active: active)
        }
        update(agent(.done))
        let station = try #require(view.workstations["main"])
        #expect(!station.animating)
        update(agent(.working))
        update(agent(.done))
        #expect(station.motion.gesture == .celebration)
        try await Task.sleep(for: .milliseconds(750))
        #expect(!view.isPlaying)
        update(agent(.working))
        update(agent(.waiting))
        update(agent(.waiting), active: false)
        #expect(!station.animating && !view.isPlaying)
        update(agent(.waiting))
        #expect(!station.animating)
        update(agent(.working), reduced: true)
        #expect(!view.isPlaying)
        update(agent(.failed), reduced: true)
        #expect(station.avatar.head?.hasActions == false)
        update(agent(.working, freshness: .lastKnown))
        #expect(!station.animating)
        view.stopRendering()
        #expect(!view.isPlaying)
    }

    @Test func rigMovesTheFaceWithTheHeadAndSupportsMissingAnchors() {
        let avatar = WorkspaceAvatarFactory.capybara()
        #expect(avatar.capybaraRig != nil)
        #expect(avatar.head?.name == "head")
        #expect(avatar.capybaraRig?.nodes.contains { $0.skinner?.bones.contains(where: { $0 === avatar.head }) == true } == true)
        #expect(avatar.leftArm?.parent?.name == "shoulder.L")
        let empty = WorkspaceAvatar(root: SCNNode(), body: nil, head: nil, leftArm: nil, rightArm: nil)
        let motion = WorkspaceAvatarMotion()
        motion.update(agent(.working), avatar: empty, reduceMotion: false, active: true, cameraYaw: 0)
        #expect(!motion.animating)
    }

    @Test func renderLiveGestureFrames() throws {
        let view = WorkspaceSceneNSView()
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 650)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = view.scene; renderer.pointOfView = view.pointOfView
        let size = CGSize(width: 760, height: 650)
        func frame(_ time: Double, _ name: String) throws {
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/diorama-gesture-\(name).png"))
        }
        view.apply(agents: [agent(.working)], selectedID: nil, reduceMotion: false, active: true)
        try frame(0, "typing")
        view.apply(agents: [agent(.waiting)], selectedID: nil, reduceMotion: false, active: true)
        try frame(0.01, "wave-start")
        try frame(0.35, "wave")
        view.apply(agents: [agent(.done)], selectedID: nil, reduceMotion: false, active: true)
        try frame(0.36, "done-start")
        try frame(0.65, "done")
        view.apply(agents: [agent(.failed)], selectedID: nil, reduceMotion: false, active: true)
        try frame(0.66, "failure-start")
        try frame(0.95, "failure")
        view.stopRendering()
    }

    @Test func renderStaticStatusPoses() throws {
        for (name, width) in [("wide", 1200), ("narrow", 420)] {
            let view = WorkspaceSceneNSView()
            view.frame = NSRect(x: 0, y: 0, width: width, height: 850)
            let statuses: [WorkspaceAgentStatus] = [.ready, .working, .waiting, .done, .stopped, .failed, .unknown]
            let agents = statuses.enumerated().map { index, status in
                WorkspaceAgent(id: "pose-\(index)", name: status.rawValue, provider: "codex", task: "Fixture", action: "",
                    status: status, reportedStatus: status.rawValue, freshness: .live,
                    attentionReason: status == .waiting ? .approval : .other)
            }
            view.apply(agents: agents, selectedID: nil, reduceMotion: true, active: true)
            view.resetCamera()
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/diorama-motion-\(name).png"))
        }
    }
}
