import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct FinishedAgentRetentionTests {
    @Test func boundedHistoryRetainsFinishedChildWithoutInventingCompletion() {
        let cache = WorkspaceProjectionCache()
        let time = Date(timeIntervalSince1970: 100)
        var snapshot = SessionActivitySnapshot()
        snapshot.apply(SessionActivityRecord(id: "child", provider: "Codex", sessionID: "s", turnID: nil,
            nativeID: "child", parentID: "s", kind: "agent", title: "Child", status: "completed", detail: "Task",
            source: "Fixture", recordedAt: time, observedAt: time, data: .null))
        var source = WorkspaceActivitySource(provider: .codex, sessionID: "s", snapshot: snapshot, task: nil)
        let first = cache.agents(id: "s", title: "Title", sources: [source])
        #expect(first.count == 2)
        source = WorkspaceActivitySource(provider: .codex, sessionID: "s", snapshot: .init(), task: nil)
        let next = cache.agents(id: "s", title: "Title", sources: [source])
        #expect(next.count == 2)
        #expect(next[1].id == first[1].id)
        #expect(next[1].status == .done && next[1].freshness == .lastKnown)
        #expect(next[0].status != .done)
    }

    @Test func removingConversationRemovesItsVisibleAgents() {
        let session = Session(id: "c", provider: .codex, url: nil, sessionID: "c", title: "Task", project: "/tmp/p",
                              modified: Date(), bytes: 0, archived: false, parentID: nil, classification: .conversation)
        let agent = SpatialAgent(projectID: "p", conversationID: "c", value: .init(id: "child", name: "Child", provider: "Codex", task: "Task", action: "", status: .done, reportedStatus: "done", freshness: .lastKnown))
        #expect(OfficeRoster(teams: [.init(projectID: "p", session: session, agents: [agent])], now: .distantFuture).occupants.count == 1)
        #expect(OfficeRoster(teams: [], now: .distantFuture).occupants.isEmpty)
    }
}
