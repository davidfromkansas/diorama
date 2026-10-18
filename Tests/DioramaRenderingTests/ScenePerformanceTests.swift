import AppKit
import SceneKit
import Metal
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
}
