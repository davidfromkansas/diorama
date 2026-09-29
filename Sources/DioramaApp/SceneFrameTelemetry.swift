import SceneKit
import os

/// Render callbacks measure delivered cadence independently of the camera display link.
/// No scene state is mutated from SceneKit's rendering thread.
nonisolated final class SceneFrameTelemetry: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    struct Samples: Sendable {
        var previous: Double?
        var intervals: [Double] = []
        var renderingStarted: Double?
        var renderDurations: [Double] = []
    }
    private let samples = OSAllocatedUnfairLock(initialState: Samples())
    func renderer(_ renderer: any SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        samples.withLock { $0.renderingStarted = CACurrentMediaTime() }
    }
    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let now = CACurrentMediaTime()
        samples.withLock {
            if let previous = $0.previous { $0.intervals.append(now-previous) }
            if let start = $0.renderingStarted { $0.renderDurations.append(now-start) }
            $0.previous = now
            if $0.intervals.count > 10_000 { $0.intervals.removeFirst(1000) }
            if $0.renderDurations.count > 10_000 { $0.renderDurations.removeFirst(1000) }
        }
        if ScenePerformance.enabled { os_signpost(.event, log: ScenePerformance.log, name: "Rendered frame") }
    }
    func reset() { samples.withLock { $0 = Samples() } }
    func snapshot() -> Samples { samples.withLock { $0 } }
}
