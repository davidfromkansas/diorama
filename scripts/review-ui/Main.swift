import SwiftUI
import Observation
@testable import DioramaCore

// Isolated host for the production review panel; no provider connections or saved user projects.
@Observable final class LibraryModel {
    let projects = ProjectModel()
    let execution = PreviewExecution()
    let reviews = SessionReviewStore()
    var draft = "Existing draft"
    func appendReviewDraft(_ id: String, text: String) { draft += "\n\n" + text }
}
@Observable final class PreviewExecution { var tasks: [String: PreviewTask] = [:] }
struct PreviewTask { var phase = "idle" }
@Observable final class ProjectModel {
    var projects: [DioramaProject] = []
    func updateWorkspace(_ id: String, id workID: String, _ body: (inout ProjectWorkspace) -> Void) {}
}
struct SessionView: View {
    let session: Session; let model: LibraryModel; var hasLocalReview = false
    var body: some View { Text("Conversation preview") }
}
@main struct ReviewVerificationApp: App {
    var body: some Scene { WindowGroup("Diorama Review Verification") { Preview().frame(minWidth: 440, minHeight: 580) } }
}
struct Preview: View {
    @State private var library = LibraryModel()
    @State private var review = SessionReviewState()
    let work: ProjectWorkspace
    let project: DioramaProject
    let session: Session
    init() {
        var w = ProjectWorkspace(id: "preview", folder: "/tmp/review-preview", branch: "codex/session-changes", baseCommit: "abc", context: ProjectContext())
        w.pullRequest = try! JSONDecoder().decode(LinkedPullRequest.self, from: Data(#"{"number":42,"title":"Add session changes","url":"https://github.com/example/repo/pull/42","state":"OPEN","isDraft":false,"headRefName":"codex/session-changes","headRefOid":"abc","headRepository":{"name":"repo"},"headRepositoryOwner":{"login":"example"},"statusCheckRollup":[{"name":"Tests","conclusion":"FAILURE"}]}"#.utf8))
        work = w
        var p = DioramaProject(name: "UI fixture", folder: w.folder, commonDirectory: "", base: "main", remote: nil); p.workspaces = [w]; project = p
        session = Session(id: "preview", provider: .claude, url: nil, sessionID: "preview", title: "Session changes", project: w.folder, modified: Date(), bytes: 0, archived: false, parentID: nil)
    }
    var body: some View {
        VStack {
            Text("Isolated review verification · fixture data").font(.caption).foregroundStyle(.secondary)
            SessionReviewContainer(session: session, workspaceID: work.id, projectID: project.id, library: library, review: review).panel(work)
            Text(library.draft).font(.caption).padding()
        }.frame(minWidth: 440, maxWidth: 480, minHeight: 580).onAppear {
            library.projects.projects = [project]
            review.visible = true; review.checksExpanded = true; review.selected = "Sources/App.swift"
            review.snapshot = ChangesSnapshot(files: [ChangedFile(path: "Sources/App.swift", status: "Modified", added: 2, removed: 1)], head: "abc", branch: work.branch, dirty: true)
            review.patch = "@@ -1,3 +1,4 @@\n struct App {\n-    let title = \"Before\"\n+    let title = \"Session Changes\"\n+    let ready = true\n }"
        }
    }
}
