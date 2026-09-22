import SwiftUI
import Observation
@testable import DioramaCore

// Isolated native host: real activity panel, synthetic data, no provider connection or user storage.
@Observable final class LibraryModel {
    let execution = ExecutionController()
    let conversations = PreviewConversations()
    var activityPanels: [String: ActivityPanelState] = [:]
}
struct PreviewConversations { func record(_ id: String) -> DioramaConversation? { nil } }
struct TranscriptContent: View { let text: String; var body: some View { Text(text).textSelection(.enabled) } }
struct EntryView: View { let entry: Entry; var body: some View { Text(entry.text) } }

@main struct ActivityVerificationApp: App {
    var body: some Scene {
        WindowGroup("Diorama Activity Verification") { Preview().frame(minWidth: 420, minHeight: 580).preferredColorScheme(.dark) }
            .defaultSize(width: 440, height: 700)
    }
}
struct Preview: View {
    @State private var library = LibraryModel()
    @State private var panel = ActivityPanelState()
    @State private var draft = "Unsent draft stays here"
    private let session = Session(id: "fixture", provider: .codex, url: nil, sessionID: "fixture", title: "UI fixture", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
    var body: some View {
        VStack(spacing: 0) {
            Text("Isolated UI verification · synthetic provider facts").font(.caption).foregroundStyle(.secondary).padding(8)
            if panel.visible { SessionActivityPanel(session: session, library: library, state: panel, close: { panel.visible = false }) }
            else { Button("Open activity") { panel.visible = true }.padding(40) }
            Divider()
            TextField("Composer draft", text: $draft).textFieldStyle(.roundedBorder).padding(16)
        }.onAppear {
            var task = ExecutedTask(id: "fixture", title: "UI fixture", folder: "/tmp")
            let events: [WireValue] = [
                .object(["method": .string("item/completed"), "params": .object(["item": .object(["id": .string("plan"), "type": .string("plan"), "text": .string("Make sessions observable\n\nPreserve provider facts, then show them in one activity panel. Keep the composer ready to use.\n\n" + String(repeating: "Verify plans, steps, child history and restart behavior.\n\n", count: 14))])])]),
                .object(["method": .string("turn/plan/updated"), "params": .object(["turnId": .string("turn"), "plan": .array([.object(["step": .string("Preserve provider facts"), "status": .string("completed")]), .object(["step": .string("Verify child history and narrow layouts"), "status": .string("inProgress")])])])]),
                .object(["method": .string("item/completed"), "params": .object(["item": .object(["id": .string("spawn"), "type": .string("collabToolCall"), "newThreadId": .string("child"), "senderThreadId": .string("fixture"), "prompt": .string("Inspect the fixture"), "agentStatus": .string("running")])])])
            ]
            for event in events { SessionActivityReducer.ingest(event, provider: .codex, sessionID: "fixture", into: &task.structuredActivity) }
            for (child, parent) in [("grandchild", "child"), ("sibling", "fixture")] {
                let item: WireValue = .object(["id": .string("spawn-" + child), "type": .string("collabToolCall"), "newThreadId": .string(child), "senderThreadId": .string(parent), "agentStatus": .string("running")])
                SessionActivityReducer.ingest(.object(["method": .string("item/completed"), "params": .object(["item": item])]), provider: .codex, sessionID: "fixture", into: &task.structuredActivity)
            }
            library.execution.tasks["fixture"] = task
            panel.visible = true
        }
    }
}
