import SwiftUI
import DioramaCore

actor FixtureTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { _ in }
    var codex: Bool
    var claude: Bool
    init(_ scenario: String) { codex = scenario == "Codex only" || scenario == "Both"; claude = scenario == "Claude only" || scenario == "Both" }
    func add(_ anthropic: Bool) { if anthropic { claude = true } else { codex = true } }
    func connect() {}
    func request(_ method: String, _ p: WireValue) -> WireValue {
        if method == "diorama/connections" { return .object(["codex": .bool(codex), "claude": .bool(claude)]) }
        if method == "thread/start" { return .object(["thread": .object(["id": .string(UUID().uuidString)]), "cwd": p["cwd"], "model": p["model"]]) }
        var rows: [WireValue] = []
        if codex { rows.append(.object(["model": .string("gpt-test"), "displayName": .string("OpenAI test model")])) }
        if claude { rows.append(.object(["model": .string("claude/sonnet"), "displayName": .string("Sonnet")])) }
        return .object(["data": .array(rows)])
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}
struct ScenarioView: View {
    let scenario: String
    let defaults: UserDefaults
    let transport: FixtureTransport
    let controller: ExecutionController
    @State var finished = false
    @State var model = ""
    @State var effort = ""
    @State var outcome = ""
    init(scenario: String) {
        self.scenario = scenario
        let suite = "local.diorama.onboarding-verification." + scenario.replacingOccurrences(of: " ", with: "-")
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        self.defaults = defaults
        let transport = FixtureTransport(scenario); self.transport = transport
        controller = ExecutionController(transport: transport)
    }
    var body: some View {
        VStack {
            if !finished {
                AgentSettingsView(controller: controller, onboarding: true, defaults: defaults, loginAction: { claude in
                    Task { await transport.add(claude); outcome = "Simulated login complete. Refresh connections." }
                }, finish: {
                    model = defaults.string(forKey: "defaultAgentModel") ?? ""
                    finished = true
                })
            } else {
                Text("Onboarding complete").font(.title)
                Text("Saved default: " + (defaults.string(forKey: "defaultAgentModel") ?? "<missing>"))
                ExecutionModelPicker(controller: controller, model: $model, effort: $effort, effectiveModel: model.isEmpty ? "gpt-test" : model).padding()
                Button("Create test session") {
                    Task {
                        do {
                            let id = try await controller.prepare(folder: "/tmp", title: "Isolated onboarding fixture", model: model)
                            outcome = "Session provider: " + (controller.tasks[id]?.provider.rawValue ?? "unknown")
                        } catch { outcome = error.localizedDescription }
                    }
                }
            }
            Text(outcome).accessibilityIdentifier("fixture-outcome")
        }
    }
}
struct HarnessView: View {
    @State var scenario = "Claude only"
    var body: some View {
        VStack {
            Text("Isolated onboarding verification — simulated account availability").font(.caption)
            Picker("Scenario", selection: $scenario) { ForEach(["Claude only", "Codex only", "Both", "Neither"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            ScenarioView(scenario: scenario).id(scenario)
        }.padding(20).frame(width: 620, height: 710)
    }
}
@main struct Harness: App {
    var body: some Scene { WindowGroup("Diorama Onboarding Verification") { HarnessView() } }
}
