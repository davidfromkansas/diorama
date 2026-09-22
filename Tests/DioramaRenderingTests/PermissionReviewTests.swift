import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct PermissionReviewTests {
    @Test func fullSessionPermissionRemainsWithinViewport() async throws {
        let controller = ExecutionController()
        let session = Session(id: "Codex:permission-fixture", provider: .codex, url: nil, sessionID: "permission-fixture", title: "Update the garden heading", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        var task = ExecutedTask(id: session.sessionID, title: session.title, folder: "/tmp", turnID: "turn", attached: true)
        task.model = "gpt-6-astra"
        controller.tasks[session.sessionID] = task
        await controller.receive(.object(["id": .string("approval"), "method": .string("item/fileChange/requestApproval"), "params": .object(["threadId": .string(session.sessionID), "turnId": .string("turn"), "itemId": .string("patch"), "availableDecisions": .array([.string("accept"), .string("decline"), .string("acceptForSession")])])]))
        let model = LibraryModel(execution: controller)
        model.sessions = [session]; model.selectedID = session.id; model.transcriptSessionID = session.id; model.projectNavigation = true
        let view = SessionView(session: session, model: model, hasLocalReview: true).frame(width: 650, height: 520).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame.size = NSSize(width: 650, height: 520); host.layoutSubtreeIfNeeded()
        func editors(_ view: NSView) -> [ComposerNSTextView] {
            (view as? ComposerNSTextView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        let editor = try #require(editors(host).first)
        let bounds = editor.convert(editor.bounds, to: host)
        #expect(host.bounds.contains(bounds), "Composer must remain inside the session viewport: \(bounds)")
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-full-permission.png"))
    }
    @Test func cardFitsNarrowWindowWithoutClippingDecisions() throws {
        let request = ExecutionRequest(wireID: .string("example"), method: "item/commandExecution/requestApproval", params: .object(["toolName": .string("Read"), "toolInput": .object(["file_path": .string("/Users/example/Projects/Diorama/Package.swift")]), "availableDecisions": .array([.string("accept"), .string("decline")])]))
        for width in [460.0, 800.0] {
            let view = PermissionReviewCard(request: request, connected: true, respond: { _ in }).padding(16).frame(width: width).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame.size = host.fittingSize; host.layoutSubtreeIfNeeded()
            #expect(host.bounds.height < 360)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-permission-\(Int(width)).png"))
        }
    }
}
