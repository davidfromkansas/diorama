import SwiftUI
import Testing
import DioramaCore
@testable import DioramaApp

@MainActor struct ExecutionPriorityViewsTests {
    @Test func renderPrioritiesInLightAndDark() throws {
        var work = ExecutionWork()
        work.turnID = "fixture"
        work.plan = [.init(id: 0, text: "Inspect sign-in handling", status: "completed"), .init(id: 1, text: "Validate input and show errors", status: "inProgress"), .init(id: 2, text: "Run focused tests", status: "pending")]
        work.diff = "diff --git a/SignIn.swift b/SignIn.swift\n--- a/SignIn.swift\n+++ b/SignIn.swift\n@@ -1,3 +1,4 @@\n func signIn() {\n+    validateInput()\n     authenticate()\n }"
        let request = ExecutionRequest(wireID: .string("question"), method: "item/tool/requestUserInput", params: .object(["isBlocking": .bool(false), "questions": .array([.object(["id": .string("style"), "question": .string("Which error wording should we use?"), "options": .array([.object(["label": .string("Short"), "description": .string("Keep the message concise.")])])])])]))
        let controller = ExecutionController()
        for dark in [false, true] {
            let view = HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Improve sign-in").font(.title2.bold())
                    ExecutionPlanView(work: work)
                    ExecutionRequestView(request: request, controller: controller)
                    ConversationComposer(controller: controller, model: .constant(""), effort: .constant(""), prompt: .constant("Also cover empty passwords"), attachments: .constant([]), approvalReview: .constant(.inherit), effectiveModel: "Codex", sending: false, active: true, canSteer: true, send: {})
                }.frame(width: 600)
                ExecutionChangesView(work: work).frame(width: 500, height: 570)
            }.padding(24).frame(width: 1168, height: 660).background(dark ? Color(white: 0.12) : .white).environment(\.colorScheme, dark ? .dark : .light)
            try render(view, name: "priorities-1-3-" + (dark ? "dark" : "light"), size: CGSize(width: 1168, height: 660))
        }
    }
    @Test func renderConnectorForm() throws {
        let schema: WireValue = .object(["type": .string("object"), "required": .array([.string("project")]), "properties": .object([
            "project": .object(["type": .string("string"), "title": .string("Project"), "enum": .array([.string("Diorama"), .string("Sandbox")])]),
            "limit": .object(["type": .string("integer"), "title": .string("Result limit"), "default": .number(10), "minimum": .number(1)]),
            "archived": .object(["type": .string("boolean"), "title": .string("Include archived items")])])])
        let request = ExecutionRequest(wireID: .string("form"), method: "mcpServer/elicitation/request", params: .object(["mode": .string("form"), "serverName": .string("Project connector"), "message": .string("Choose which records to retrieve."), "requestedSchema": schema]))
        try render(ElicitationFormView(request: request, respond: { _ in }).padding(24).frame(width: 480, height: 520).background(.white).environment(\.colorScheme, .light), name: "priority-3-connector", size: CGSize(width: 480, height: 520))
    }
    private func render<V: View>(_ view: V, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view)
        host.frame.size = size; host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/priority-1-3")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
