import AppKit
import SwiftUI
import Testing
@testable import DioramaCore
@testable import DioramaApp

@MainActor struct SessionReviewApprovalLayoutTests {
    @Test func approvalComposerFitsInsideRealReviewContainer() async throws {
        let controller = ExecutionController()
        let session = Session(id: "Codex:review-approval", provider: .codex, url: nil, sessionID: "review-approval", title: "Update the garden heading", project: "/tmp/review-approval-fixture", modified: Date(), bytes: 0, archived: false, parentID: nil)
        var task = ExecutedTask(id: session.sessionID, title: session.title, folder: session.project, turnID: "turn", attached: true)
        task.model = "gpt-6-astra"
        task.transcript.entries = (0..<20).map { Entry(id: "message-\($0)", kind: "Assistant", text: "Inspecting the local worktree.\n\n" + String(repeating: "A detailed transcript row that wraps across the available conversation width. ", count: 8), timestamp: nil) }
        controller.tasks[session.sessionID] = task
        await controller.receive(.object(["id": .string("approval"), "method": .string("item/fileChange/requestApproval"), "params": .object(["threadId": .string(session.sessionID), "turnId": .string("turn"), "itemId": .string("patch"), "availableDecisions": .array([.string("accept"), .string("decline")])])]))
        let model = LibraryModel(execution: controller)
        model.sessions = [session]; model.selectedID = session.id; model.transcriptSessionID = session.id; model.projectNavigation = true
        let workspace = ProjectWorkspace(id: "review-approval-work", folder: session.project, branch: "codex/test", baseCommit: "abc", context: ProjectContext())
        var project = DioramaProject(name: "Approval fixture", folder: session.project, commonDirectory: "", base: "main", remote: nil)
        project.workspaces = [workspace]; model.projects.projects = [project]
        let review = SessionReviewState()
        // Real production container: the GeometryReader was absent from the old
        // standalone SessionView approval regression.
        let view = SessionReviewContainer(session: session, workspaceID: workspace.id, projectID: project.id, library: model, review: review)
        for height in [520.0, 600.0] {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: 650, height: height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = host
            // Attach to the native window tree without taking desktop focus.
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            func editors(_ view: NSView) -> [ComposerNSTextView] {
                (view as? ComposerNSTextView).map { [$0] } ?? view.subviews.flatMap(editors)
            }
            let editor = try #require(editors(host).first)
            let bounds = editor.convert(editor.bounds, to: host)
            #expect(abs(window.contentLayoutRect.height - height) < 1, "Native window must retain the requested test viewport")
            #expect(bounds.height > 40)
            #expect(host.bounds.contains(bounds), "Composer must remain inside production review viewport: \(bounds), host \(host.bounds)")
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-review-approval-\(Int(height)).png"))
            window.orderOut(nil)
        }
    }
}
