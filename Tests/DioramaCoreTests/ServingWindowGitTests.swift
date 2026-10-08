import Foundation
import Testing
@testable import DioramaCore

struct ServingWindowGitTests {
    private func repository() async throws -> (main: String, worktree: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("serving-" + UUID().uuidString)
        let main = root.appendingPathComponent("main").path, worktree = root.appendingPathComponent("task").path
        try FileManager.default.createDirectory(atPath: main, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.email", "test@example.com"], ["config", "user.name", "Test"]] {
            _ = try await ProjectCommand.git(main, args)
        }
        try "one\n".write(toFile: main + "/a.txt", atomically: true, encoding: .utf8)
        _ = try await ProjectCommand.git(main, ["add", "-A"]); _ = try await ProjectCommand.git(main, ["commit", "-qm", "start"])
        _ = try await ProjectCommand.git(main, ["worktree", "add", "-q", "-b", "task-branch", worktree])
        return (main, worktree)
    }

    @Test func commitThenMergeLocallyBringsTheTaskIntoBase() async throws {
        let repo = try await repository()
        try "two\n".write(toFile: repo.worktree + "/b.txt", atomically: true, encoding: .utf8)
        #expect(try await ServingWindowGit.hasUncommittedChanges(worktree: repo.worktree))
        // Merging uncommitted work is refused.
        await #expect(throws: (any Error).self) {
            try await ServingWindowGit.mergeLocally(projectFolder: repo.main, base: "main", branch: "task-branch", worktree: repo.worktree)
        }
        let sha = try await ServingWindowGit.commitAll(worktree: repo.worktree, message: "Add b")
        #expect(!sha.isEmpty)
        #expect(try await !ServingWindowGit.hasUncommittedChanges(worktree: repo.worktree))
        await #expect(throws: (any Error).self) { _ = try await ServingWindowGit.commitAll(worktree: repo.worktree, message: "again") }
        try await ServingWindowGit.mergeLocally(projectFolder: repo.main, base: "main", branch: "task-branch", worktree: repo.worktree)
        #expect(FileManager.default.fileExists(atPath: repo.main + "/b.txt"))
        let log = try await ProjectCommand.git(repo.main, ["log", "--oneline", "-1"])
        #expect(log.contains("Merge branch 'task-branch'"))
    }

    @Test func localMergeRequiresTheBaseCheckoutAndAbortsConflicts() async throws {
        let repo = try await repository()
        _ = try await ProjectCommand.git(repo.main, ["checkout", "-q", "-b", "elsewhere"])
        try "two\n".write(toFile: repo.worktree + "/a.txt", atomically: true, encoding: .utf8)
        _ = try await ServingWindowGit.commitAll(worktree: repo.worktree, message: "Change a")
        await #expect(throws: (any Error).self) {
            try await ServingWindowGit.mergeLocally(projectFolder: repo.main, base: "main", branch: "task-branch", worktree: repo.worktree)
        }
        _ = try await ProjectCommand.git(repo.main, ["checkout", "-q", "main"])
        try "conflict\n".write(toFile: repo.main + "/a.txt", atomically: true, encoding: .utf8)
        _ = try await ProjectCommand.git(repo.main, ["commit", "-qam", "Diverge"])
        await #expect(throws: (any Error).self) {
            try await ServingWindowGit.mergeLocally(projectFolder: repo.main, base: "main", branch: "task-branch", worktree: repo.worktree)
        }
        // The failed merge was undone: the base checkout is clean and unchanged.
        #expect(try await ProjectCommand.git(repo.main, ["status", "--porcelain"]).isEmpty)
        #expect(try String(contentsOfFile: repo.main + "/a.txt", encoding: .utf8) == "conflict\n")
    }
}
