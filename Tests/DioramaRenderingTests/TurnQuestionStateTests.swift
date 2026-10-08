import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

/// Same transcripts as Claude and as Codex: both land as "Assistant" entries.
@MainActor struct TurnQuestionStateTests {
    private func finished(_ provider: String, files: [String] = [], plan: AgentPlan? = nil) -> WorkspaceAgent {
        var value = WorkspaceAgent(id: "main", name: "Pia", provider: provider, task: "Task", action: "Done", status: .done,
                                   reportedStatus: "completed", freshness: .live, observedAt: Date())
        for file in files { value.turnWork.started(tool: "Edit", detail: file, call: nil) }
        value.plan = plan
        return value
    }
    private func plan(done: Int, total: Int) -> AgentPlan {
        var snapshot = SessionActivitySnapshot()
        snapshot.records = (0..<total).map { index in
            SessionActivityRecord(id: "s\(index)", provider: "Codex", sessionID: "s", turnID: "t", nativeID: "s\(index)", kind: "step",
                                  title: "Step \(index)", status: index < done ? "completed" : "pending", detail: "", source: "test", observedAt: Date(), data: .null)
        }
        return AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", currentTurn: "t")
    }
    private func turn(_ reply: String) -> [Entry] {
        [Entry(id: "u", kind: "You", text: "List the open PRs", timestamp: nil), Entry(id: "a", kind: "Assistant", text: reply, timestamp: nil)]
    }

    @Test func aQuestionWithATailWaitsForBothProviders() {
        let reply = "This repository has no Git remote. What GitHub repository URL or `owner/name` should I use? Nothing was changed."
        for provider in ["Codex", "Claude"] {
            #expect(WorkspaceAgentPresentation.endsAsking(finished(provider), entries: turn(reply)))
        }
    }

    @Test func offersWaitOnlyWhenNothingWasDeliveredOrTheListStoppedShort() {
        let offer = turn("Updated the icon. Want me to open a PR?")
        #expect(!WorkspaceAgentPresentation.endsAsking(finished("Claude", files: ["Icon.swift"]), entries: offer))
        #expect(WorkspaceAgentPresentation.endsAsking(finished("Codex"), entries: offer))
        #expect(WorkspaceAgentPresentation.endsAsking(finished("Codex", files: ["Icon.swift"], plan: plan(done: 1, total: 3)), entries: offer))
        #expect(!WorkspaceAgentPresentation.endsAsking(finished("Codex", files: ["Icon.swift"], plan: plan(done: 3, total: 3)), entries: offer))
    }

    @Test func answeredOrPlainEndingsDontWait() {
        let answered = turn("Which repository should I use?") + [Entry(id: "u2", kind: "You", text: "davidl/kitchen-demo", timestamp: nil)]
        #expect(!WorkspaceAgentPresentation.endsAsking(finished("Codex"), entries: answered))
        #expect(!WorkspaceAgentPresentation.endsAsking(finished("Claude"), entries: turn("All five PRs are summarised above.")))
    }
}
