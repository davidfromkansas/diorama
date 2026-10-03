import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ProviderTitlePresentationTests {
    @Test func titleUpdateDoesNotAdvanceRosterActivity() {
        var agent = SpatialAgent(projectID: "p", conversationID: "c", value: WorkspaceAgent(id: "main", name: "Otto", provider: "Codex", task: "Old title", action: "Editing", status: .working, reportedStatus: "working", freshness: .live))
        var reducer = AgentRosterReducer()
        reducer.ingest([agent], received: Date(timeIntervalSince1970: 1))
        let before = reducer.ordered[0]
        agent.value.task = "Fix Writing Page Contrast"
        reducer.ingest([agent], received: Date(timeIntervalSince1970: 100))
        let after = reducer.ordered[0]
        #expect(after.taskTitle == "Fix Writing Page Contrast")
        #expect(after.updated == before.updated && after.revision == before.revision && after.changedAt == before.changedAt)
        #expect(after.destination == before.destination)
    }
}
