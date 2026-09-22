import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct StructuredActivityRenderingTests {
    @Test func panelsRenderAtNarrowWidthAndPreserveDraft() throws {
        let controller = ExecutionController()
        let session = Session(id: "fixture", provider: .claude, url: nil, sessionID: "fixture", title: "Activity fixture", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        var task = ExecutedTask(id: session.sessionID, provider: .claude, title: session.title, folder: "/tmp", attached: true)
        let payloads = [
            #"{"method":"item/completed","params":{"item":{"id":"plan","type":"plan","text":"Make sessions observable\n\n1. Preserve provider facts.\n2. Show plans, steps and agents.\n3. Verify permissions and restart behavior.\n\nEarlier proposals remain readable."}}}"#,
            #"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[{"step":"Preserve provider activity","status":"completed"},{"step":"Verify saved child conversations at narrow widths","status":"inProgress"}]}}"#,
            #"{"method":"item/completed","params":{"item":{"id":"spawn","type":"collabAgentToolCall","senderThreadId":"fixture","receiverThreadIds":["child"],"prompt":"Inspect the fixture","agentsStates":{"child":{"status":"running","agentNickname":"Review agent"}}}}}"#
        ]
        for json in payloads { SessionActivityReducer.ingest(try JSONDecoder().decode(WireValue.self, from: Data(json.utf8)), provider: .codex, sessionID: "fixture", into: &task.structuredActivity) }
        controller.tasks[session.sessionID] = task
        let model = LibraryModel(execution: controller)
        model.drafts[session.id] = ConversationDraft()
        model.drafts[session.id]?.text = "Unsent draft stays here"
        let state = model.activityState(session)
        for section in ["Plan", "Steps", "Agents", "Timeline"] {
            state.section = section
            let view = SessionActivityPanel(session: session, library: model, state: state, close: {}).frame(width: 420, height: 640).background(Color(white: 0.12)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let image = try #require(renderer.nsImage)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-activity-" + section.lowercased() + ".png"))
            #expect(model.drafts[session.id]?.text == "Unsent draft stays here")
        }
        #expect(model.activityState(session) === state)
        #expect(model.activitySnapshot(session).steps.count == 2)
    }
}
