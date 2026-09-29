import AppKit
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ScenePerformanceTests {
    @Test func qualityHysteresisAndRecovery() {
        var policy = SceneQualityPolicy()
        let change1 = !policy.observe(gpuSeconds: 0.02, now: 0, targetFPS: 120)
        #expect(change1)
        let change2 = !policy.observe(gpuSeconds: 0.02, now: 1.9, targetFPS: 120)
        #expect(change2)
        let change3 = policy.observe(gpuSeconds: 0.02, now: 2, targetFPS: 120)
        #expect(change3)
        #expect(policy.level == 1)
        let change4 = !policy.observe(gpuSeconds: 0.001, now: 3, targetFPS: 120)
        #expect(change4)
        let change5 = !policy.observe(gpuSeconds: 0.001, now: 12.9, targetFPS: 120)
        #expect(change5)
        let change6 = policy.observe(gpuSeconds: 0.001, now: 13, targetFPS: 120)
        #expect(change6)
        #expect(policy.level == 0)
    }
    @Test func latestMeadowRequestWinsAndCacheIsBounded() async {
        let meadow = OfficeMeadow()
        meadow.configure(project:"old",office:.init(minX:-6,maxX:6,minZ:-6,maxZ:6))
        meadow.updateVisibility(bounds:.init(minX:-100,maxX:100,minZ:-100,maxZ:100),centre:.zero)
        #expect(meadow.cachedPatchCount == 0, "Camera requests do not synchronously generate meshes")
        meadow.configure(project:"new",office:.init(minX:-10,maxX:10,minZ:-10,maxZ:10))
        meadow.updateVisibility(bounds:.init(minX:-20,maxX:20,minZ:-20,maxZ:20),centre:.zero)
        await meadow.settle()
        #expect(meadow.bladeCount > 0 && meadow.bladeCount <= 48_000)
        #expect(meadow.cachedBytes <= OfficeMeadow.byteLimit)
        #expect(!meadow.pending)
        meadow.setStreaming(false)
    }
    @Test func projectionCacheTracksFreshnessAndSourceChanges() {
        let cache = WorkspaceProjectionCache()
        var source = WorkspaceActivitySource(provider:.codex, sessionID:"s", snapshot:.init(), task:nil)
        _ = cache.agents(id:"s",title:"Title",sources:[source])
        _ = cache.agents(id:"s",title:"Title",sources:[source])
        #expect(cache.rebuilds == 1)
        source.fallbackStatus = "working"
        _ = cache.agents(id:"s",title:"Title",sources:[source])
        #expect(cache.rebuilds == 2)
    }

    @Test func cancelledPreparationCanResumeAndCommit() async {
        let meadow = OfficeMeadow()
        var completions: [@MainActor @Sendable () -> Void] = []
        meadow.prepare = { _, completion in completions.append(completion) }
        meadow.configure(project:"p",office:.init(minX:-2,maxX:2,minZ:-2,maxZ:2))
        meadow.updateVisibility(bounds:.init(minX:-8,maxX:8,minZ:-8,maxZ:8),centre:.zero)
        for _ in 0..<100 where completions.isEmpty {
            meadow.uploadReady()
            try? await Task.sleep(for:.milliseconds(2))
        }
        #expect(!completions.isEmpty)
        meadow.setStreaming(false)
        completions.forEach { $0() }
        #expect(meadow.cachedBytes == 0)
        meadow.prepare = nil
        await meadow.settle()
        #expect(!meadow.pending)
        #expect(meadow.bladeCount > 0)
        #expect(meadow.cachedBytes <= OfficeMeadow.byteLimit)
    }
    @Test func cachedChildFreshnessExpiresWithoutNewSourceRecords() {
        let cache = WorkspaceProjectionCache()
        let time = Date(timeIntervalSince1970:100)
        var snapshot = SessionActivitySnapshot()
        snapshot.apply(SessionActivityRecord(id:"child", provider:"Codex", sessionID:"s", turnID:nil,
            nativeID:"child", parentID:"s", kind:"agent", title:"Child", status:"running", detail:"Task",
            source:"Fixture", recordedAt:time, observedAt:time, data:.null))
        let observation = ExternalObservationSnapshot(sessionID:"s",transcript:.init(),activity:.init(),
            structured:snapshot,sourceModifiedAt:time,synchronizedAt:time,error:nil)
        var source = WorkspaceActivitySource(provider:.codex,sessionID:"s",snapshot:snapshot,task:nil,
            observation:observation,now:time.addingTimeInterval(29))
        #expect(cache.agents(id:"s",title:"Title",sources:[source])[1].freshness == .recentlyObserved)
        source.now = time.addingTimeInterval(31)
        #expect(cache.agents(id:"s",title:"Title",sources:[source])[1].freshness == .lastKnown)
        #expect(cache.rebuilds == 2)
    }
    @Test func gpuProbeReportsCommandBufferExecutionTime() async {
        let scene = SCNScene()
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position.z = 5
        scene.rootNode.addChildNode(camera)
        scene.rootNode.addChildNode(SCNNode(geometry:SCNBox(width:1,height:1,length:1,chamferRadius:0)))
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .directional
        light.light?.castsShadow = true; light.light?.shadowMode = .deferred
        scene.rootNode.addChildNode(light)
        let probe = SceneGPUProbe()
        let seconds: Double? = await withCheckedContinuation { continuation in
            probe.sample(scene:scene,camera:camera,size:CGSize(width:640,height:480),samples:4) {
                continuation.resume(returning:$0)
            }
        }
        #expect(seconds != nil && seconds! > 0)
    }
}
