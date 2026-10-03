import SwiftUI
import Observation
import DioramaCore

@Observable final class ActivityPanelState {
    var visible = false
    var section = "Plan"
    var selectedPlan: String?
    var selectedAgent: String?
    var scrolls: [String: String] = [:]
    var scroll: String? {
        get { scrolls[section] }
        set { scrolls[section] = newValue }
    }
}

extension LibraryModel {
    func activityState(_ session: Session) -> ActivityPanelState {
        if let state = activityPanels[session.id] { return state }
        let state = ActivityPanelState(); activityPanels[session.id] = state; return state
    }
    func activitySnapshot(_ session: Session) -> SessionActivitySnapshot {
        let ids = conversations.record(session.id)?.segments.map(\.nativeID) ?? [session.sessionID]
        var result = SessionActivitySnapshot()
        for id in ids {
            let provider = conversations.record(session.id)?.segments.first(where: { $0.nativeID == id }).flatMap { Provider(rawValue: $0.provider) } ?? session.provider
            let snapshot = execution.activitySnapshot(provider: provider, id: id)
            result.records += snapshot.records
            result.events += snapshot.events
            result.lastKnown = result.lastKnown || snapshot.lastKnown || execution.tasks[id]?.attached != true
            result.truncated = result.truncated || snapshot.truncated
        }
        result.events.sort { $0.observedAt < $1.observedAt }
        // Disk byte limits are enforced off the main actor by the journal store.
        // Do not JSON-encode the entire history during every SwiftUI evaluation.
        if result.events.count > 10_000 {
            result.events = Array(result.events.suffix(10_000)); result.truncated = true
        }
        return result
    }
}

struct SessionActivityPanel: View {
    let session: Session
    @Bindable var library: LibraryModel
    @Bindable var state: ActivityPanelState
    var close: () -> Void
    @State private var history: Transcript?
    @State private var historyError: String?
    private var snapshot: SessionActivitySnapshot { library.activitySnapshot(session) }
    private var selected: SessionActivityRecord? { snapshot.agents.first { $0.id == state.selectedAgent } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: close) { Label("Back to conversation", systemImage: "chevron.left") }.pointingHand()
                Spacer()
                Text(snapshot.lastKnown ? "Last known" : "Reported activity").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Activity section", selection: $state.section) {
                ForEach(["Plan", "Steps", "Agents", "Timeline"], id: \.self) { Text($0).tag($0) }
            }.pointingHand().pickerStyle(.segmented)
            .accessibilityHint("Plan, Steps, Agents, Timeline. Command Option 1 through 4 select a section.")
            HStack(spacing: 0) {
                ForEach(Array(["Plan", "Steps", "Agents", "Timeline"].enumerated()), id: \.offset) { index, section in
                    Button(section) { state.section = section }.pointingHand()
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                }
            }.frame(width: 0, height: 0).clipped().accessibilityHidden(true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if state.section == "Plan" { plans }
                    else if state.section == "Steps" { steps }
                    else if state.section == "Agents" { agents }
                    else { timeline }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    .scrollTargetLayout()
            }.scrollPosition(id: $state.scroll)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: state.selectedPlan) { _, id in if state.section == "Plan" { state.scroll = id } }
        .onAppear { if state.section == "Plan", let id = state.selectedPlan { state.scroll = id } }
        .task(id: state.section) {
            guard state.section == "Agents" else { return }
            while !Task.isCancelled {
                await library.execution.refreshAgents(session)
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .task(id: state.selectedAgent) {
            history = nil; historyError = nil
            guard let selected else { return }
            do {
                let value = try await library.execution.inspectChild(provider: Provider(rawValue: selected.provider) ?? session.provider,
                    parentID: selected.sessionID, childID: selected.nativeID, folder: session.project)
                if state.selectedAgent == selected.id {
                    if let error = value.error { historyError = "Details unavailable: " + error } else { history = value }
                }
            } catch { if state.selectedAgent == selected.id { historyError = "Details unavailable: " + error.localizedDescription } }
        }
    }
    @ViewBuilder private var plans: some View {
        if snapshot.plans.isEmpty { Text("No structured plan has been reported yet.").foregroundStyle(.secondary) }
        ForEach(snapshot.plans) { plan in
            VStack(alignment: .leading, spacing: 10) {
                Label(plan.status == "draft" ? "Draft plan" : "Proposed plan", systemImage: "doc.text").font(.headline)
                Text(plan.provider).font(.caption).foregroundStyle(.secondary)
                TranscriptContent(text: plan.detail)
                details(plan)
            }.id(plan.id)
        }
    }
    @ViewBuilder private var steps: some View {
        Text("Agent-reported steps. A finished turn does not complete unfinished steps.").font(.caption).foregroundStyle(.secondary)
        if snapshot.steps.isEmpty { Text("No structured steps reported. Availability depends on the agent and runtime.").foregroundStyle(.secondary) }
        ForEach(snapshot.steps) { step in
            Label {
                VStack(alignment: .leading, spacing: 4) { Text(step.title); Text(status(step.status)).font(.caption).foregroundStyle(.secondary) }
            } icon: { Image(systemName: step.status == "completed" ? "checkmark.circle.fill" : ["inProgress", "in_progress"].contains(step.status) ? "circle.lefthalf.filled" : "circle") }
            .id(step.id)
        }
    }
    @ViewBuilder private var agents: some View {
        if let selected {
            Button("Back to parent task") { state.selectedAgent = nil }.pointingHand()
            Text(displayName(selected)).font(.headline)
            Text(status(selected.status))
            if !selected.detail.isEmpty { Text(selected.detail) }
            details(selected)
            if let historyError { Text(historyError).foregroundStyle(.secondary) }
            else if let history {
                Text("Saved conversation").font(.headline)
                if history.entries.isEmpty { Text("No saved messages available.").foregroundStyle(.secondary) }
                ForEach(history.entries) { EntryView(entry: $0) }
            } else { ProgressView("Reading saved conversation") }
        } else {
            Text("Parent task").font(.headline)
            if snapshot.agents.isEmpty { Text("No subagents or background jobs reported yet.").foregroundStyle(.secondary) }
            ForEach(orderedAgents) { agent in
                Button { state.selectedAgent = agent.id } label: {
                    HStack(alignment: .top) {
                        Image(systemName: agent.kind == "agent" ? "person.crop.circle" : "terminal")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName(agent)).lineLimit(3)
                            Text((agent.kind == "job" ? "Background job · " : "") + status(agent.status)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }.pointingHand().buttonStyle(.plain)
                .accessibilityLabel(agentAccessibilityLabel(agent))
                .accessibilityHint("Opens saved details without starting or resuming this agent.")
                .padding(.leading, CGFloat(depth(agent) * 18)).id(agent.id)
            }
        }
    }
    @ViewBuilder private var timeline: some View {
        if snapshot.truncated { Text("Earlier history was truncated. Current state is retained as a baseline.").font(.caption).foregroundStyle(.secondary) }
        if snapshot.events.isEmpty { Text("No structured activity recorded yet.").foregroundStyle(.secondary) }
        ForEach(snapshot.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(event.title.isEmpty ? event.kind.capitalized : event.title).font(.headline); Spacer(); Text(event.observedAt, style: .time).font(.caption) }
                Text(status(event.status)).font(.caption).foregroundStyle(.secondary)
                if !event.detail.isEmpty { Text(event.detail).lineLimit(4) }
                details(event)
            }.id(event.id)
            Divider()
        }
    }
    private func displayName(_ agent: SessionActivityRecord) -> String {
        guard agent.kind == "agent" else { return agent.title.isEmpty ? "Background job" : agent.title }
        return library.agentDisplayName(session, agent: [agent.provider, agent.sessionID, agent.nativeID].joined(separator: "\u{1F}"), reported: agent.reportedAgentName)
    }
    private func agentAccessibilityLabel(_ agent: SessionActivityRecord) -> String {
        let title = displayName(agent)
        return "\(title), \(status(agent.status)), nesting level \(depth(agent) + 1)"
    }
    private var orderedAgents: [SessionActivityRecord] {
        var result: [SessionActivityRecord] = [], seen = Set<String>()
        func visit(_ agent: SessionActivityRecord) {
            guard seen.insert(agent.id).inserted else { return }
            result.append(agent)
            for child in snapshot.agents where child.provider == agent.provider && (child.parentID == agent.nativeID || child.parentID == agent.data["delegationID"].string) { visit(child) }
        }
        for agent in snapshot.agents where depth(agent) == 0 { visit(agent) }
        for agent in snapshot.agents { visit(agent) } // Orphans and cycles remain inspectable.
        return result
    }
    private func depth(_ agent: SessionActivityRecord) -> Int {
        var current = agent, seen: Set<String> = [agent.id], depth = 0
        while let parent = snapshot.agents.first(where: { $0.provider == current.provider && ($0.nativeID == current.parentID || $0.data["delegationID"].string == current.parentID) }), seen.insert(parent.id).inserted {
            depth += 1; current = parent
        }
        return min(depth, 6)
    }
    private func status(_ raw: String) -> String {
        switch raw { case "inProgress", "in_progress", "running": "In progress"; case "completed": "Completed"; case "pending": "Pending"; case "unknown", "": "Unknown"; default: raw.capitalized }
    }
    private func details(_ record: SessionActivityRecord) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.source + " · " + record.provider)
                Text("Native ID: " + record.nativeID)
                if let parent = record.parentID { Text("Parent / delegation: " + parent) }
                if let turn = record.turnID { Text("Turn: " + turn) }
                Text(record.recordedAt.map { "Provider time: " + $0.formatted() } ?? "Provider timestamp unavailable")
                Text("Observed: " + record.observedAt.formatted())
                if let model = record.data["model"].string { Text("Model: " + model) }
                if let tool = record.data["lastTool"].string { Text("Latest tool: " + tool) }
                if let duration = record.data["duration_ms"].number ?? record.data["durationMs"].number ?? record.data["usage"]["duration_ms"].number { Text(String(format: "Reported duration: %.1f seconds", duration / 1000)) }
                if record.kind == "usage" || record.data["usage"] != .null {
                    Text("Usage at the reported scope; overlapping counters are not added together.")
                    let usage = record.data["usage"] == .null ? record.data : record.data["usage"]
                    ForEach(["input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "total_tokens"], id: \.self) { key in
                        if let count = usage[key].number { Text(key.replacingOccurrences(of: "_", with: " ").capitalized + ": " + Int(count).formatted()) }
                    }
                }
                if record.data != .null { DisclosureGroup { Text(record.data.pretty).font(.system(.caption, design: .monospaced)) } label: { Text("Provider fields").disclosurePointingHand() } }
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
        } label: { Text("Details").disclosurePointingHand() }.font(.caption)
    }
}
