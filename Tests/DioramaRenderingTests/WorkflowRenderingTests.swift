import SwiftUI
import Testing
@testable import DioramaCore
@testable import DioramaApp

private actor PreviewWorkflowTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue> = AsyncStream { $0.finish() }
    func connect() {}
    func request(_ method: String, _ params: WireValue) -> WireValue { .object(["data": .array([]), "goal": .null]) }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}
@MainActor struct WorkflowRenderingTests {
    @Test func renderGoalsModesQueueUsageAndRichTools() throws {
        let c = ExecutionController(transport: PreviewWorkflowTransport())
        var task = ExecutedTask(id: "fixture", title: "Improve sign-in", folder: "/tmp", phase: .working, turnID: "turn", attached: true)
        task.workflow.goal = .object(["objective": .string("Make sign-in validation clear and reliable"), "status": .string("active"), "tokensUsed": .number(3200), "tokenBudget": .number(12000)])
        task.workflow.usage = .object(["last": .object(["totalTokens": .number(3200)]), "total": .object(["totalTokens": .number(9200)]), "modelContextWindow": .number(200000)])
        task.workflow.queue = [.object(["id": .string("queued"), "input": .array([.object(["type": .string("text"), "text": .string("Then check keyboard navigation")])])])]
        c.tasks["fixture"] = task
        c.collaborationModes = [.object(["mode": .string("plan"), "name": .string("Plan")]), .object(["mode": .string("default"), "name": .string("Default")])]
        c.rateLimits = .object(["rateLimits": .object(["primary": .object(["usedPercent": .number(15), "resetsAt": .number(1790000000)])])])
        let tool = try #require(ToolResult(item: .object(["type": .string("commandExecution"), "command": .string("swift test --filter SignInTests"), "status": .string("completed"), "aggregatedOutput": .string("All 8 sign-in tests passed."), "exitCode": .number(0), "durationMs": .number(820)])))
        for dark in [false, true] {
            let view = HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Improve sign-in").font(.title2.bold())
                    HStack { Text("Conversation"); Spacer(); Text("Find   Review   •••").foregroundStyle(.secondary) }
                    Text("Validation handles empty fields and provides accessible errors.")
                    RichToolResultView(result: tool)
                    Spacer()
                    WorkflowControls(controller: c, task: task, mode: .constant(""), capabilities: .constant([.init(name: "Accessibility review", path: "/tmp/SKILL.md", kind: "skill")]), queueNext: .constant(true))
                    ConversationComposer(controller: c, model: .constant(""), effort: .constant(""), prompt: .constant("Then check keyboard navigation"), attachments: .constant([]), approvalReview: .constant(.inherit), effectiveModel: "Codex", sending: false, active: true, canSteer: true, queued: true, send: {})
                }.frame(width: 750)
                UsageView(controller: c, task: task).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            }.padding(24).frame(width: 1220, height: 700).background(dark ? Color(white: 0.12) : .white).environment(\.colorScheme, dark ? .dark : .light)
            let host = NSHostingView(rootView: view); host.frame.size = CGSize(width: 1220, height: 700); host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/workflows")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent(dark ? "workflow-dark.png" : "workflow-light.png"))
        }
    }
}
