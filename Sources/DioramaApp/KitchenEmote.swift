import DioramaCore
import Foundation

/// A notable moment for a chef (a step done, tests passing, needing you): its tag pops or shakes
/// and VoiceOver hears about it. Lasting states are the tag's phase (`ChefTagContent.Phase`).
enum ChefEmote: String, CaseIterable, Comparable {
    case alert, question, wrench, angry, star, check, note, idea, plus, thinking

    /// Lower shows first when several happen at once.
    var priority: Int { Self.allCases.firstIndex(of: self)! }
    static func < (a: Self, b: Self) -> Bool { a.priority < b.priority }

    var spoken: String {
        switch self {
        case .alert: "needs you"
        case .question: "has a question"
        case .angry: "hit a failure"
        case .wrench: "needs a fix"
        case .star: "has a dish ready"
        case .check: "tests passed"
        case .note: "finished a step"
        case .idea: "made a plan"
        case .plus: "fetched from the pantry"
        case .thinking: "is thinking"
        }
    }
    /// The emote that stays up while a state lasts: needing you, or a dish at the pass.
    static func lasting(_ agent: SpatialAgent, review: KitchenReviews.State?) -> ChefEmote? {
        let value = agent.value
        if agent.needsAttention || value.status == .failed || value.status == .waiting {
            return value.status == .waiting && value.attentionReason == .input ? .question : .alert
        }
        // A pull request: a wrench while it needs a fix, a check once it's ready to merge.
        if review == .needsFix, value.status != .working { return .wrench }
        if review == .shipped, value.status != .working { return .check }
        return KitchenLayout.work(for: value, review: review).area == "serving" ? .star : nil
    }
}

/// What changed between two looks at an agent that deserves a reaction.
enum ChefMoment {
    static func detect(previous: WorkspaceAgent?, current: WorkspaceAgent) -> [ChefEmote] {
        guard let previous else { return [] }
        var moments: [ChefEmote] = []
        let attention = { (agent: WorkspaceAgent) in agent.status == .waiting || agent.status == .failed }
        if attention(current), !attention(previous) || current.attentionReason != previous.attentionReason {
            moments.append(current.status == .waiting && current.attentionReason == .input ? .question : .alert)
        }
        if current.status == .done, previous.status != .done { moments.append(.star) }
        let before = previous.turnWork, after = current.turnWork
        func count(_ work: TurnWork, _ outcome: TurnWork.Outcome) -> Int { work.tests.filter { $0.outcome == outcome }.count }
        // Counts restart with each turn; only growth within the turn is a moment.
        if count(after, .failed) > count(before, .failed) || after.failedCommands > before.failedCommands { moments.append(.angry) }
        if count(after, .passed) > count(before, .passed) { moments.append(.check) }
        func kept(_ plan: AgentPlan?) -> AgentPlan? { plan.flatMap { $0.hasTasks && !$0.tasksPreviousTurn && $0.checklist.count > 1 ? $0 : nil } }
        if let now = kept(current.plan) {
            if let then = kept(previous.plan) { if now.completedTaskCount > then.completedTaskCount { moments.append(.note) } }
            else { moments.append(.idea) }
        }
        if after.resources.count > before.resources.count { moments.append(.plus) }
        return moments
    }
    /// Seconds without a tool call or a note before a working agent reads as thinking (composing a
    /// long file, planning) and how often the thought bubble repeats while it stays quiet.
    static let thinkingAfter: TimeInterval = 20
    static let thinkingEvery: TimeInterval = 8
    static func silent(_ agent: WorkspaceAgent, now: Date) -> Bool {
        guard agent.isWorking, let last = [agent.lastToolAt, agent.lastCommentaryAt].compactMap({ $0 }).max() else { return false }
        return now.timeIntervalSince(last) >= thinkingAfter
    }
}
