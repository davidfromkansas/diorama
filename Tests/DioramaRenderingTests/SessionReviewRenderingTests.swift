import AppKit
import SwiftUI
import Testing
@testable import DioramaCore
@testable import DioramaApp

@MainActor struct SessionReviewRenderingTests {
    @Test func lineNumbersAndStableReviewState() {
        let lines = DiffLine.parse("@@ -2,2 +2,2 @@\n same\n-old\n+new")
        #expect(lines[1].old == 2 && lines[1].new == 2)
        #expect(lines[2].old == 3 && lines[2].new == nil)
        #expect(lines[3].old == nil && lines[3].new == 3)
        let store = SessionReviewStore(); store.state("a").visible = true; store.state("a").selected = "file"
        #expect(!store.state("b").visible)
        #expect(store.state("a").selected == "file")
    }
    @Test func rendersNativeReviewAtNarrowAndWideWidths() async throws {
        let library = LibraryModel()
        var work = ProjectWorkspace(id: "preview", folder: "/tmp/review-preview", branch: "codex/session-changes", baseCommit: "abc", context: ProjectContext())
        work.pullRequest = try JSONDecoder().decode(LinkedPullRequest.self, from: Data(#"{"number":42,"title":"Add session changes","url":"https://github.com/example/repo/pull/42","state":"OPEN","isDraft":false,"headRefName":"codex/session-changes","headRefOid":"abc","headRepository":{"name":"repo"},"headRepositoryOwner":{"login":"example"},"statusCheckRollup":[{"name":"Tests","conclusion":"FAILURE","detailsUrl":"https://github.com/example/repo/actions/runs/1"}]}"#.utf8))
        var project = DioramaProject(name: "UI fixture", folder: work.folder, commonDirectory: "", base: "main", remote: nil); project.workspaces = [work]
        library.projects.projects = [project]
        let session = Session(id: "preview", provider: .claude, url: nil, sessionID: "preview", title: "Session changes", project: work.folder, modified: Date(), bytes: 0, archived: false, parentID: nil)
        let state = SessionReviewState(); state.visible = true; state.checksExpanded = true; state.selected = "Sources/App.swift"
        state.snapshot = ChangesSnapshot(files: [ChangedFile(path: "Sources/App.swift", status: "Modified", added: 2, removed: 1)], head: "abc", branch: work.branch, dirty: true)
        state.patch = "diff --git a/Sources/App.swift b/Sources/App.swift\n@@ -1,3 +1,4 @@\n struct App {\n-    let title = \"Before\"\n+    let title = \"Session Changes\"\n+    let ready = true\n }"
        let view = SessionReviewContainer(session: session, workspaceID: work.id, projectID: project.id, library: library, review: state)
        for width in [480.0, 780.0] {
            let host = NSHostingView(rootView: view.panel(work))
            host.appearance = NSAppearance(named: .aqua)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 780)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Diorama Review Verification"
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(400))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-review-\(Int(width)).png"))
            if ProcessInfo.processInfo.environment["DIORAMA_MANUAL_REVIEW"] == "1", width == 480 { try await Task.sleep(for: .seconds(90)) }
            window.orderOut(nil)
        }
    }
}
