import Foundation
import DioramaCore

extension LibraryModel {
    /// The agent card: one row per conversation in this project, grouped by what it needs, from
    /// the same state the kitchen uses (status, pending requests, serving-window reviews).
    func agentSidebarItems(_ teams: [SpatialTeam]) -> [AgentSidebarItem] {
        let execution = self.execution
        let workspaces = Dictionary(projects.projects.flatMap(\.workspaces).compactMap { w in w.threadID.map { ($0, w) } }) { first, _ in first }
        // Titles are the chefs' task labels: written labels arrive later and update the rows.
        _ = TaskLabels.shared.revision
        let inputs = teams.map { team in
            AgentSidebar.Input(session: team.session, agents: team.agents,
                               review: team.agents.first { $0.value.isMain }.flatMap { KitchenReviews.shared.state($0.conversationID) },
                               reviewNote: team.agents.first { $0.value.isMain }.flatMap { KitchenReviews.shared.note($0.conversationID) },
                               model: demo?.models[team.session.id] ?? execution.tasks[team.session.sessionID].flatMap(\.namedModel),
                               title: team.agents.first { $0.value.isMain }.map { TaskLabels.shared.title($0) },
                               requests: execution.requests.values.filter { $0.threadID == team.session.sessionID }.count,
                               question: demo?.questions[team.session.id] ?? pendingQuestion(team),
                               workspaceBranch: workspaces[team.session.sessionID]?.branch,
                               pullRequest: workspaces[team.session.sessionID]?.pullRequest)
        }
        return AgentSidebar.items(inputs, catalog: execution.models, order: AgentSidebarOrder.shared.order)
    }
    /// What a conversation is waiting on you for, in a line: the oldest pending request's question
    /// or command, else (a question asked in chat) the agent's last message.
    func pendingQuestion(_ team: SpatialTeam) -> String? {
        let execution = self.execution
        if let request = RequestReviewModal.pending(execution, thread: team.session.sessionID).first {
            if let question = request.params["questions"].array.first?["question"].string { return question }
            if let command = request.params["command"].string { return "Wants to run " + command }
            return request.params["reason"].string
        }
        guard team.agents.contains(where: { $0.value.isMain && $0.value.attentionReason == .input && $0.value.status == .waiting }),
              let asked = execution.tasks[team.session.sessionID]?.transcript.entries.last(where: { $0.kind == "Assistant" })?.text else { return nil }
        // The question itself: the message's last sentence that asks something.
        if let question = TurnQuestion.asking(asked) { return question.text }
        let sentences = asked.split(whereSeparator: { ".!\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return sentences.last { $0.hasSuffix("?") } ?? sentences.last
    }
}
