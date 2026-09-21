import Foundation
import DioramaCore

/// Only unfinished calls from the attached current turn are presented as live work.
struct CanvasActivity: Codable, Equatable {
    var id: String
    var tool: String
    var label: String
    var target: String
    static func current(_ task: ExecutedTask?) -> [CanvasActivity] {
        guard let task, task.attached, task.phase == .working, let turn = task.turnID else { return [] }
        var pending: [String: ActivityEvent] = [:]
        for event in task.activity where event.turnID == turn {
            guard let id = event.callID else { continue }
            if event.kind == "toolStarted" { pending[id] = event }
            if ["toolFinished", "toolFailed"].contains(event.kind) { pending.removeValue(forKey: id) }
        }
        return pending.values.sorted { $0.time < $1.time }.suffix(8).map { event in
            let tool = event.tool ?? "tool"
            let label: String
            switch tool {
            case "commandExecution", "exec_command", "shell", "Bash": label = "Running command"
            case "fileChange", "apply_patch", "Edit", "Write": label = "Editing files"
            case "webSearch", "web_search": label = "Searching the web"
            case "imageGeneration", "image_gen", "imagegen": label = "Generating image"
            default: label = "Using \(tool)"
            }
            return CanvasActivity(id: event.callID ?? event.id, tool: tool, label: label, target: String((event.detail ?? "").prefix(240)))
        }
    }
}

extension CanvasActivity {
    /// Observation is evidence of recent activity, not an execution connection.
    static func observedPhase(_ summary: ActivitySummary, now: Date) -> ExecutionPhase? {
        guard summary.error == nil, let event = summary.latestState,
              let time = event.recordedAt, now.timeIntervalSince(time) >= -5,
              now.timeIntervalSince(time) <= 90 else { return nil }
        switch summary.state {
        case .working: return .working
        case .approval: return .approval
        case .input: return .input
        case .finished: return .finished
        case .interrupted: return .interrupted
        default: return nil
        }
    }
}
