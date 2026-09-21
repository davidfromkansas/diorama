import Foundation

public enum OnboardingModels {
    public static func isAvailable(_ selection: String, models: [ExecutionModel], connections: WireValue) -> Bool {
        if selection.isEmpty { return connections["codex"].bool && models.contains { !$0.id.hasPrefix("claude/") } }
        let provider = selection.hasPrefix("claude/") ? "claude" : "codex"
        return connections[provider].bool && models.contains { $0.id == selection }
    }
    public static func initialSelection(models: [ExecutionModel], connections: WireValue) -> String? {
        if isAvailable("", models: models, connections: connections) { return "" }
        if connections["claude"].bool {
            return models.first { $0.id == "claude/default" }?.id ?? models.first { $0.id.hasPrefix("claude/") }?.id
        }
        return nil
    }
}
