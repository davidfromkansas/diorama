import Foundation

/// Where an open pull request stands on its way to the base branch, from GitHub's merge test and
/// its checks. One place decides this, so the serving window, the kitchen and the service board agree.
public enum PRHealth: String, Codable, Sendable {
    /// Checks are running, or GitHub is still computing whether it merges.
    case checking
    /// Checks passed and it merges cleanly.
    case ready
    /// One or more checks failed.
    case checksFailed
    /// It conflicts with the base branch.
    case conflicted
    /// Branch protection wants it up to date with the base branch first.
    case behind
    /// GitHub blocks the merge for another reason (required review, draft).
    case blocked
    case merged
    case closed

    /// The agent should go back to work on it.
    public var needsFix: Bool { self == .checksFailed || self == .conflicted }
}

extension LinkedPullRequest {
    public var health: PRHealth {
        if state == "MERGED" { return .merged }
        if state != "OPEN" { return .closed }
        if mergeable == false || mergeableState == "dirty" { return .conflicted }
        if checks.contains(where: { $0.result == "Failed" }) { return .checksFailed }
        if checks.contains(where: { $0.result == "Running" }) || mergeable == nil || mergeableState == "unknown" { return .checking }
        if checks.isEmpty, let pushedAt, Date().timeIntervalSince(pushedAt) < Self.checkGrace { return .checking }
        if mergeableState == "behind" { return .behind }
        if isDraft || mergeableState == "blocked" || mergeableState == "draft" { return .blocked }
        return .ready
    }
    /// How long after a push a PR without any checks waits for CI to report.
    public static let checkGrace: TimeInterval = 120
    /// A refreshed copy keeps what only Diorama knows.
    public func carrying(from previous: LinkedPullRequest) -> LinkedPullRequest {
        var copy = self; copy.pushedAt = copy.pushedAt ?? previous.pushedAt; return copy
    }
    /// Checks that finished, for "3 of 5 done".
    public var finishedChecks: Int { checks.filter { $0.result != "Running" }.count }
    public var failedChecks: [PRCheck] { checks.filter { $0.result == "Failed" } }
}

/// Files that conflict between a task branch and the latest base, and the base commits that
/// touched them, worked out locally without changing the checkout.
public struct PRConflicts: Equatable, Sendable {
    public struct File: Equatable, Sendable, Identifiable {
        public var path: String
        /// Subjects of base commits that changed this file since the branch forked, newest first.
        public var changedBy: [String]
        public var id: String { path }
    }
    public var base: String
    public var files: [File]
}

public enum PullRequestRepair {
    /// Fetches the base branch so `origin/<base>` is current for every worktree of the repository.
    public static func fetchBase(worktree: String, base: String) async throws {
        _ = try await ProjectCommand.git(worktree, ["check-ref-format", "refs/heads/" + base])
        _ = try await GitHubGit.remote(worktree, arguments: ["fetch", "--no-tags", "origin", "+refs/heads/\(base):refs/remotes/origin/\(base)"])
    }

    /// Test-merges `origin/<base>` into the worktree's HEAD in memory (`git merge-tree`), so nothing
    /// in the checkout changes. Empty when it merges cleanly.
    public static func conflicts(worktree: String, base: String) async throws -> PRConflicts {
        let target = "refs/remotes/origin/" + base
        let (status, output) = try await gitStatus(worktree, ["merge-tree", "--write-tree", "--name-only", "--no-messages", target, "HEAD"])
        guard status == 1 else {
            if status == 0 { return PRConflicts(base: base, files: []) }
            throw AppServerFailure("Couldn't test the merge with \(base): \(output.prefix(300))")
        }
        // First line is the merged tree; the rest are conflicted paths.
        let paths = output.split(separator: "\n").dropFirst().map(String.init).filter { !$0.isEmpty }
        let fork = try await ProjectCommand.git(worktree, ["merge-base", "HEAD", target])
        var files: [PRConflicts.File] = []
        for path in Array(Set(paths)).sorted().prefix(20) {
            let log = (try? await ProjectCommand.git(worktree, ["log", "--format=%s", "-n", "3", fork + ".." + target, "--", path])) ?? ""
            files.append(.init(path: path, changedBy: log.split(separator: "\n").map(String.init)))
        }
        return PRConflicts(base: base, files: files)
    }

    /// Merges `origin/<base>` into the worktree's branch. A clean merge commits; a conflicting one
    /// is left in progress with conflict markers for the agent to resolve. Returns the conflicted paths.
    public static func mergeBase(worktree: String, base: String, identity: [String: String]? = nil) async throws -> [String] {
        guard try await ProjectCommand.git(worktree, ["status", "--porcelain"]).isEmpty else {
            throw AppServerFailure("This task has uncommitted changes. Commit them before bringing in \(base).")
        }
        var env: [String: String] = [:]
        if let identity { env = identity } else { env = await identityEnvironment() }
        do {
            _ = try await ProjectCommand.data("/usr/bin/git", ["-C", worktree, "merge", "--no-edit", "refs/remotes/origin/" + base], environmentOverrides: env)
            return []
        } catch {
            let conflicted = try await ProjectCommand.git(worktree, ["diff", "--name-only", "--diff-filter=U"])
            guard !conflicted.isEmpty else {
                _ = try? await ProjectCommand.git(worktree, ["merge", "--abort"])
                throw error
            }
            return conflicted.split(separator: "\n").map(String.init)
        }
    }

    /// After the agent's fix: refuses leftover conflict markers, commits whatever the agent left
    /// (concluding an in-progress merge), and pushes the branch to the pull request without forcing.
    public static func pushFollowUp(worktree: String, pullRequest: LinkedPullRequest, message: String, mergedFiles: [String] = [],
                                    isActive: @escaping @Sendable (String) async -> Bool) async throws -> LinkedPullRequest {
        try await GitHubCheckoutLocks.shared.acquire(worktree)
        do {
            guard !(await isActive(worktree)) else { throw AppServerFailure("The agent is still working in this checkout. Push after it finishes.") }
            let branch = await ProjectGit.currentBranch(worktree)
            guard branch == pullRequest.headRefName else {
                throw AppServerFailure("This checkout is on \(branch), not \(pullRequest.headRefName). Switch back before pushing.")
            }
            let unresolved = try await ProjectCommand.git(worktree, ["diff", "--name-only", "--diff-filter=U"])
            var marked: [String] = unresolved.isEmpty ? [] : unresolved.split(separator: "\n").map(String.init)
            for path in mergedFiles where !marked.contains(path) {
                let url = URL(fileURLWithPath: worktree).appendingPathComponent(path)
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   text.split(separator: "\n", omittingEmptySubsequences: false).contains(where: { $0.hasPrefix("<<<<<<< ") || $0.hasPrefix(">>>>>>> ") }) {
                    marked.append(path)
                }
            }
            guard marked.isEmpty else { throw AppServerFailure("Conflict markers remain in \(marked.joined(separator: ", ")). Send it back to the agent.") }
            let dirty = try await !ProjectCommand.git(worktree, ["status", "--porcelain"]).isEmpty
            let merging = (try? await ProjectCommand.git(worktree, ["rev-parse", "-q", "--verify", "MERGE_HEAD"])).map { !$0.isEmpty } ?? false
            if dirty || merging {
                let env = await identityEnvironment()
                _ = try await ProjectCommand.git(worktree, ["add", "-A"])
                let subject = message.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await ProjectCommand.data("/usr/bin/git", ["-C", worktree, "commit", "-m", subject.isEmpty ? "Address review feedback" : subject], environmentOverrides: env)
            }
            _ = try await GitHubGit.remote(worktree, arguments: ["push", "origin", "HEAD:refs/heads/" + pullRequest.headRefName])
            await GitHubCheckoutLocks.shared.release(worktree)
        } catch { await GitHubCheckoutLocks.shared.release(worktree); throw error }
        var fresh = try await GitHubPullRequests.get(pullRequest.url)
        fresh.pushedAt = Date()
        return fresh
    }

    /// What the agent is told to do: the conflicting files and what changed them on the base, and
    /// the failing checks with their links.
    public static func fixPrompt(_ pr: LinkedPullRequest, conflicts: PRConflicts?, mergeStarted: Bool) -> String {
        var lines: [String] = []
        if let conflicts, !conflicts.files.isEmpty {
            if mergeStarted {
                lines.append("Pull request #\(pr.number) conflicts with \(conflicts.base). Diorama has started merging origin/\(conflicts.base) into this branch; the files below have conflict markers.")
                lines.append("Resolve every conflict, keeping the intent of both sides. Don't rebase, reset, abort the merge, or push: when you finish, Diorama commits the merge and pushes it to the PR.")
            } else {
                lines.append("Pull request #\(pr.number) conflicts with \(conflicts.base). Merge origin/\(conflicts.base) into this branch and resolve the conflicts, keeping the intent of both sides. Don't rebase or push.")
            }
            lines.append("")
            for file in conflicts.files {
                lines.append("- \(file.path)" + (file.changedBy.isEmpty ? "" : " (on \(conflicts.base): \(file.changedBy.joined(separator: "; ")))"))
            }
        }
        let failed = pr.failedChecks
        if !failed.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("These CI checks failed on #\(pr.number). Find the cause, fix it, and run the same checks locally:")
            for check in failed.prefix(8) { lines.append("- \(check.title): \(check.url ?? "no link")") }
        }
        if lines.isEmpty { lines.append("Bring pull request #\(pr.number) up to date and make sure its checks pass.") }
        lines.append("")
        lines.append("Run the project's tests before you finish.")
        return lines.joined(separator: "\n")
    }

    /// Commits made on the user's behalf use their GitHub no-reply identity when connected.
    static func identityEnvironment() async -> [String: String] {
        guard let identity = try? await GitHubAccount.shared.identity() else { return [:] }
        let email = "\(identity.id)+\(identity.login)@users.noreply.github.com"
        return ["GIT_AUTHOR_NAME": identity.login, "GIT_AUTHOR_EMAIL": email, "GIT_COMMITTER_NAME": identity.login, "GIT_COMMITTER_EMAIL": email]
    }
}

/// Runs git and returns its exit status with its output, for commands whose status is the answer
/// (`merge-tree` exits 1 on a conflict).
private func gitStatus(_ folder: String, _ arguments: [String]) async throws -> (Int32, String) {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"; environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            continuation.resume(returning: (finished.terminationStatus, String(decoding: data, as: UTF8.self)))
        }
        do { try process.run() } catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
    }
}
