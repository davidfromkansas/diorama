import Foundation
import Testing
@testable import DioramaCore

struct PullRequestHealthTests {
    private func pr(state: String = "OPEN", mergeable: Bool? = true, mergeableState: String? = "clean", checks: [PRCheck]? = [], draft: Bool = false) -> LinkedPullRequest {
        var pr = LinkedPullRequest(number: 42, title: "Add OAuth refresh", url: "https://github.com/acme/store/pull/42", state: state,
                                   isDraft: draft, headRefName: "add-oauth-refresh", headRefOid: "abc", statusCheckRollup: checks)
        pr.baseRefName = "main"; pr.mergeable = mergeable; pr.mergeableState = mergeableState
        return pr
    }
    private let passed = PRCheck(name: "build", status: "COMPLETED", conclusion: "SUCCESS")
    private let failed = PRCheck(name: "test", status: "COMPLETED", conclusion: "FAILURE", detailsUrl: "https://github.com/acme/store/actions/runs/1/job/2")
    private let running = PRCheck(name: "lint", status: "IN_PROGRESS")

    @Test func healthFollowsChecksAndGitHubsMergeTest() {
        #expect(pr(checks: [passed]).health == .ready)
        #expect(pr(checks: [passed, running]).health == .checking)
        #expect(pr(mergeable: nil, mergeableState: "unknown", checks: [passed]).health == .checking)
        #expect(pr(checks: [passed, failed, running]).health == .checksFailed)
        // A conflict outranks everything else that's open.
        #expect(pr(mergeable: false, mergeableState: "dirty", checks: [failed]).health == .conflicted)
        #expect(pr(mergeableState: "behind", checks: [passed]).health == .behind)
        #expect(pr(mergeableState: "blocked", checks: [passed]).health == .blocked)
        #expect(pr(mergeableState: "draft", checks: [passed], draft: true).health == .blocked)
        #expect(pr(state: "MERGED", mergeable: nil).health == .merged)
        #expect(pr(state: "CLOSED").health == .closed)
        #expect(PRHealth.conflicted.needsFix && PRHealth.checksFailed.needsFix && !PRHealth.behind.needsFix)
        #expect(pr(checks: [passed, failed, running]).finishedChecks == 2)
        // Right after a push, no checks means CI hasn't reported yet; later it means there's no CI.
        var fresh = pr(checks: []); fresh.pushedAt = Date()
        #expect(fresh.health == .checking)
        fresh.pushedAt = Date().addingTimeInterval(-LinkedPullRequest.checkGrace - 1)
        #expect(fresh.health == .ready)
        var refreshed = pr(checks: []); refreshed = refreshed.carrying(from: fresh)
        #expect(refreshed.pushedAt == fresh.pushedAt)
    }

    @Test func decodesGitHubsMergeability() throws {
        let json = #"{"number":7,"html_url":"https://github.com/a/b/pull/7","title":"T","state":"open","draft":false,"head":{"ref":"x","sha":"s"},"base":{"ref":"main"},"mergeable":false,"mergeable_state":"dirty"}"#
        let decoded = try GitHubPullRequests.decode(Data(json.utf8))
        #expect(decoded.mergeable == false && decoded.mergeableState == "dirty" && decoded.health == .conflicted)
        let pending = try GitHubPullRequests.decode(Data(json.replacingOccurrences(of: #""mergeable":false"#, with: #""mergeable":null"#).utf8))
        #expect(pending.mergeable == nil)
    }

    @Test func mergingRefusesUnlessGreen() async {
        await #expect(throws: (any Error).self) { try await ServingWindowGit.mergeOnGitHub(pr(checks: [failed])) }
        await #expect(throws: (any Error).self) { try await ServingWindowGit.mergeOnGitHub(pr(checks: [running])) }
        await #expect(throws: (any Error).self) { try await ServingWindowGit.mergeOnGitHub(pr(mergeable: false, mergeableState: "dirty")) }
    }

    @Test func fixPromptNamesConflictsAndFailedChecks() {
        let conflicts = PRConflicts(base: "main", files: [.init(path: "Sources/Client.swift", changedBy: ["Retry policy (#39)"])])
        let text = PullRequestRepair.fixPrompt(pr(mergeable: false, mergeableState: "dirty", checks: [failed]), conflicts: conflicts, mergeStarted: true)
        #expect(text.contains("Sources/Client.swift") && text.contains("Retry policy (#39)"))
        #expect(text.contains("Don't rebase") && text.contains("Diorama commits the merge"))
        #expect(text.contains("test: https://github.com/acme/store/actions/runs/1/job/2"))
        let checksOnly = PullRequestRepair.fixPrompt(pr(checks: [failed]), conflicts: nil, mergeStarted: false)
        #expect(!checksOnly.contains("conflicts") && checksOnly.contains("CI checks failed"))
    }

    /// A task branch and a base that both changed `a.txt`, with `origin/main` pointing at the base.
    private func diverged(conflicting: Bool) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-health-" + UUID().uuidString)
        let main = root.appendingPathComponent("main").path, worktree = root.appendingPathComponent("task").path
        try FileManager.default.createDirectory(atPath: main, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.email", "test@example.com"], ["config", "user.name", "Test"]] {
            _ = try await ProjectCommand.git(main, args)
        }
        try "one\ntwo\nthree\n".write(toFile: main + "/a.txt", atomically: true, encoding: .utf8)
        _ = try await ProjectCommand.git(main, ["add", "-A"]); _ = try await ProjectCommand.git(main, ["commit", "-qm", "start"])
        _ = try await ProjectCommand.git(main, ["worktree", "add", "-q", "-b", "task-branch", worktree])
        try "one\nTASK\nthree\n".write(toFile: worktree + "/a.txt", atomically: true, encoding: .utf8)
        _ = try await ProjectCommand.git(worktree, ["commit", "-qam", "Task edit"])
        if conflicting { try "one\nBASE\nthree\n".write(toFile: main + "/a.txt", atomically: true, encoding: .utf8) }
        else { try "base\n".write(toFile: main + "/b.txt", atomically: true, encoding: .utf8) }
        _ = try await ProjectCommand.git(main, ["add", "-A"]); _ = try await ProjectCommand.git(main, ["commit", "-qm", "Retry policy (#39)"])
        _ = try await ProjectCommand.git(main, ["update-ref", "refs/remotes/origin/main", "main"])
        return worktree
    }

    @Test func findsConflictingFilesAndWhatChangedThem() async throws {
        let worktree = try await diverged(conflicting: true)
        let head = try await ProjectCommand.git(worktree, ["rev-parse", "HEAD"])
        let found = try await PullRequestRepair.conflicts(worktree: worktree, base: "main")
        #expect(found.files.map(\.path) == ["a.txt"])
        #expect(found.files.first?.changedBy == ["Retry policy (#39)"])
        // Testing the merge changes nothing.
        #expect(try await ProjectCommand.git(worktree, ["rev-parse", "HEAD"]) == head)
        #expect(try await ProjectCommand.git(worktree, ["status", "--porcelain"]).isEmpty)
        let clean = try await diverged(conflicting: false)
        #expect(try await PullRequestRepair.conflicts(worktree: clean, base: "main").files.isEmpty)
    }

    @Test func mergingTheBaseLeavesConflictsForTheAgentOrCommitsCleanly() async throws {
        let worktree = try await diverged(conflicting: true)
        #expect(try await PullRequestRepair.mergeBase(worktree: worktree, base: "main", identity: [:]) == ["a.txt"])
        let text = try String(contentsOfFile: worktree + "/a.txt", encoding: .utf8)
        #expect(text.contains("<<<<<<< ") && text.contains("BASE") && text.contains("TASK"))
        let clean = try await diverged(conflicting: false)
        #expect(try await PullRequestRepair.mergeBase(worktree: clean, base: "main", identity: [:]).isEmpty)
        #expect(FileManager.default.fileExists(atPath: clean + "/b.txt"))
        #expect(try await ProjectCommand.git(clean, ["status", "--porcelain"]).isEmpty)
    }
}
