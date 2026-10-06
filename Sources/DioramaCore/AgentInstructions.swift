import Foundation

/// Standing instructions Diorama adds to every agent it starts or resumes, after any project
/// context. The live task list is what lets Diorama show real progress (steps done of steps
/// planned) instead of guessing from tool calls.
public enum AgentInstructions {
    /// UserDefaults key that turns the task-list request off (on unless set to false).
    public static let liveTaskListKey = "liveTaskListInstruction"
    public static let liveTaskList = """
    Diorama shows your progress to the person you're working with. For any task with more than one step, keep your task list current (Codex: update_plan; Claude Code: your task tools, TaskCreate/TaskUpdate or TodoWrite). Create it before you start with 3–7 concrete steps (not one step for the whole task), mark one step in progress at a time, and mark each completed as soon as it's done; before your final message, every finished step must be marked completed. Don't spend separate turns on the list: send list updates together with your next real action (in the same message, as parallel tool calls, or in the same script), e.g. mark a step completed and the next in progress alongside the edit or command that starts it. When the person adds feedback, steers you, or changes the goal (in a new message or mid-task), revise the list in your next action: add new steps, remove or cancel steps that no longer apply, then continue. Skip the list for single-step tasks and plain questions.
    """
    public static func liveTaskListEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: liveTaskListKey) as? Bool ?? true
    }
    /// The project context (when there is one) followed by Diorama's standing instructions;
    /// nil when there is nothing to send.
    public static func compose(_ context: String?, liveTaskList enabled: Bool = liveTaskListEnabled()) -> String? {
        let parts = [context?.trimmingCharacters(in: .whitespacesAndNewlines), enabled ? liveTaskList : nil].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
