import SwiftUI
import DioramaCore

struct WorkflowControls: View {
    let controller: ExecutionController
    let task: ExecutedTask
    @Binding var mode: String
    @Binding var capabilities: [CapabilityInput]
    @Binding var queueNext: Bool
    @State private var showGoal = false
    @State private var objective = ""
    @State private var budget = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if task.workflow.goal != .null {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(task.workflow.goal["objective"].string ?? "Goal").font(.callout.weight(.medium))
                        Text("Goal: \(task.workflow.goal["status"].scalarText) · \(task.workflow.goal["tokensUsed"].scalarText) tokens").font(.caption).foregroundStyle(.secondary)
                        if task.provider == .claude {
                            Text("\(task.workflow.goal["reason"].scalarText) · \(task.workflow.goal["turnsUsed"].scalarText)/\(task.workflow.goal["turnLimit"].scalarText) turns").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if task.workflow.goal["status"].string == "active" { Button("Pause goal") { run { try await controller.setGoal(id: task.id, status: "paused") } } }
                    Button("Edit") { objective = task.workflow.goal["objective"].string ?? ""; budget = task.workflow.goal["tokenBudget"].number.map { String(Int($0)) } ?? ""; showGoal = true }
                    Button("Clear") { run { try await controller.clearGoal(id: task.id) } }.help("Clear the goal; an already running turn continues until stopped")
                }
            }
            if !capabilities.isEmpty {
                HStack { ForEach(capabilities) { value in Button("\(value.name) ×") { capabilities.removeAll { $0.id == value.id } } } }.font(.caption)
            }
            if !task.workflow.queue.isEmpty || task.workflow.queueUncertain {
                VStack(spacing: 6) {
                    ForEach(task.workflow.queue, id: \.pretty) { row in
                        HStack {
                            Image(systemName: "tray")
                            Text(row["input"].array.compactMap { $0["text"].string }.joined(separator: " ").isEmpty ? "Queued attachment" : row["input"].array.compactMap { $0["text"].string }.joined(separator: " "))
                                .lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 8)
                            if [Provider.codex, .claude].contains(task.provider) { Button(task.provider == .claude ? "Interrupt & steer" : "Steer") { run { try await controller.steerQueued(id: task.id, submissionID: row["id"].string ?? "") } }
                                .disabled(!controller.canSteer(id: task.id) || task.workflow.queueUncertain) }
                            Button { run { try await controller.removeQueued(id: task.id, submissionID: row["id"].string ?? "") } } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Remove queued message")
                        }.font(.caption).padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if task.workflow.queueUncertain {
                        Text("Queue paused · delivery needs verification").font(.caption).foregroundStyle(.orange)
                        Button("Refresh and verify queue") { run { try await controller.acknowledgeQueueInspection(id: task.id) } }
                    } else if !task.phase.active && !task.workflow.queue.isEmpty {
                        Button("Send next queued message") { run { try await controller.startQueued(id: task.id) } }
                    }
                }
            }
            if let message = error ?? controller.featureErrors["modes"] ?? controller.featureErrors["queue:" + task.id] ?? controller.featureErrors["goals"] { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }.disabled(controller.workflowBusy.contains(task.id))
            .task(id: task.id) { await controller.loadWorkflow(id: task.id); await controller.loadModes() }
            .popover(isPresented: $showGoal) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Goal").font(.headline)
                    TextField("Objective", text: $objective, axis: .vertical).lineLimit(2...5)
                    TextField("Optional token budget", text: $budget)
                    if task.provider == .claude {
                        Text("Claude goals run while Diorama is open. Up to 10 responses and 100,000 tokens by default; token usage is checked between responses, so the final response can exceed the budget. Reopening Diorama leaves goals paused.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Starting or resuming a goal may continue work automatically. Permissions stay unchanged.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Save paused") { saveGoal(active: false) }
                        Button("Resume goal") { saveGoal(active: true) }

                    }
                    if let error { Text(error).foregroundStyle(.orange) }
                }.padding(20).frame(width: 390)
            }
    }
    private func saveGoal(active: Bool) {
        guard budget.isEmpty || (Int(budget) ?? 0) > 0 else { error = "Enter a positive whole-number budget or leave it empty"; return }
        run { try await controller.setGoal(id: task.id, objective: objective, status: active ? "active" : "paused", tokenBudget: Int(budget)); showGoal = false }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        error = nil; Task { do { try await operation() } catch { self.error = error.localizedDescription } }
    }
}

struct UsageView: View {
    let controller: ExecutionController
    let task: ExecutedTask
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage & context").font(.headline)
            Text("Last turn: \(task.workflow.usage["last"]["totalTokens"].scalarText) tokens")
            Text("Conversation total: \(task.workflow.usage["total"]["totalTokens"].scalarText) tokens")
            Text("Model context capacity: \(task.workflow.usage["modelContextWindow"].scalarText)")
            Text("Token usage is not a dollar cost or an exact context-fill percentage.").font(.caption).foregroundStyle(.secondary)
            ForEach(["primary", "secondary"], id: \.self) { key in
                let limit = controller.rateLimits["rateLimits"][key]
                if let used = limit["usedPercent"].number {
                    Text("\(key.capitalized) account limit: \(used.formatted())% used")
                    if let reset = limit["resetsAt"].number { Text("Resets " + Date(timeIntervalSince1970: reset).formatted()).font(.caption) }
                }
            }
            Button("Compact conversation") { Task { do { try await controller.compact(id: task.id) } catch { self.error = error.localizedDescription } } }.disabled(task.phase.active)
            if let error = error ?? controller.featureErrors["usage"] { Text(error).foregroundStyle(.orange) }
        }.padding(20).frame(width: 380).textSelection(.enabled)
    }
}

struct IntegrationPicker: View {
    let controller: ExecutionController
    let folder: String
    let threadID: String?
    @Binding var selection: [CapabilityInput]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Skills & connectors").font(.title2); Spacer(); Button("Done") { dismiss() } }

            Text("Choose capabilities to include with the next message. Connection and tool approval are separate.").foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    sectionHeading("Skills", key: "skills")
                    ForEach(controller.skills, id: \.capabilityRowID) { skill in
                        HStack {
                            VStack(alignment: .leading) { Text(skill["name"].scalarText); Text(skill["description"].string ?? "").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button(skill["enabled"].bool ? "Disable" : "Enable") { run { try await controller.setSkill(path: skill["path"].string ?? "", enabled: !skill["enabled"].bool) } }.help("Saves the enabled state in Codex configuration")
                            if skill["enabled"].bool { chooseButton(.init(name: skill["name"].string ?? "", path: skill["path"].string ?? "", kind: "skill")) }
                        }
                    }
                    sectionHeading("Apps", key: "app/installed")
                    Text("Installed apps appear first. Browse the directory to discover more.").font(.caption).foregroundStyle(.secondary)
                    ForEach(controller.apps, id: \.capabilityRowID) { app in
                        HStack {
                            VStack(alignment: .leading) { Text(app["name"].scalarText); Text(app["isAccessible"].bool ? "Accessible" : "Not connected / not accessible").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if app["isAccessible"].bool && app["isEnabled"] != .bool(false) { chooseButton(.init(name: app["name"].string ?? "", path: "app://" + (app["id"].string ?? ""), kind: "mention")) }
                            if let link = safeURL(app["installUrl"].string) { Button("Manage connection") { openURL(link) } }
                        }
                    }
                    HStack {
                        if !controller.appDirectoryLoaded || controller.appDirectoryCursor != nil {
                            Button(controller.appDirectoryLoaded ? "Load more apps" : "Browse app directory") {
                                Task { await controller.loadMoreApps(threadID: threadID) }
                            }.disabled(controller.appDirectoryLoading || controller.integrationSectionsLoading.contains("app/installed"))
                        }
                        if controller.appDirectoryLoading { ProgressView().controlSize(.small).accessibilityLabel("Loading app directory") }
                    }
                    sectionHeading("MCP servers", key: "mcpServerStatus/list")
                    ForEach(controller.connectors, id: \.capabilityRowID) { connector in
                        HStack {
                            VStack(alignment: .leading) { Text(connector["name"].scalarText); Text("Auth: \(connector["authStatus"].scalarText) · \(connector["tools"].object.count) tools").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Sign in") { run { openURL(try await controller.connectorLogin(name: connector["name"].string ?? "", threadID: threadID)) } }
                        }
                    }
                    Text("MCP tools become available through the connected server; they are not inserted as fake skill mentions.").font(.caption).foregroundStyle(.secondary)
                    ForEach(controller.skillErrors, id: \.pretty) { Text($0.pretty).font(.caption).foregroundStyle(.orange) }
                    ForEach(["skills", "app/installed", "app/list", "mcpServerStatus/list"], id: \.self) { key in if let message = controller.featureErrors[key] { Text(message).font(.caption).foregroundStyle(.orange) } }
                    if let error { Text(error).foregroundStyle(.orange) }
                }
            }
            HStack {
                Button("Refresh status") { Task { await controller.loadIntegrations(folder: folder, threadID: threadID, forceRefresh: true) } }.disabled(controller.integrationsLoading)
                Button("Reload configured MCP servers") { run { try await controller.reloadConnectors(); await controller.loadIntegrations(folder: folder, threadID: threadID, forceRefresh: true) } }
            }
        }.padding(24).frame(width: 650, height: 580).disabled(busy)
            .task { await controller.loadIntegrations(folder: folder, threadID: threadID) }
    }
    private func sectionHeading(_ title: String, key: String) -> some View {
        HStack {
            Text(title).font(.headline)
            if controller.integrationSectionsLoading.contains(key) {
                ProgressView().controlSize(.small).accessibilityLabel("Loading " + title)
            }
            Spacer()
        }
    }
    private func chooseButton(_ value: CapabilityInput) -> some View { Button(selection.contains(value) ? "Remove" : "Use") { if selection.contains(value) { selection.removeAll { $0 == value } } else { selection.append(value) } } }
    private func safeURL(_ value: String?) -> URL? { guard let value, let url = URL(string: value), ["https", "http"].contains(url.scheme ?? "") else { return nil }; return url }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) { busy = true; Task { defer { busy = false }; do { try await operation() } catch { self.error = error.localizedDescription } } }
}

private extension WireValue {
    var capabilityRowID: String { self["id"].string ?? self["path"].string ?? self["name"].string ?? pretty }
}
