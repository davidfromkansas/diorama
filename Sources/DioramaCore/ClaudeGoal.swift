import Foundation

/// Diorama-owned continuation state. Reopening an app never restarts work implicitly.
struct ClaudeGoal: Codable, Sendable {
    var objective: String
    var status = "paused"
    var tokenBudget: Int = 100_000
    var tokensUsed = 0
    var turnsUsed = 0
    var turnLimit = 10
    var reason = "Ready"
    var marker = UUID().uuidString
    var pendingResult = false
    var selectedModel: String?

    var wire: WireValue {
        .object(["objective": .string(objective), "status": .string(status),
                 "tokenBudget": .number(Double(tokenBudget)), "tokensUsed": .number(Double(tokensUsed)),
                 "turnsUsed": .number(Double(turnsUsed)), "turnLimit": .number(Double(turnLimit)),
                 "reason": .string(reason)])
    }
    var instruction: String {
        """
        <diorama_goal_context>
        Diorama goal: \(objective)
        Work toward this goal within the user's permissions. Do not broaden its scope.
        At the end of this response, summarize concrete progress and evidence, then output exactly one status line:
        DIORAMA_GOAL_\(marker):COMPLETE — only if the whole goal is achieved with evidence.
        DIORAMA_GOAL_\(marker):CONTINUE — if useful authorized work remains and you can proceed.
        DIORAMA_GOAL_\(marker):BLOCKED — if you need user input or cannot proceed.
        Use only the status line itself, without the explanatory dash text.
        </diorama_goal_context>
        """
    }
    mutating func finish(result: String, usage: Int, failed: Bool, interrupted: Bool) {
        pendingResult = false
        tokensUsed += max(0, usage)
        if interrupted || failed {
            status = "paused"; reason = interrupted ? "Stopped" : "Turn failed"; return
        }
        let lines = result.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let prefix = "DIORAMA_GOAL_\(marker):"
        if lines.last == prefix + "COMPLETE" {
            status = "complete"; reason = "Claude reported completion; see its evidence in the conversation"
        } else if lines.last == prefix + "BLOCKED" {
            status = "paused"; reason = "Needs input; see the conversation"
        } else if lines.last != prefix + "CONTINUE" {
            status = "paused"; reason = "No clear continuation status; review before resuming"
        } else if tokensUsed >= tokenBudget || turnsUsed >= turnLimit {
            status = "paused"; reason = "Continuation limit reached"
        }
    }
}
