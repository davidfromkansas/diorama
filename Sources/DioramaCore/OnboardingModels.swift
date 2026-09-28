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

public enum AgentConnectionState: String, Sendable {
    case checking, connected, missing, signedOut, unavailable
    public static func resolve(installed: Bool, connected: Bool, checking: Bool, error: String?) -> Self {
        if connected { return .connected }
        if checking { return .checking }
        if !installed { return .missing }
        guard let error else { return .signedOut }
        let value = error.lowercased()
        if value.contains("not logged in") || value.contains("please run /login") || value.contains("login expired") { return .signedOut }
        return .unavailable
    }
}
