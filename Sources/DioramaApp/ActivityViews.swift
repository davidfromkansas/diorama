import SwiftUI
import DioramaCore

struct ActivityBadge: View {
    let summary: ActivitySummary
    var livePhase: ExecutionPhase? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(livePhase.map { "Connected: " + $0.rawValue } ?? ("Last reported: " + summary.state.rawValue), systemImage: summary.state.needsAttention ? "exclamationmark.circle" : summary.state == .working ? "gearshape" : "circle")
                .foregroundStyle(summary.state.needsAttention ? Color.orange : summary.state == .working ? Color.mint : Color.secondary)
            if let current = summary.current { Text(current) }
            if let role = summary.events.last(where: { $0.role != nil })?.role { Text("Recorded role: " + role) }
            if let event = summary.latestState { Text(event.time, style: .relative).foregroundStyle(.secondary) }
        }.font(.caption2)
        .help((summary.error ?? (livePhase == nil ? "Current activity unverified; recorded state may be stale." : "Status from the attached Codex execution connection.")) + (summary.uncertain ? " Missing timestamps or conflicting evidence." : ""))
    }
}

struct ActivityTimeline: View {
    let summary: ActivitySummary
    var livePhase: ExecutionPhase? = nil
    private var grouped: [(ActivityEvent, ActivityEvent?)] {
        var consumed = Set<String>()
        return summary.events.compactMap { event in
            guard !consumed.contains(event.id) else { return nil }
            var end: ActivityEvent?
            if event.kind == "toolStarted", let call = event.callID {
                end = summary.events.first {
                    $0.callID == call && $0.provider == event.provider && $0.sessionID == event.sessionID &&
                    $0.agentID == event.agentID && $0.time >= event.time && ["toolFinished", "toolFailed"].contains($0.kind)
                }
                if let end { consumed.insert(end.id) }
            }
            return (event, end)
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ActivityBadge(summary: summary, livePhase: livePhase)
                Text(livePhase == nil ? "Recorded events · current activity unverified · latest bounded transcript tail and retained hook history" : "Connected execution · bounded activity since attachment · pending requests appear above")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = summary.error { Text(error).foregroundStyle(.orange) }
                if summary.events.isEmpty { Text("No supported activity events observed.").foregroundStyle(.secondary) }
                ForEach(grouped, id: \.0.id) { event, end in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(event.label).font(.headline)
                            Spacer()
                            Text(event.time, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        if event.kind == "toolStarted" {
                            if let end {
                                Text(end.label).font(.caption).foregroundStyle(end.kind == "toolFailed" ? Color.orange : Color.secondary)
                                let duration = end.durationMS.map { $0 / 1000 } ?? end.time.timeIntervalSince(event.time)
                                Text(String(format: "%.1fs · %@ duration", max(0, duration), end.durationMS == nil ? "observed" : "provider"))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else { Text("No completion observed").font(.caption).foregroundStyle(.secondary) }
                        }
                        if livePhase == nil, event.state?.needsAttention == true, summary.attention.contains(where: { $0.id == event.id }) {
                            Text("Resolution unverified · respond in the source client").font(.caption).foregroundStyle(.orange)
                        }
                        DisclosureGroup("Evidence and details") {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.source)
                                Text("Observed: " + event.observedAt.formatted())
                                Text(event.recordedAt.map { "Recorded: " + $0.formatted() } ?? "Provider timestamp unavailable")
                                if let turn = event.turnID { Text("Turn: " + turn) }
                                if let call = event.callID { Text("Tool call: " + call) }
                                if let agent = event.agentID { Text("Subagent: " + agent) }
                                if let role = event.role { Text("Recorded role: " + role) }
                                if let detail = event.detail { Text(verbatim: detail).font(.system(.caption, design: .monospaced)) }
                                if let detail = end?.detail { Text(verbatim: detail).font(.system(.caption, design: .monospaced)) }
                            }.font(.caption).textSelection(.enabled).padding(.top, 4)
                        }.font(.caption)
                    }.padding(14).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(24)
        }
    }
}

struct AttentionInbox: View {
    @Bindable var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Attention inbox").font(.title2); Spacer(); Button("Done") { dismiss() } }
            Text("Diorama tasks: select a request to respond here. Observed tasks: respond in the original client; resolution requires correlated evidence.")
                .font(.caption).foregroundStyle(.secondary)
            if model.attentionSessions.isEmpty { ContentUnavailableView("No observed requests", systemImage: "tray") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.attentionSessions) { session in
                        Button { model.openAttention(session) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(markdownTitle(session.title)).font(.headline)
                                Text(session.project).font(.caption).foregroundStyle(.secondary)
                                Text(session.provider.rawValue + " · " + session.classification.rawValue).font(.caption)
                                ForEach(model.summary(session).attention) { event in
                                    Text(event.label + " · " + event.time.formatted()).font(.caption)
                                    if let detail = event.detail { Text(verbatim: detail).font(.caption).lineLimit(3) }
                                }
                                if model.execution.tasks[session.sessionID]?.attached == true {
                                    Text("Respond in Diorama").font(.caption).foregroundStyle(.mint)
                                } else { Text("Resolution unverified").font(.caption).foregroundStyle(.orange) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.buttonStyle(.plain).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }.padding(24).frame(width: 680, height: 560)
    }
}

struct HookConnections: View {
    @Bindable var model: LibraryModel
    @State private var setup: Provider?
    @State private var removing = false
    @State private var original: Data?
    @State private var preview = Data()
    @State private var message = ""
    @State private var versions: [String: String] = [:]
    private func profile(_ provider: Provider) -> HookCapability {
        .profile(provider: provider, version: versions[provider.rawValue] ?? "Unknown")
    }
    private func prepare(_ provider: Provider, remove: Bool) {
        do {
            let config = HookConfiguration(provider: provider)
            let existing = try config.original()
            preview = try config.preview(original: existing, events: profile(provider).events, remove: remove)
            original = existing; removing = remove; setup = provider
        } catch { message = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Provider.allCases, id: \.rawValue) { provider in
                let capability = profile(provider)
                let installed = HookConfiguration(provider: provider).installed()
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.rawValue + " · " + capability.version).font(.headline)
                    Text(installed ? "Reporter configured · trust/delivery not verified" : "Reporter not configured").font(.caption)
                    Text(capability.explanation).font(.caption).foregroundStyle(.secondary)
                    if let last = model.activity.values.flatMap(\.events).filter({ $0.provider == provider.rawValue && $0.source.hasPrefix("Hook") }).max(by: { $0.observedAt < $1.observedAt }) {
                        Text("Last hook observed: " + last.observedAt.formatted()).font(.caption)
                    }
                    HStack {
                        Button("Enable activity reporting…") { prepare(provider, remove: false) }.disabled(!capability.canInstall)
                        if installed { Button("Remove reporter hooks…") { prepare(provider, remove: true) } }
                        Link("Documentation", destination: URL(string: provider == .codex ? "https://learn.chatgpt.com/docs/hooks" : "https://code.claude.com/docs/en/hooks")!)
                    }.font(.caption)
                }
            }
            HStack {
                Button("Clear activity history") {
                    do { try HookStore.clear(); Task { await model.refresh() } }
                    catch { message = error.localizedDescription }
                }
                Text("Hook records only · 7 days / 50 MiB").font(.caption).foregroundStyle(.secondary)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.orange) }
        }
        .task { versions = await ProviderVersions.read() }
        .sheet(isPresented: Binding(get: { setup != nil }, set: { if !$0 { setup = nil } })) {
            if let provider = setup {
                VStack(alignment: .leading, spacing: 12) {
                    Text(removing ? "Remove Diorama hooks" : "Enable local activity reporting").font(.title2)
                    Text(HookConfiguration(provider: provider).configURL.path).font(.caption).textSelection(.enabled)
                    Text("Changes below preserve other settings and create a backup. Filenames, command previews, and errors may contain sensitive information. Records stay on this Mac. Review hook trust in the source client and restart it; Diorama does not bypass trust or handle approvals.").font(.callout)
                    ScrollView { Text(verbatim: String(decoding: preview, as: UTF8.self)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button("Cancel") { setup = nil }
                        Spacer()
                        Button(removing ? "Remove hooks" : "Apply configuration") {
                            do {
                                let executable = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("DioramaReporter")
                                try HookConfiguration(provider: provider).apply(expected: original, updated: preview, bundledReporter: executable, remove: removing)
                                message = removing ? "Diorama hooks removed. Restart the source client." : "Configuration saved. Review trust in the source client and restart it. Live capability remains unverified."
                                setup = nil
                            } catch { message = error.localizedDescription; setup = nil }
                        }
                    }
                }.padding(24).frame(width: 700, height: 580)
            }
        }
    }
}

actor ProviderVersions {
    @concurrent static func read() async -> [String: String] {
        var result: [String: String] = [:]
        // The native installation takes precedence over a stale global npm package.
        let nativeClaude = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        if FileManager.default.isExecutableFile(atPath: nativeClaude), let text = await versionOutput(nativeClaude) {
            result[Provider.claude.rawValue] = text.components(separatedBy: " ").first
        }
        // Read Claude package metadata: old `claude --version` mutates user configuration.
        for path in ["/usr/local/lib/node_modules/@anthropic-ai/claude-code/package.json", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/package.json"] where result[Provider.claude.rawValue] == nil {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["version"] as? String { result[Provider.claude.rawValue] = version; break }
        }
        let candidates = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }), let text = await versionOutput(path) {
            result[Provider.codex.rawValue] = text.components(separatedBy: " ").last
        }
        return result
    }

    private static func versionOutput(_ path: String) async -> String? {
            let process = Process(); let output = Pipe()
            process.executableURL = URL(fileURLWithPath: path); process.arguments = ["--version"]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
                if process.isRunning { process.terminate(); return nil }
                let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {}
        return nil
    }
}
