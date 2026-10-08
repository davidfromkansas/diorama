import AppKit
@testable import DioramaCore
import SwiftUI
import Testing
@testable import DioramaApp

@MainActor struct ReviewModalTests {
    func approval(_ decisions: [String]? = nil, method: String = "item/commandExecution/requestApproval") -> ExecutionRequest {
        var params: [String: WireValue] = ["threadId": .string("t"), "turnId": .string("turn"), "command": .string("npm test -- auth/signin.test.ts"),
                                           "reason": .string("Run the sign-in tests to confirm the redirect fix."), "cwd": .string("/tmp/fix-sign-in-flow")]
        if let decisions { params["availableDecisions"] = .array(decisions.map(WireValue.string)) }
        if method == "item/permissions/requestApproval" { params["permissions"] = .object(["network": .object(["enabled": .bool(true)])]) }
        return ExecutionRequest(wireID: .string("a"), method: method, params: .object(params))
    }
    let question = ExecutionRequest(wireID: .string("q"), method: "item/tool/requestUserInput", params: .object([
        "threadId": .string("t"), "questions": .array([.object(["id": .string("theme"), "question": .string("Which colour theme should the dashboard use?"),
            "options": .array([.object(["label": .string("Bold purple"), "description": .string("High contrast, playful accent colour")]),
                               .object(["label": .string("Calm blue"), "description": .string("Neutral, matches most products")])])])])]))

    @Test func approvalChoicesKeepTheirPayloadsAndPutAllowOnceLast() {
        let decisions = RequestDecisions(approval(["accept", "acceptForSession", "decline", "cancel"]))
        #expect(decisions.footer.map(\.title) == ["Deny", "Allow for session", "Allow once"])
        #expect(decisions.footer.last?.primary == true && decisions.footer.dropLast().allSatisfy { !$0.primary })
        #expect(decisions.footer.last?.result == .object(["decision": .string("accept")]))
        #expect(decisions.more.map(\.title) == ["Cancel turn"])
        // Permission requests keep their turn-scoped grant and denial.
        let permissions = RequestDecisions(approval(method: "item/permissions/requestApproval"))
        #expect(permissions.footer.map(\.title) == ["Deny", "Allow for this turn"])
        #expect(permissions.footer[1].result["scope"] == .string("turn") && permissions.footer[0].result["permissions"] == .object([:]))
        #expect(RequestKind(approval()) == .approval && RequestKind(question) == .question)
        #expect(RequestKind(question).band(blocking: true).detail == "work paused until you answer")
    }

    @Test func captureModals() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_MODAL_CAPTURE"] == "1" else { return }
        let controller = ExecutionController()
        func shot<V: View>(_ view: V, _ name: String, height: CGFloat) throws {
            let host = NSHostingView(rootView: view.fixedSize(horizontal: false, vertical: true).background(SidebarStyle.background).environment(\.colorScheme, .light))
            host.frame = NSRect(x: 0, y: 0, width: 560, height: height); host.layoutSubtreeIfNeeded()
            host.frame.size = host.fittingSize; host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-modal-\(name).png"))
        }
        let link = Button("Open conversation") {}.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SidebarStyle.accent)
        try shot(VStack(spacing: 0) {
            ModalHeader(group: .needsYou, title: "Fix sign-in flow", status: "Needs approval", model: "Claude Opus 5.5") {}
            RequestReviewContent(request: approval(["accept", "acceptForSession", "decline"]), controller: controller, position: "1 of 2") { link }
        }.frame(width: 560), "approval", height: 520)
        try shot(ExecutionRequestView(request: approval(["accept", "acceptForSession", "decline"]), controller: controller).padding(12).frame(width: 560), "compact", height: 260)
        try shot(VStack(spacing: 0) {
            ModalHeader(group: .needsYou, title: "Add stats dashboard", status: "Needs an answer", model: "GPT-6 Astra") {}
            RequestReviewContent(request: question, controller: controller, wide: true) { link } skip: {}
        }.frame(width: 720), "question", height: 560)
        var agent = SpatialAgent(projectID: nil, conversationID: "c", value: WorkspaceAgent(id: "main", name: "Remy", provider: Provider.codex.rawValue, task: "Update app icon",
                                    action: "", status: .done, reportedStatus: "Done", freshness: .live))
        agent.value.reportedModel = "gpt-6-astra"
        var work = TurnWork()
        work.started(tool: "apply_patch", detail: "Resources/AppIcon.icon", call: "e")
        work.started(tool: "Bash", detail: "npm test", call: "t"); work.finished(call: "t", failed: false)
        agent.value.turnWork = work
        let session = Session(id: "c", provider: .codex, url: nil, sessionID: "c", title: "Update app icon", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        try shot(ServingWindowView(agent: agent, session: session, library: LibraryModel(execution: controller)), "review", height: 700)
    }
}
