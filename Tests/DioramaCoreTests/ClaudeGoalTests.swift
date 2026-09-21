import Foundation
import Testing
@testable import DioramaCore

struct ClaudeGoalTests {
    @Test func nativeModelControlMetadataIsContext() {
        #expect(MessageContent.split("<command-name>/model</command-name><command-message>model</command-message><command-args>default</command-args>", provider: .claude).first?.context == true)
        #expect(MessageContent.split("/model sonnet", provider: .claude).first?.context == false)
    }
    @Test func generatedGoalInstructionsAreCollapsedInHistory() {
        let goal = ClaudeGoal(objective: "Finish the task")
        let parts = MessageContent.split(goal.instruction, provider: .claude)
        #expect(parts.count == 1)
        #expect(parts.first?.context == true)
    }
    @Test func onlyExplicitFinalStatusContinues() {
        var goal = ClaudeGoal(objective: "Finish")
        goal.status = "active"
        goal.finish(result: "Everything seems done", usage: 12, failed: false, interrupted: false)
        #expect(goal.status == "paused")
        #expect(goal.tokensUsed == 12)
        goal.status = "active"
        goal.finish(result: "Evidence\nDIORAMA_GOAL_\(goal.marker):COMPLETE", usage: 3, failed: false, interrupted: false)
        #expect(goal.status == "complete")
    }
    @Test func limitsAndInterruptionsStopContinuation() {
        var goal = ClaudeGoal(objective: "Finish")
        goal.status = "active"; goal.turnsUsed = 10
        goal.finish(result: "DIORAMA_GOAL_\(goal.marker):CONTINUE", usage: 1, failed: false, interrupted: false)
        #expect(goal.status == "paused")
        goal.status = "active"; goal.turnsUsed = 1; goal.tokenBudget = 5
        goal.finish(result: "DIORAMA_GOAL_\(goal.marker):CONTINUE", usage: 5, failed: false, interrupted: false)
        #expect(goal.status == "paused")
        goal.status = "active"
        goal.finish(result: "DIORAMA_GOAL_\(goal.marker):COMPLETE", usage: 0, failed: false, interrupted: true)
        #expect(goal.status == "paused")
    }
    @Test func pauseIsNotOverriddenByContinue() {
        var goal = ClaudeGoal(objective: "Finish")
        goal.finish(result: "DIORAMA_GOAL_\(goal.marker):CONTINUE", usage: 1, failed: false, interrupted: false)
        #expect(goal.status == "paused")
    }
}
