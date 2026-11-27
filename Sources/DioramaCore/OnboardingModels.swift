import Foundation

public enum OnboardingModels {
    public static func isAvailable(_ selection: String, models: [ExecutionModel], connections: WireValue) -> Bool {
        if selection.isEmpty { return connections["codex"].bool && models.contains { Provider.forModel($0.id) == .codex } }
        return connections[Provider.forModel(selection).key].bool && models.contains { $0.id == selection }
    }
    public static func initialSelection(models: [ExecutionModel], connections: WireValue) -> String? {
        if isAvailable("", models: models, connections: connections) { return "" }
        for provider in [Provider.claude, .devin] where connections[provider.key].bool {
            let prefix = provider.modelPrefix ?? ""
            if let model = models.first(where: { $0.id == prefix + "default" })?.id ?? models.first(where: { $0.id.hasPrefix(prefix) })?.id { return model }
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
