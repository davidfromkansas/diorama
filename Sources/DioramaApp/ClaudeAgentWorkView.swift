import SwiftUI
import DioramaCore

/// Uses observed snapshots only. Selecting a desk never attaches execution.
struct AgentWorkDetailsView: View {
    @Bindable var library: LibraryModel
    let parent: Session?
    let agent: WorkspaceAgent
    var openConversation: () -> Void
    private var session: Session? {
        guard let parent else { return nil }
        if agent.isMain { return parent }
        guard let record = library.activitySnapshot(parent).records.first(where: { $0.id == agent.activityRecordID }) else { return nil }
        return library.sessions.first { $0.classification == .subagent && ($0.id == record.nativeID || ($0.provider == .codex && $0.sessionID == record.nativeID)) }
    }
    private var snapshot: ExternalObservationSnapshot? { session.flatMap { library.observations[$0.id] } }
    private var entries: [Entry] {
        if let snapshot { return Array(snapshot.transcript.entries.filter { ($0.claude != nil || $0.codex != nil || $0.tool != nil || $0.kind == "Proposed plan") && (!agent.isMain || $0.claude?.agentID == nil) }.suffix(8)) }
        return []
    }
    var body: some View {
        if parent != nil {
            Divider()
            if entries.isEmpty { Text("No recent structured work is available for this agent.").foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                if let presentation = entry.claude {
                    ClaudeEntryView(entry: entry, presentation: presentation)
                } else if let presentation = entry.codex {
                    CodexEntryView(entry: entry, presentation: presentation, selectWorker: { library.openWorker($0) })
                } else if let tool = entry.tool {
                    RichToolResultView(result: tool, selectWorker: { library.openWorker($0) })
                } else if entry.kind == "Proposed plan" {
                    DisclosureGroup("Proposed plan") { TranscriptContent(text: entry.text) }
                }
                Group {
                    Button("View in conversation") {
                        guard let session else { return }
                        library.scrollPositions[session.id] = entry.id
                        library.openInWorkspace(session)
                        openConversation()
                    }.font(.caption)
                }
            }
            if let snapshot {
                ForEach(snapshot.structured.records.filter { $0.kind == "step" }.suffix(12)) { step in
                    Label(step.title + " · " + step.status, systemImage: step.status == "completed" ? "checkmark.circle" : "circle")
                }
                if let error = snapshot.error { Text(error).foregroundStyle(.orange) }
            }
        }
    }
}
