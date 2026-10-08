import DioramaCore
import Foundation
import Observation

/// Keeps every task's open pull request current while Diorama runs: CI results and GitHub's merge
/// test move the chef (tasting while checks run, the bell on a conflict or failed check, the pass
/// when it's green, the break room once merged, including merges made on GitHub). When a fix you
/// sent back finishes, it pushes the result to the same pull request.
@Observable @MainActor final class PRWatcher {
    static let shared = PRWatcher()
    /// Conversations whose fix is being pushed right now.
    private(set) var pushing = Set<String>()
    /// The last failed follow-up push or refresh, by conversation.
    private(set) var errors: [String: String] = [:]
    @ObservationIgnored private var refreshed: [String: Date] = [:]
    @ObservationIgnored private var running = false

    /// Polls until cancelled. Faster while checks run.
    func run(library: LibraryModel) async {
        guard !running else { return }
        running = true; defer { running = false }
        while !Task.isCancelled {
            await tick(library)
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
        }
    }

    /// Refreshes one pull request on the next pass, whatever its interval.
    func refreshSoon(_ url: String) { refreshed[url] = nil }

    func tick(_ library: LibraryModel) async {
        let reviews = KitchenReviews.shared
        for project in library.projects.projects {
            for workspace in project.workspaces where !workspace.archived {
                guard let pr = workspace.pullRequest, let thread = workspace.threadID,
                      let session = library.sessions.first(where: { $0.sessionID == thread }) else { continue }
                let conversation = session.id
                if let fix = reviews.fixes[conversation], fix.pullRequest == pr.url {
                    await finishFix(fix, pr: pr, conversation: conversation, thread: thread, project: project, workspace: workspace, library: library)
                    continue
                }
                guard pr.state == "OPEN" || ![.merged, .approved].contains(reviews.state(conversation) ?? .approved) else { continue }
                let interval: TimeInterval = reviews.state(conversation) == .checking ? 20 : 60
                if let last = refreshed[pr.url], Date().timeIntervalSince(last) < interval { continue }
                refreshed[pr.url] = Date()
                do {
                    let fresh = try await GitHubPullRequests.get(pr.url).carrying(from: pr)
                    errors[conversation] = nil
                    if fresh != pr { library.projects.updateWorkspace(project.id, id: workspace.id) { $0.pullRequest = fresh } }
                    Self.apply(fresh, conversation: conversation, reviews: reviews)
                } catch {
                    errors[conversation] = error.localizedDescription
                }
            }
        }
    }

    /// Moves a conversation's review to match its pull request. Leaves it alone while the agent
    /// works or while newer work waits for your review.
    static func apply(_ pr: LinkedPullRequest, conversation: String, reviews: KitchenReviews) {
        guard let state = reviews.state(conversation) else { return }
        let health = pr.health
        if health == .merged, state != .merged { reviews.set(conversation, .merged, note: "Merged #\(pr.number)"); return }
        guard [.shipped, .checking, .needsFix, .committed].contains(state) else { return }
        let next = Self.review(for: pr)
        reviews.set(conversation, next.state, note: next.note)
    }

    static func review(for pr: LinkedPullRequest) -> (state: KitchenReviews.State, note: String) {
        let base = pr.baseRefName ?? "base"
        switch pr.health {
        case .checking: return (.checking, pr.checks.isEmpty ? "PR #\(pr.number) · waiting for checks" : "PR #\(pr.number) · \(pr.finishedChecks) of \(pr.checks.count) checks done")
        case .ready: return (.shipped, "Ready to merge")
        case .behind: return (.shipped, "Behind \(base)")
        case .blocked: return (.shipped, pr.isDraft ? "Draft PR" : "Waiting on review")
        case .checksFailed: return (.needsFix, "Needs a fix · " + ListFormatter.localizedString(byJoining: pr.failedChecks.map(\.title)) + " failed")
        case .conflicted: return (.needsFix, "Needs a fix · conflicts with \(base)")
        case .merged: return (.merged, "Merged #\(pr.number)")
        case .closed: return (.approved, "PR closed")
        }
    }

    /// A fix you sent back: once the agent's turn has finished, push what it did to the PR.
    private func finishFix(_ fix: KitchenReviews.Fix, pr: LinkedPullRequest, conversation: String, thread: String,
                           project: DioramaProject, workspace: ProjectWorkspace, library: LibraryModel) async {
        let reviews = KitchenReviews.shared
        guard !pushing.contains(conversation), Date().timeIntervalSince(fix.sent) > 8 else { return }
        if let task = library.execution.tasks[thread] {
            if task.busy || library.execution.requests.values.contains(where: { $0.threadID == thread }) { return }
            if task.phase == .failed || task.phase == .interrupted {
                reviews.setFix(conversation, nil)
                reviews.set(conversation, .needsFix, note: "The fix stopped before finishing")
                return
            }
        } else if reviews.state(conversation) == nil || reviews.state(conversation) == .reworking {
            return
        }
        pushing.insert(conversation); defer { pushing.remove(conversation) }
        do {
            let execution = library.execution
            let fresh = try await PullRequestRepair.pushFollowUp(worktree: workspace.folder, pullRequest: pr,
                message: fix.mergedFiles.isEmpty ? "Fix failing checks" : "Merge \(pr.baseRefName ?? "base") and resolve conflicts",
                mergedFiles: fix.mergedFiles) { folder in
                await MainActor.run { execution.tasks.values.contains { $0.busy && $0.folder == folder } }
            }
            reviews.setFix(conversation, nil)
            errors[conversation] = nil
            library.projects.updateWorkspace(project.id, id: workspace.id) { $0.pullRequest = fresh }
            refreshed[pr.url] = Date()
            // The pushed commit is new: CI starts over, whatever GitHub reported a moment ago.
            reviews.set(conversation, .checking, note: "PR #\(pr.number) · fix pushed, waiting for checks")
        } catch {
            reviews.setFix(conversation, nil)
            errors[conversation] = error.localizedDescription
            reviews.set(conversation, .needsFix, note: "Couldn't push the fix")
        }
    }

    /// Merges every green pull request among these tasks, one at a time: each merge can put the
    /// next one behind or in conflict, so each is re-read and merged only while still green.
    /// Returns a one-line summary.
    func mergeAllGreen(_ items: [AgentSidebarItem], library: LibraryModel) async -> String {
        let reviews = KitchenReviews.shared
        var merged: [Int] = [], skipped: [String] = []
        for item in items {
            guard let pr = item.pullRequest, pr.health == .ready else { continue }
            do {
                let current = try await GitHubPullRequests.get(pr.url)
                guard current.health == .ready else {
                    skipped.append("#\(pr.number) \(PRHealthStyle.pill(current))")
                    Self.apply(current, conversation: item.conversationID, reviews: reviews)
                    continue
                }
                try await ServingWindowGit.mergeOnGitHub(current, method: .squash)
                let after = try await GitHubPullRequests.confirmMerged(pr.url, merged: true)
                if let project = library.projects.projects.first(where: { $0.workspaces.contains { $0.pullRequest?.url == pr.url } }),
                   let workspace = project.workspaces.first(where: { $0.pullRequest?.url == pr.url }) {
                    library.projects.updateWorkspace(project.id, id: workspace.id) { $0.pullRequest = after }
                    let execution = library.execution
                    try? await GitHubBranchUpdate.update(projectFolder: project.folder, pullRequest: after) { folder in
                        await MainActor.run { execution.tasks.values.contains { $0.phase.active && $0.folder == folder } }
                    }
                }
                reviews.set(item.conversationID, .merged, note: "Merged #\(pr.number)")
                merged.append(pr.number)
            } catch {
                skipped.append("#\(pr.number): \(error.localizedDescription)")
            }
        }
        // Every other open PR's base just moved: look again soon.
        refreshed.removeAll()
        var parts: [String] = []
        if !merged.isEmpty { parts.append("Merged " + merged.map { "#\($0)" }.joined(separator: ", ")) }
        if !skipped.isEmpty { parts.append("Skipped " + skipped.joined(separator: "; ")) }
        return parts.isEmpty ? "Nothing was ready to merge." : parts.joined(separator: ". ")
    }
}
