import Foundation

/// Git steps behind the kitchen's serving window: commit a task's worktree locally, merge its
/// branch into the project's base checkout, or merge its pull request on GitHub. Arguments are
/// always passed as arrays (never through a shell); nothing is forced, reset or deleted.
public enum ServingWindowGit {
    /// Stages everything in the task's worktree and commits it. Returns the short commit id.
    public static func commitAll(worktree: String, message: String) async throws -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppServerFailure("Write a commit message first.") }
        guard try await !ProjectCommand.git(worktree, ["status", "--porcelain"]).isEmpty else {
            throw AppServerFailure("There is nothing new to commit.")
        }
        _ = try await ProjectCommand.git(worktree, ["add", "-A"])
        _ = try await ProjectCommand.git(worktree, ["commit", "-m", text])
        return try await ProjectCommand.git(worktree, ["rev-parse", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the worktree has uncommitted changes.
    public static func hasUncommittedChanges(worktree: String) async throws -> Bool {
        try await !ProjectCommand.git(worktree, ["status", "--porcelain"]).isEmpty
    }

    /// Merges the task branch into the base branch checked out in the project folder. Requires
    /// both checkouts to be clean and the project folder to be on the base branch; a conflicting
    /// merge is aborted, leaving everything as it was.
    public static func mergeLocally(projectFolder: String, base: String, branch: String, worktree: String) async throws {
        guard try await !hasUncommittedChanges(worktree: worktree) else { throw AppServerFailure("Commit the changes before merging.") }
        let current = try await ProjectCommand.git(projectFolder, ["symbolic-ref", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard current == base else { throw AppServerFailure("Check out \(base) in \(projectFolder) to merge locally (it is on \(current)).") }
        guard try await ProjectCommand.git(projectFolder, ["status", "--porcelain"]).isEmpty else {
            throw AppServerFailure("\(base) has uncommitted changes in \(projectFolder). Commit or stash them first.")
        }
        do {
            _ = try await ProjectCommand.git(projectFolder, ["merge", "--no-ff", "--no-edit", branch])
        } catch {
            _ = try? await ProjectCommand.git(projectFolder, ["merge", "--abort"])
            throw AppServerFailure("The merge stopped on a conflict and was undone. Ask the agent to rebase on \(base). (\(error.localizedDescription))")
        }
    }

    /// Merges an open pull request on GitHub (merge commit). Requires a connected GitHub account.
    public static func mergeOnGitHub(_ pullRequest: LinkedPullRequest) async throws {
        let target = try GitHubPullRequests.identity(pullRequest.url)
        _ = try await GitHubAccount.shared.api("/repos/\(target.repository)/pulls/\(target.number)/merge", method: "PUT",
                                               body: .object(["merge_method": .string("merge")]))
    }
}
