import Foundation

public enum GitHubBranchUpdate {
    public static func update(projectFolder: String, pullRequest: LinkedPullRequest,
                              isActive: @escaping @Sendable (String) async -> Bool) async throws {
        let pr = try await GitHubPullRequests.get(pullRequest.url)
        guard pr.state == "MERGED", let base = pr.baseRefName else { throw AppServerFailure("GitHub has not confirmed this PR was merged.") }
        _ = try await ProjectCommand.git(projectFolder, ["check-ref-format", "refs/heads/" + base])
        let identity = try GitHubPullRequests.identity(pr.url)
        let remote = try GitHubGit.https(await ProjectCommand.git(projectFolder, ["remote", "get-url", "origin"]))
        guard remote.name.lowercased() == identity.repository.lowercased() else { throw AppServerFailure("The PR destination differs from this project's remote. It was not changed.") }
        let worktrees = try await ProjectCommand.git(projectFolder, ["worktree", "list", "--porcelain"])
        let checkout = worktrees.components(separatedBy: "\n\n").first { $0.components(separatedBy: "\n").contains("branch refs/heads/" + base) }?
            .components(separatedBy: "\n").first { $0.hasPrefix("worktree ") }.map { String($0.dropFirst(9)) }
        let folder = checkout ?? projectFolder
        try await GitHubCheckoutLocks.shared.acquire(folder)
        do {
            try await safe(folder: folder, checkout: checkout, isActive: isActive)
            _ = try await GitHubGit.remote(projectFolder, arguments: ["fetch", "--no-tags", "origin", "refs/heads/" + base])
            let commit = try await ProjectCommand.git(projectFolder, ["rev-parse", "--verify", "FETCH_HEAD^{commit}"])
            try await safe(folder: folder, checkout: checkout, isActive: isActive)
            if let checkout {
                guard await ProjectGit.currentBranch(checkout) == base else { throw AppServerFailure("The checkout changed branches. Retry after reviewing it.") }
                _ = try await ProjectCommand.git(checkout, ["merge", "--ff-only", commit])
            } else {
                let ref = "refs/heads/" + base
                let prior = try? await ProjectCommand.git(projectFolder, ["rev-parse", "--verify", ref])
                if let prior {
                    do { _ = try await ProjectCommand.git(projectFolder, ["merge-base", "--is-ancestor", prior, commit]) }
                    catch { throw AppServerFailure("Local \(base) has different commits. Resolve the branches manually; Diorama will not reset local history.") }
                }
                _ = try await ProjectCommand.git(projectFolder, ["update-ref", ref, commit, prior ?? ""])
            }
            await GitHubCheckoutLocks.shared.release(folder)
        } catch { await GitHubCheckoutLocks.shared.release(folder); throw error }
    }
    private static func safe(folder: String, checkout: String?, isActive: @Sendable (String) async -> Bool) async throws {
        guard !(await isActive(folder)) else { throw AppServerFailure("Active Diorama work uses this checkout. Wait until it finishes.") }
        if let checkout {
            guard try await ProjectCommand.git(checkout, ["status", "--porcelain", "--untracked-files=all"]).isEmpty else {
                throw AppServerFailure("This checkout has local edits. Commit or move them before updating the branch.")
            }
        }
    }
}
