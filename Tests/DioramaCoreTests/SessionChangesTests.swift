import Foundation
import Testing
@testable import DioramaCore

struct SessionChangesTests {
    @Test func scopesAndIsolation() async throws {
        let root = try await ProjectTests().repository(); defer { try? FileManager.default.removeItem(at: root) }
        let project = try await ProjectGit.discover(root.path)
        let first = try await ProjectGit.createWorkspace(project: project, id: "changes-a", root: root.appendingPathComponent("trees"))
        let second = try await ProjectGit.createWorkspace(project: project, id: "changes-b", root: root.appendingPathComponent("trees"))
        let folder = URL(fileURLWithPath: first.folder)
        try Data("committed\n".utf8).write(to: folder.appendingPathComponent("sample.txt"))
        _ = try await ProjectCommand.git(first.folder, ["commit", "-am", "Change"])
        #expect(try await SessionChanges.snapshot(first, scope: .session).files.count == 1)
        #expect(try await SessionChanges.snapshot(first, scope: .uncommitted).files.isEmpty)
        #expect(try await SessionChanges.snapshot(second, scope: .session).files.isEmpty)
        try Data("one\ntwo\n".utf8).write(to: folder.appendingPathComponent("odd\tname\n.txt"))
        try Data([0,1,2]).write(to: folder.appendingPathComponent("binary"))
        let snapshot = try await SessionChanges.snapshot(first, scope: .session)
        let odd = try #require(snapshot.files.first { $0.path == "odd\tname\n.txt" })
        #expect(odd.added == 2)
        #expect(try await SessionChanges.diff(odd, workspace: first, scope: .session).contains("+two"))
        let binary = try #require(snapshot.files.first { $0.path == "binary" })
        #expect(try await SessionChanges.diff(binary, workspace: first, scope: .session).contains("Binary"))
        _ = try await ProjectCommand.git(first.folder, ["mv", "sample.txt", "renamed.txt"])
        let staged = try await SessionChanges.snapshot(first, scope: .uncommitted)
        #expect(staged.files.contains { $0.status == "Renamed" && $0.oldPath == "sample.txt" })
        try Data("unstaged\n".utf8).write(to: folder.appendingPathComponent("renamed.txt"))
        #expect(try await SessionChanges.snapshot(first, scope: .uncommitted).dirty)
        var missing = first; missing.cleaned = true
        await #expect(throws: (any Error).self) { try await SessionChanges.snapshot(missing, scope: .session) }
    }
    @Test func renameParsingAndRepositoryIdentity() throws {
        let files = SessionChanges.parseNames("R100\0old\tname\0new\nname\0D\0gone\0")
        #expect(files.count == 2)
        #expect(files[0].path == "new\nname")
        #expect(SessionChanges.parseStats("3\t2\t\0old\0new\0")["new"]?.0 == 3)
        #expect(GitHubRepository.parse("git@github.com:owner/repo.git")?.argument == "github.com/owner/repo")
        #expect(GitHubRepository.parse("https://github.com/owner/repo.git")?.name == "owner/repo")
        #expect(GitHubRepository.parse("/local/repo") == nil)
    }
    @Test func associationChecksAndCompatibility() throws {
        let json = #"{"number":42,"title":"Test","url":"https://github.com/upstream/repo/pull/42","state":"OPEN","isDraft":false,"headRefName":"feature","headRefOid":"abc","headRepository":{"name":"repo"},"headRepositoryOwner":{"login":"fork"},"statusCheckRollup":[{"name":"Tests","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/upstream/repo/actions/runs/1"}]}"#
        let pr = try JSONDecoder().decode(LinkedPullRequest.self, from: Data(json.utf8))
        #expect(pr.matches(head: try #require(GitHubRepository.parse("https://github.com/fork/repo")), branch: "feature"))
        #expect(!pr.matches(head: try #require(GitHubRepository.parse("https://github.com/other/repo")), branch: "feature"))
        #expect(pr.checkSummary == "1 check failed")
        #expect(pr.excludesLocalChanges(ChangesSnapshot(files: [], head: "different", branch: "feature", dirty: false)))
        var work = ProjectWorkspace(id: "a", folder: "/tmp/a", branch: "feature", baseCommit: "abc", context: ProjectContext())
        let old = try JSONEncoder().encode(work)
        #expect(try JSONDecoder().decode(ProjectWorkspace.self, from: old).pullRequest == nil)
        work.pullRequest = pr
        #expect(try JSONDecoder().decode(ProjectWorkspace.self, from: JSONEncoder().encode(work)).pullRequest == pr)
        for (raw, expected) in [("CANCELLED", "Cancelled"), ("SUCCESS", "Passed"), ("UNKNOWN", "Unavailable"), ("PENDING", "Running")] {
            let check = try JSONDecoder().decode(PRCheck.self, from: Data("{\"state\":\"\(raw)\"}".utf8))
            #expect(check.result == expected)
        }
    }
}

private actor PRCommandRecorder {
    var count = 0
    func response(_ args: [String]) async throws -> String {
        count += 1
        #expect(args.contains("feature"))
        try await Task.sleep(for: .milliseconds(50))
        return #"[{"number":1,"title":"Matching","url":"https://github.com/base/repo/pull/1","state":"OPEN","isDraft":false,"headRefName":"feature","headRefOid":"abc","headRepository":{"name":"repo"},"headRepositoryOwner":{"login":"fork"},"statusCheckRollup":[]},{"number":2,"title":"Unrelated fork","url":"https://github.com/base/repo/pull/2","state":"OPEN","isDraft":false,"headRefName":"feature","headRefOid":"abc","headRepository":{"name":"repo"},"headRepositoryOwner":{"login":"other"},"statusCheckRollup":[]}]"#
    }
}
extension SessionChangesTests {
    @Test func discoveryFiltersForksAndDeduplicates() async throws {
        let root = try await ProjectTests().repository(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await ProjectCommand.git(root.path, ["checkout", "-b", "feature"])
        _ = try await ProjectCommand.git(root.path, ["remote", "add", "origin", "https://github.com/fork/repo.git"])
        var initial = try await ProjectGit.discover(root.path); initial.remote = "https://github.com/base/repo.git"
        let project = initial
        let work = ProjectWorkspace(id: "x", folder: root.path, branch: "feature", baseCommit: "HEAD", context: ProjectContext())
        let recorder = PRCommandRecorder()
        let service = PullRequestService(command: { try await recorder.response($0) })
        async let a = service.discover(project: project, workspace: work)
        async let b = service.discover(project: project, workspace: work)
        let (first, second) = try await (a,b)
        #expect(first.count == 1 && first[0].number == 1)
        #expect(first == second)
        #expect(await recorder.count == 1)
        _ = try await service.discover(project: project, workspace: work)
        #expect(await recorder.count == 1)
        _ = try await service.discover(project: project, workspace: work, force: true)
        #expect(await recorder.count == 2)
        let failing = PullRequestService(command: { _ in throw AppServerFailure("Offline") })
        await #expect(throws: (any Error).self) { try await failing.discover(project: project, workspace: work) }
        #expect(try await SessionChanges.snapshot(work, scope: .uncommitted).files.isEmpty)
    }
    @Test func deletionLargeFileConflictAndExternalDiffDisabled() async throws {
        let root = try await ProjectTests().repository(); defer { try? FileManager.default.removeItem(at: root) }
        let base = try await ProjectCommand.git(root.path, ["rev-parse", "HEAD"])
        let work = ProjectWorkspace(id: "x", folder: root.path, branch: "main", baseCommit: base, context: ProjectContext())
        _ = try await ProjectCommand.git(root.path, ["config", "diff.external", "/nonexistent/do-not-run"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("sample.txt"))
        var snapshot = try await SessionChanges.snapshot(work, scope: .session)
        #expect(snapshot.files.first?.status == "Deleted")
        #expect(try await SessionChanges.diff(try #require(snapshot.files.first), workspace: work, scope: .session).contains("-original"))
        try Data(repeating: 65, count: 600_000).write(to: root.appendingPathComponent("large"))
        snapshot = try await SessionChanges.snapshot(work, scope: .session)
        let large = try #require(snapshot.files.first { $0.path == "large" })
        #expect(try await SessionChanges.diff(large, workspace: work, scope: .session).contains("too large"))
        _ = try await ProjectCommand.git(root.path, ["restore", "sample.txt"])
        _ = try await ProjectCommand.git(root.path, ["checkout", "-b", "other"])
        try Data("other\n".utf8).write(to: root.appendingPathComponent("sample.txt"))
        _ = try await ProjectCommand.git(root.path, ["commit", "-am", "Other"])
        _ = try await ProjectCommand.git(root.path, ["checkout", "main"])
        try Data("main\n".utf8).write(to: root.appendingPathComponent("sample.txt"))
        _ = try await ProjectCommand.git(root.path, ["commit", "-am", "Main"])
        _ = try? await ProjectCommand.git(root.path, ["merge", "other"])
        snapshot = try await SessionChanges.snapshot(work, scope: .session)
        #expect(snapshot.files.filter { $0.path == "sample.txt" }.count == 1)
        #expect(snapshot.files.first { $0.path == "sample.txt" }?.status == "Conflicted")
    }
}
