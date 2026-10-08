import DioramaCore

extension WorkspaceAgentPresentation {
    /// A finished turn whose last message asks you something (see `TurnQuestion`), wherever the
    /// question sits in the closing lines, for Claude and Codex alike: a real question waits on
    /// you; an offer ("Want me to…?") does too when the turn delivered nothing or stopped with its
    /// checklist unfinished.
    static func endsAsking(_ agent: WorkspaceAgent, entries: [Entry]) -> Bool {
        guard [.done, .ready].contains(agent.status) else { return false }
        let start = entries.lastIndex { $0.kind == "You" }.map { $0 + 1 } ?? 0
        guard let last = entries[start...].last(where: { $0.kind == "Assistant" }),
              let asked = TurnQuestion.asking(last.text) else { return false }
        switch asked {
        case .question: return true
        case .offer:
            let plan = agent.plan.flatMap { $0.hasTasks && !$0.tasksPreviousTurn ? $0 : nil }
            let unfinished = plan.map { $0.completedTaskCount < $0.checklist.count } ?? false
            return agent.turnWork.files.isEmpty || unfinished
        }
    }
}
