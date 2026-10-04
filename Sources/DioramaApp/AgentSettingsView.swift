import SwiftUI
import DioramaCore

struct AgentSettingsView: View {
    let controller: ExecutionController
    var onboarding = false
    var finish: (() -> Void)? = nil
    var cancel: (() -> Void)? = nil
    @AppStorage private var defaultModel: String
    private let loginAction: ((Bool) -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var info: WireValue = .null
    @State private var refreshing = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var snapshotTask: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var pendingLogin: String?
    @State private var loginDeadline: Date?
    @State private var notice: String?
    @State private var githubStep = false
    @State private var githubConnected = false
    @State private var reviewSetup = false
    @State private var locating: String?
    init(controller: ExecutionController, onboarding: Bool = false, defaults: UserDefaults = .standard, loginAction: ((Bool) -> Void)? = nil, cancel: (() -> Void)? = nil, finish: (() -> Void)? = nil) {
        self.controller = controller; self.onboarding = onboarding; self.finish = finish; self.cancel = cancel; self.loginAction = loginAction
        _defaultModel = AppStorage(wrappedValue: "", "defaultAgentModel", store: defaults)
    }
    private var selectionAvailable: Bool { OnboardingModels.isAvailable(defaultModel, models: controller.models, connections: info) }
    private var anyConnected: Bool { info["codex"].bool || info["claude"].bool }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(onboarding ? (githubStep ? "Bring your projects to GitHub." : "Connect an account to get started.") : "Models & accounts")
                .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Text(githubStep ? "Import repositories, publish projects, and create pull requests. GitHub is optional." : "Connect OpenAI or Claude. You can add the other later.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if githubStep {
                        GitHubSettingsView(onboarding: true, connectionChanged: { githubConnected = $0 })
                    } else {
                        account("OpenAI", key: "codex")
                        account("Claude", key: "claude")
                        if anyConnected {
                            Picker("Default model", selection: $defaultModel) {
                                if info["codex"].bool { Text("OpenAI · Default").tag("") }
                                ForEach(controller.models.filter { info[$0.id.hasPrefix("claude/") ? "claude" : "codex"].bool }) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }.pointingHand()
                            Text("You can choose another model in each conversation.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let notice { Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        if !onboarding {
                            Divider()
                            GitHubSettingsView()
                            Button("Review setup…") { reviewSetup = true }.pointingHand()
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: onboarding ? 340 : 420)
            Divider()
            HStack {
                if githubStep {
                    Button("Back") { githubStep = false }.pointingHand()
                    Spacer()
                    Button("Skip for now") { finish?() }.pointingHand()
                    Button("Finish setup") { finish?() }.pointingHand().disabled(!githubConnected).keyboardShortcut(.defaultAction)
                } else {
                    if let cancel { Button("Cancel", action: cancel).pointingHand().keyboardShortcut(.cancelAction) }
                    Button("Refresh connections", action: refresh).pointingHand().disabled(refreshing)
                    if refreshing { ProgressView().controlSize(.small).accessibilityLabel("Checking connections") }
                    Spacer()
                    if onboarding {
                        Button("Continue") { pendingLogin = nil; githubStep = true }.pointingHand()
                            .disabled(!selectionAvailable).keyboardShortcut(.defaultAction)
                    }
                }
            }
        }.padding(28).frame(width: 620).interactiveDismissDisabled(onboarding)
        .task { refresh() }
        .task(id: pendingLogin) {
            guard pendingLogin != nil else { return }
            while !Task.isCancelled, pendingLogin != nil, Date() < (loginDeadline ?? .distantPast) {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                if scenePhase == .active { refresh() }
            }
            if !Task.isCancelled { pendingLogin = nil }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onDisappear { generation = UUID(); refreshTask?.cancel(); snapshotTask?.cancel(); refreshing = false; pendingLogin = nil }
        .sheet(isPresented: $reviewSetup) { AgentSettingsView(controller: controller, onboarding: true, cancel: { reviewSetup = false }, finish: { reviewSetup = false }) }
    }
    private func account(_ title: String, key: String) -> some View {
        let connected = info[key].bool
        let missing = AgentExecutable.resolve(key) == nil
        let detail = info[key + "Error"].string
        let state = AgentConnectionState.resolve(installed: !missing, connected: connected, checking: info == .null || info[key + "Checking"].bool, error: detail)
        let status: String = switch state {
        case .connected: "Connected"
        case .checking: "Checking…"
        case .missing: key == "claude" ? "Claude Code not found" : "Codex not found"
        case .signedOut: "Sign in needed"
        case .unavailable: "Couldn’t verify connection"
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                if anyConnected && !connected { Text("Optional").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if state == .checking { ProgressView().controlSize(.small) }
                Label(status, systemImage: connected ? "checkmark.circle.fill" : "circle")
                    .font(.callout).foregroundStyle(connected ? Color.green : Color.secondary)
            }
            if key == "claude" { Text("Uses your Claude subscription. No automatic switch to API billing.").font(.caption).foregroundStyle(.secondary) }
            if !connected, let detail, !missing { Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                if !connected {
                    if missing {
                        Link("Installation instructions", destination: URL(string: key == "claude" ? "https://code.claude.com/docs/en/setup" : "https://developers.openai.com/codex/cli")!).pointingHand()
                        Button("Locate existing installation…") { locate(key) }.pointingHand().disabled(controller.hasActiveWork || locating != nil)
                    } else {
                        Button("Login with " + title) { login(key) }.pointingHand().disabled(pendingLogin == key || state == .checking)
                        if detail != nil { Button("Try again", action: refresh).pointingHand().disabled(refreshing) }
                    }
                }
                if connected { Button("Manage login…") { login(key) }.pointingHand() }
                if !missing { Menu("Advanced") {
                    Button("Locate existing installation…") { locate(key) }.pointingHand().disabled(controller.hasActiveWork || locating != nil)
                }.pointingHand().fixedSize() }
            }
            if pendingLogin == key { Text("Finish signing in through Terminal and your browser. Diorama will check automatically when you return.").font(.caption).foregroundStyle(.secondary) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
    }
    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let id = generation
        snapshotTask = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                let updated = await controller.onboardingSnapshot()
                guard !Task.isCancelled, id == generation else { return }
                apply(updated)
            }
        }
        refreshTask = Task {
            await controller.refreshModels()
            let updated = await controller.connectionInfo()
            guard !Task.isCancelled, id == generation else { return }
            snapshotTask?.cancel()
            apply(updated)
            refreshing = false
        }
    }
    private func apply(_ updated: WireValue) {
        if updated != .null { info = updated }
        if !selectionAvailable, let selected = OnboardingModels.initialSelection(models: controller.models, connections: info) { defaultModel = selected }
        if let key = pendingLogin, info[key].bool { pendingLogin = nil; notice = nil }
    }
    private func locate(_ key: String) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose the official \(key == "claude" ? "Claude Code" : "Codex") executable."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        locating = key
        Task {
            defer { locating = nil }
            do {
                try await AgentExecutable.validate(url, name: key)
                UserDefaults.standard.set(url.path, forKey: "agentExecutable." + key)
                notice = "Selected \(url.lastPathComponent). New connections use this installation."
                refresh()
            } catch { notice = error.localizedDescription }
        }
    }
    private func login(_ key: String) {
        if let loginAction { loginAction(key == "claude"); return }
        guard let binary = AgentExecutable.resolve(key) else { refresh(); return }
        let shell = "'" + binary.path.replacingOccurrences(of: "'", with: "'\\''") + "'" + (key == "claude" ? " auth login --claudeai" : " login")
        let literal = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var problem: NSDictionary?
        NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(literal)\"\nend tell")?.executeAndReturnError(&problem)
        pendingLogin = key; loginDeadline = Date().addingTimeInterval(120)
        notice = problem == nil ? nil : "Open Terminal and run: " + shell
    }
}
