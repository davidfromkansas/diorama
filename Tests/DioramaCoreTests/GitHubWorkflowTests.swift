import Foundation
import Testing
@testable import DioramaCore

struct GitHubWorkflowTests {
    @Test func newPublishedProjectsUsePrivateGitHubAuthor() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-author-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await ProjectGit.initialize(folder.path, githubIdentity: GitHubIdentity(login: "fixture", id: 42))
        #expect(try await ProjectCommand.git(folder.path, ["log", "-1", "--format=%ae"]) == "42+fixture@users.noreply.github.com")
        await #expect(throws: (any Error).self) { try await ProjectCommand.git(folder.path, ["config", "--local", "--get", "user.email"]) }
    }
    @Test func selectedCommitPreservesOtherStagedContent() async throws {
        let folder = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("staged".utf8).write(to: folder.appendingPathComponent("unrelated.txt"))
        _ = try await ProjectCommand.git(folder.path, ["add", "unrelated.txt"])
        try Data("working copy".utf8).write(to: folder.appendingPathComponent("unrelated.txt"))
        try Data("selected".utf8).write(to: folder.appendingPathComponent("new file.txt"))
        let staged = try await ProjectCommand.git(folder.path, ["show", ":unrelated.txt"])
        let service = GitHubPRSubmission(storage: folder.appendingPathComponent("journal"))
        let tree = try await service.selectedTree(folder: folder.path, paths: ["new file.txt"])
        try await service.commitSelected(folder: folder.path, paths: ["new file.txt"], title: "Selected file", expectedTree: tree)
        #expect(try await ProjectCommand.git(folder.path, ["show", "HEAD:new file.txt"]) == "selected")
        #expect(try await ProjectCommand.git(folder.path, ["show", ":unrelated.txt"]) == staged)
        #expect(try String(contentsOf: folder.appendingPathComponent("unrelated.txt"), encoding: .utf8) == "working copy")
        await #expect(throws: (any Error).self) { try await ProjectCommand.git(folder.path, ["show", "HEAD:unrelated.txt"]) }
    }
    @Test func staleSelectedTreeBlocksCommit() async throws {
        let folder = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = GitHubPRSubmission()
        try Data("previewed".utf8).write(to: folder.appendingPathComponent("sample.txt"))
        let original = try await ProjectCommand.git(folder.path, ["rev-parse", "HEAD"])
        let tree = try await service.selectedTree(folder: folder.path, paths: ["sample.txt"])
        let fingerprint = try await GitHubPRSubmission.fingerprint(folder.path)
        try Data("changed after preview".utf8).write(to: folder.appendingPathComponent("sample.txt"))
        #expect(try await GitHubPRSubmission.fingerprint(folder.path) != fingerprint)
        await #expect(throws: (any Error).self) { try await service.commitSelected(folder: folder.path, paths: ["sample.txt"], title: "Should fail", expectedTree: tree) }
        #expect(try await ProjectCommand.git(folder.path, ["rev-parse", "HEAD"]) == original)
    }
    @Test func selectedDeletionAndRename() async throws {
        let folder = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.moveItem(at: folder.appendingPathComponent("sample.txt"), to: folder.appendingPathComponent("renamed.txt"))
        let service = GitHubPRSubmission()
        let paths = ["sample.txt", "renamed.txt"]
        let tree = try await service.selectedTree(folder: folder.path, paths: paths)
        try await service.commitSelected(folder: folder.path, paths: paths, title: "Rename", expectedTree: tree)
        #expect(try await ProjectCommand.git(folder.path, ["show", "HEAD:renamed.txt"]) == "original")
        await #expect(throws: (any Error).self) { try await ProjectCommand.git(folder.path, ["show", "HEAD:sample.txt"]) }
    }
    @Test func malformedAndUntrustedDestinations() throws {
        for value in ["https://github.com.evil.test/a/b", "https://user:secret@github.com/a/b", "http://github.com/a/b", "https://github.com/a/b?token=secret", "file:///tmp/repo"] {
            #expect(throws: (any Error).self) { try GitHubGit.https(value) }
        }
        #expect(try GitHubGit.https("git@github.com:owner/repo.git").url == "https://github.com/owner/repo.git")
        #expect(throws: (any Error).self) { try GitHubAccount.validRepository("owner/../repo") }
        #expect(throws: (any Error).self) { try GitHubPullRequests.identity("https://example.com/a/b/pull/1") }
    }
    @Test func mergedPRSurvivesDeletedHeadRepository() throws {
        let data = Data(#"{"number":7,"title":"Test","html_url":"https://github.com/a/b/pull/7","state":"closed","draft":false,"merged_at":"2026-09-25T10:00:00Z","merge_commit_sha":"merge","head":{"ref":"feature","sha":"head","repo":null},"base":{"ref":"trunk"}}"#.utf8)
        let pr = try GitHubPullRequests.decode(data)
        #expect(pr.state == "MERGED")
        #expect(pr.baseRefName == "trunk")
        #expect(pr.headRepository == nil)
        #expect(pr.mergeCommit == "merge")
    }
    @Test func locksCanonicalizeFolderAndRelease() async throws {
        let folder = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: folder) }
        let locks = GitHubCheckoutLocks()
        try await locks.acquire(folder.path)
        await #expect(throws: (any Error).self) { try await locks.acquire(folder.appendingPathComponent(".").path) }
        await locks.release(folder.path)
        try await locks.acquire(folder.path)
        await locks.release(folder.path)
    }
}
