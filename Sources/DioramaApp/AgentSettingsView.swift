import SwiftUI
import DioramaCore

struct AgentSettingsView: View {
    let controller: ExecutionController
    var onboarding = false
    var finish: (() -> Void)? = nil
    @AppStorage private var defaultModel: String
    private let loginAction: ((Bool) -> Void)?
    @State private var needsInitialSelection: Bool
    init(controller: ExecutionController, onboarding: Bool = false, defaults: UserDefaults = .standard, loginAction: ((Bool) -> Void)? = nil, finish: (() -> Void)? = nil) {
        self.controller = controller; self.onboarding = onboarding; self.finish = finish; self.loginAction = loginAction
        _defaultModel = AppStorage(wrappedValue: "", "defaultAgentModel", store: defaults)
        _needsInitialSelection = State(initialValue: defaults.object(forKey: "defaultAgentModel") == nil)
    }
    private var selectionAvailable: Bool { OnboardingModels.isAvailable(defaultModel, models: controller.models, connections: info) }
    @State private var info: WireValue = .null
    @State private var refreshing = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(onboarding ? "Choose your default model" : "Models & accounts").font(.title2.bold())
            Text("New sessions use this model. You can choose another in the composer.").foregroundStyle(.secondary)
            Picker("Default model", selection: $defaultModel) {
                if info["codex"].bool { Text("OpenAI · Default").tag("") }
                else { Text(controller.models.isEmpty ? "Connect an account to choose a model" : "Choose a model").tag("") }
                ForEach(controller.models) { model in Text((model.id.hasPrefix("claude/") ? "Anthropic · " : "OpenAI · ") + model.name).tag(model.id) }
                if !defaultModel.isEmpty, !controller.models.contains(where: { $0.id == defaultModel }) { Text(defaultModel + " · reconnect to use").tag(defaultModel) }
            }
            .disabled(refreshing)
            if !refreshing && !selectionAvailable {
                Text(controller.models.isEmpty ? "Connect either account to get started." : "Choose a connected model, or reconnect the account for your saved default.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            account("OpenAI", connected: info["codex"].bool, claude: false)
            account("Anthropic", connected: info["claude"].bool, claude: true)
            Text("Claude uses your Claude subscription through the official Claude Code login. Diorama does not fall back to API billing.").font(.caption).foregroundStyle(.secondary)
            if let detail = info["claudeError"].string { Text(detail).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button(refreshing ? "Checking…" : "Refresh connections", action: refresh).disabled(refreshing)
                Spacer()
                if let finish { Button("Done", action: finish).keyboardShortcut(.defaultAction).disabled(refreshing || !selectionAvailable || error != nil) }
            }
        }.padding(28).frame(width: 520).interactiveDismissDisabled(onboarding).task { refresh() }
    }
    private func account(_ name: String, connected: Bool, claude: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(name).font(.headline); Text(connected ? "Connected" : "Not connected").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(connected ? "Manage login…" : "Log in…") { login(claude: claude) }
        }
    }
    private func refresh() {
        guard !refreshing else { return }; refreshing = true
        Task {
            await controller.refreshModels(); info = await controller.connectionInfo(); error = controller.error
            if onboarding && needsInitialSelection, let selected = OnboardingModels.initialSelection(models: controller.models, connections: info) {
                defaultModel = selected; needsInitialSelection = false
            }
            refreshing = false
        }
    }
    private func login(claude: Bool) {
        if let loginAction { loginAction(claude); return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binary = claude ? ClaudeExecutionTransport.binary() : [home.appendingPathComponent(".local/bin/codex"), URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex")].first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let binary else {
            NSWorkspace.shared.open(URL(string: claude ? "https://code.claude.com/docs/en/setup" : "https://developers.openai.com/codex/cli")!)
            error = "Install the official CLI, then return here and refresh connections."; return
        }
        let shell = "'" + binary.path.replacingOccurrences(of: "'", with: "'\\''") + "'" + (claude ? " auth login --claudeai" : " login")
        let literal = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var problem: NSDictionary?
        NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(literal)\"\nend tell")?.executeAndReturnError(&problem)
        error = problem == nil ? "Finish login in the official CLI, then click Refresh connections." : "Open Terminal and run: " + shell
    }
}
