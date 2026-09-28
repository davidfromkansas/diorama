import SceneKit

/// Owns semantic transitions, independently of labels, activity text, and selection.
final class WorkspaceAvatarMotion {
    private struct State: Equatable {
        let status: WorkspaceAgentStatus
        let freshness: WorkspaceAgentFreshness
        let attention: WorkspaceAttentionReason
        init(_ agent: WorkspaceAgent) {
            status = agent.status; freshness = agent.freshness; attention = agent.attentionReason
        }
    }
    enum Gesture: Equatable { case typing, wave, celebration, failure, settle, none }
    private var avatar: WorkspaceAvatar?
    private var previous: State?
    private var wasActive = false
    private var reduced = false
    private var attentionYaw = 0.0
    private var completion: Task<Void, Never>?
    private(set) var gesture: Gesture = .none
    private(set) var generation = 0
    private(set) var animating = false {
        didSet { if oldValue != animating { animationChanged?() } }
    }
    var animationChanged: (() -> Void)?

    func update(_ agent: WorkspaceAgent, avatar: WorkspaceAvatar, reduceMotion: Bool, active: Bool, cameraYaw: Double) {
        self.avatar = avatar
        let next = State(agent)
        let changed = next != previous
        guard changed || active != wasActive || reduceMotion != reduced else { return }
        let observedTransition = (previous?.freshness == .live || previous?.freshness == .recentlyObserved) && wasActive && active
        let oldStatus = previous?.status
        previous = next
        wasActive = active
        reduced = reduceMotion
        generation += 1
        completion?.cancel(); completion = nil
        // Retarget from what the user currently sees, rather than an action's destination.
        for node in avatar.poseAnchors {
            let visible = node.presentation.eulerAngles
            node.removeAllActions()
            node.eulerAngles = visible
        }
        gesture = .none
        animating = false
        let live = (agent.freshness == .live || agent.freshness == .recentlyObserved)
        if live && [.waiting, .failed].contains(agent.status) && changed {
            attentionYaw = cameraYaw
        }
        let target = pose(agent)
        guard active, !reduceMotion else {
            apply(target, to: avatar)
            return
        }
        if live && agent.status == .working {
            gesture = .typing
            transition(target, avatar: avatar)
            for (index, arm) in avatar.workingAnchors.enumerated() {
                arm.removeAction(forKey: "pose")
                let a = rotation(x: index == 0 ? 0.06 : -0.06, node: arm)
                let b = rotation(x: index == 0 ? -0.06 : 0.06, node: arm)
                arm.runAction(.sequence([rotation(node: arm), .repeatForever(.sequence([a, b]))]), forKey: "typing")
            }
            animating = !avatar.workingAnchors.isEmpty
            return
        }
        // Initial snapshots and view re-entry establish a pose, never replay a terminal event.
        let entered = changed && observedTransition && oldStatus != agent.status && live
        if entered && agent.status == .waiting, let arm = avatar.rightArm {
            gesture = .wave
            transition(target, avatar: avatar)
            arm.removeAction(forKey: "pose")
            let left = rotation(x: -.pi / 2, z: -0.30, node: arm)
            let right = rotation(x: -.pi / 2, z: 0.30, node: arm)
            arm.runAction(.sequence([rotation(x: -.pi / 2, node: arm), left, right, left, right,
                                     rotation(x: -.pi / 2, node: arm)]), forKey: "wave")
            finish(after: 1.2, target: target, avatar: avatar)
        } else if entered && agent.status == .done, !avatar.workingAnchors.isEmpty {
            gesture = .celebration
            transition(target, avatar: avatar)
            for arm in avatar.workingAnchors {
                arm.removeAction(forKey: "pose")
                arm.runAction(.sequence([rotation(x: -.pi / 2, node: arm), .wait(duration: 0.2),
                                         rotation(x: .pi / 2, node: arm)]), forKey: "celebration")
            }
            finish(after: 0.6, target: target, avatar: avatar)
        } else if entered && agent.status == .failed, let head = avatar.head {
            gesture = .failure
            transition(target, avatar: avatar)
            head.removeAction(forKey: "pose")
            head.runAction(.sequence([rotation(y: -0.30, node: head), rotation(y: 0.30, node: head), rotation(node: head)]), forKey: "failure")
            finish(after: 0.6, target: target, avatar: avatar)
        } else if changed && observedTransition && live && !avatar.poseAnchors.isEmpty {
            gesture = .settle
            transition(target, avatar: avatar)
            finish(after: 0.2, target: target, avatar: avatar)
        } else {
            apply(target, to: avatar)
        }
    }

    private struct Pose {
        var yaw = 0.0
        var left = Double.pi / 2
        var right = Double.pi / 2
    }
    private func pose(_ agent: WorkspaceAgent) -> Pose {
        guard (agent.freshness == .live || agent.freshness == .recentlyObserved) else { return Pose() }
        switch agent.status {
        case .working: return Pose(left: 0, right: 0)
        case .waiting: return Pose(yaw: attentionYaw, right: -.pi / 2)
        case .failed: return Pose(yaw: attentionYaw)
        default: return Pose()
        }
    }
    private func rotation(x: Double = 0, y: Double = 0, z: Double = 0, node: SCNNode? = nil) -> SCNAction {
        let action: SCNAction
        if let node, let avatar, avatar.capybaraRig != nil {
            let q = avatar.orientation(for: node, x: x, y: y, z: z)
            action = .rotate(toAxisAngle: SCNVector4(q.axis.x,q.axis.y,q.axis.z,q.angle), duration: 0.2)
        } else {
            action = .rotateTo(x: x, y: y, z: z, duration: 0.2, usesShortestUnitArc: true)
        }
        // Shared motion guidance: strong ease-in-out for on-screen transformations.
        action.timingFunction = { progress in
            // Cubic Bézier (0.77, 0, 0.175, 1), solved for x.
            var low: Float = 0, high: Float = 1
            for _ in 0..<12 {
                let t = (low + high) / 2, u = 1 - t
                let x = 3 * u * u * t * 0.77 + 3 * u * t * t * 0.175 + t * t * t
                if x < progress { low = t } else { high = t }
            }
            let t = (low + high) / 2
            return 3 * (1 - t) * t * t + t * t * t
        }
        return action
    }
    private func transition(_ pose: Pose, avatar: WorkspaceAvatar) {
        avatar.body?.runAction(rotation(y: pose.yaw, node: avatar.body), forKey: "pose")
        avatar.head?.runAction(rotation(node: avatar.head), forKey: "pose")
        avatar.leftArm?.runAction(rotation(x: pose.left, node: avatar.leftArm), forKey: "pose")
        avatar.rightArm?.runAction(rotation(x: pose.right, node: avatar.rightArm), forKey: "pose")
    }
    private func apply(_ pose: Pose, to avatar: WorkspaceAvatar) {
        for node in avatar.poseAnchors { node.removeAllActions() }
        if avatar.capybaraRig != nil {
            if let node = avatar.body { node.simdOrientation = avatar.orientation(for: node, y: pose.yaw) }
            if let node = avatar.head { node.simdOrientation = avatar.orientation(for: node) }
            if let node = avatar.leftArm { node.simdOrientation = avatar.orientation(for: node, x: pose.left) }
            if let node = avatar.rightArm { node.simdOrientation = avatar.orientation(for: node, x: pose.right) }
        } else {
            avatar.body?.eulerAngles = SCNVector3(0, pose.yaw, 0)
            avatar.head?.eulerAngles = avatar.neutralRotation
            avatar.leftArm?.eulerAngles = SCNVector3(pose.left, 0, 0)
            avatar.rightArm?.eulerAngles = SCNVector3(pose.right, 0, 0)
        }
    }
    private func finish(after seconds: Double, target: Pose, avatar: WorkspaceAvatar) {
        animating = true
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        completion = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard let self else { return }
            self.apply(target, to: avatar)
            self.gesture = .none
            self.animating = false
        }
    }
}
