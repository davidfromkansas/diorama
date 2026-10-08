import Foundation
import CryptoKit

public struct GitHubPRPreview: Sendable {
    public var repository: GitHubRepo
    public var workspace: ProjectWorkspace
    public var base: String
    public var source: String
    public var createsBranch: Bool
    public var snapshot: ChangesSnapshot
    public var fingerprint: String
    public var commits: String
    public var existing: LinkedPullRequest?
    public var pendingTitle: String? = nil
    public var pendingBody: String? = nil
}

/// One mutation at a time per checkout. UI also checks active provider runs.
public actor GitHubCheckoutLocks {
    public static let shared = GitHubCheckoutLocks()
    private var folders = Set<String>()
    private var starting: [String: Int] = [:]
    public func acquire(_ folder: String) throws {
        let key = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        guard (starting[key] ?? 0) == 0, folders.insert(key).inserted else { throw AppServerFailure("Another operation is using this checkout. Wait for it to finish.") }
    }
    public func beginAgentSubmission(_ folder: String) throws {
        let key = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        guard !folders.contains(key) else { throw AppServerFailure("A GitHub operation is using this checkout. Wait for it to finish before sending.") }
        starting[key, default: 0] += 1
    }
    public func endAgentSubmission(_ folder: String) {
        let key = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        starting[key] = max(0, (starting[key] ?? 0) - 1)
    }
    public func release(_ folder: String) { folders.remove(URL(fileURLWithPath: folder).resolvingSymlinksInPath().path) }
}

public actor GitHubPRSubmission {
    public static let shared = GitHubPRSubmission()
    private let storage: URL
    public init(storage: URL = ProjectStorage.directory.appendingPathComponent("github-operations")) { self.storage = storage }
    struct Record: Codable {
        var repository: String
        var account: Int
        var base: String
        var source: String
        var original: String
        var tree: String
        var paths: [String]
        var title: String
        var body: String
        var commit: String?
        var indexUpdated = false
        var pushed = false
        var pr: LinkedPullRequest?
    }
    private func file(_ folder: String) -> URL {
        let path = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return storage.appendingPathComponent(key + ".json")
    }
    private func save(_ record: Record, folder: String) throws {
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: file(folder), options: .atomic)
    }
    public static func fingerprint(_ folder: String) async throws -> String {
        var hash = SHA256()
        for args in [["rev-parse", "HEAD"], ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
                     ["diff", "--no-ext-diff", "--no-textconv", "--binary", "HEAD", "--"],
                     ["diff", "--no-ext-diff", "--no-textconv", "--binary", "--cached", "--"]] {
            hash.update(data: try await ProjectCommand.data("/usr/bin/git", ["-C", folder] + args))
        }
        let untracked = try await ProjectCommand.git(folder, ["ls-files", "--others", "--exclude-standard", "-z"])
        for path in untracked.split(separator: "\0") {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(String(path))
            if (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true {
                hash.update(data: Data(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8))
            } else {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public func preview(workspace: ProjectWorkspace, base requestedBase: String? = nil) async throws -> GitHubPRPreview {
        let remote = try await ProjectCommand.git(workspace.folder, ["remote", "get-url", "origin"])
        let repo = try await GitHubAccount.shared.repository(GitHubGit.https(remote).name)
        let base = requestedBase?.isEmpty == false ? requestedBase! : repo.default_branch
        _ = try await ProjectCommand.git(workspace.folder, ["check-ref-format", "refs/heads/" + base])
        let snapshot = try await SessionChanges.snapshot(workspace, scope: .uncommitted)
        guard !snapshot.files.contains(where: { $0.status == "Conflicted" }) else { throw AppServerFailure("Resolve merge conflicts before creating a PR.") }
        let branch = await ProjectGit.currentBranch(workspace.folder)
        let candidates = branch == "HEAD" ? [] : try await GitHubPullRequests.list(repository: repo.full_name, branch: branch)
        let existing = candidates.first { $0.state == "OPEN" }
        let creates = branch == "HEAD" || branch == base || branch == repo.default_branch || (existing == nil && !candidates.isEmpty)
        let source = creates ? "diorama/pr-" + UUID().uuidString.lowercased().prefix(8) : branch
        var comparison: String?
        for ref in ["refs/remotes/origin/" + base, "refs/heads/" + base] {
            if let commit = try? await ProjectCommand.git(workspace.folder, ["rev-parse", "--verify", ref + "^{commit}"]) { comparison = commit; break }
        }
        guard let comparison else { throw AppServerFailure("The destination branch is not available locally. Use Fetch from remote, then refresh the preview.") }
        let commits = try await ProjectCommand.git(workspace.folder, ["log", "--oneline", comparison + "..HEAD", "--"])
        var result = GitHubPRPreview(repository: repo, workspace: workspace, base: existing?.baseRefName ?? base, source: String(source), createsBranch: creates,
            snapshot: snapshot, fingerprint: try await Self.fingerprint(workspace.folder), commits: commits, existing: existing)
        if FileManager.default.fileExists(atPath: file(workspace.folder).path) {
            let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file(workspace.folder)))
            result.source = record.source; result.base = record.base; result.createsBranch = false
            result.pendingTitle = record.title; result.pendingBody = record.body
        }
        return result
    }
    public func submit(_ preview: GitHubPRPreview, selected: Set<String>, title: String, body: String,
                       isActive: @escaping @Sendable (String) async -> Bool) async throws -> LinkedPullRequest {
        let folder = preview.workspace.folder
        try await GitHubCheckoutLocks.shared.acquire(folder)
        do {
            let result = try await perform(preview, selected: selected, title: title, body: body, isActive: isActive)
            await GitHubCheckoutLocks.shared.release(folder)
            return result
        } catch { await GitHubCheckoutLocks.shared.release(folder); throw error }
    }
    private func perform(_ preview: GitHubPRPreview, selected: Set<String>, title: String, body: String,
                         isActive: @escaping @Sendable (String) async -> Bool) async throws -> LinkedPullRequest {
        let folder = preview.workspace.folder
        guard !(await isActive(folder)) else { throw AppServerFailure("Wait for active Diorama work in this checkout to finish before sharing code.") }
        let identity = try await GitHubAccount.shared.identity()
        let remote = try GitHubGit.https(await ProjectCommand.git(folder, ["remote", "get-url", "origin"]))
        guard remote.name.lowercased() == preview.repository.full_name.lowercased() else { throw AppServerFailure("The repository changed. Refresh the preview.") }
        let recordFile = file(folder)
        var record: Record
        if FileManager.default.fileExists(atPath: recordFile.path) {
            record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: recordFile))
            guard record.account == identity.id, record.repository == preview.repository.full_name else { throw AppServerFailure("Reconnect the original account to finish this pending PR operation.") }
            if let pr = record.pr { return try await GitHubPullRequests.get(pr.url) }
        } else {
            guard try await Self.fingerprint(folder) == preview.fingerprint else { throw AppServerFailure("Files or commits changed since the preview. Refresh it before submitting.") }
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppServerFailure("Enter a PR title.") }
            guard selected.isSubset(of: Set(preview.snapshot.files.map(\.path))) else { throw AppServerFailure("The file selection changed. Refresh the preview.") }
            let paths = preview.snapshot.files.filter { selected.contains($0.path) }.flatMap { [$0.oldPath, $0.path].compactMap { $0 } }
            if preview.createsBranch {
                _ = try await ProjectCommand.git(folder, ["switch", "-c", preview.source, preview.snapshot.head])
            }
            let tree = try await selectedTree(folder: folder, paths: paths)
            record = Record(repository: preview.repository.full_name, account: identity.id, base: preview.base, source: preview.source,
                original: preview.snapshot.head, tree: tree, paths: paths, title: title, body: body)
            try save(record, folder: folder)
        }
        guard await ProjectGit.currentBranch(folder) == record.source else { throw AppServerFailure("Return to branch \(record.source) to finish this pending PR operation.") }
        var head = try await ProjectCommand.git(folder, ["rev-parse", "HEAD"])
        if record.commit == nil {
            if head != record.original {
                let parent = try await ProjectCommand.git(folder, ["rev-parse", "HEAD^"])
                let tree = try await ProjectCommand.git(folder, ["rev-parse", "HEAD^{tree}"])
                guard parent == record.original, tree == record.tree else { throw AppServerFailure("Local history changed during PR preparation. Review the pending operation before retrying.") }
            } else if !record.paths.isEmpty {
                guard !(await isActive(folder)) else { throw AppServerFailure("Active work started in this checkout. Retry after it finishes.") }
                try await commitSelected(folder: folder, paths: record.paths, title: record.title, expectedTree: record.tree, identity: identity)
                head = try await ProjectCommand.git(folder, ["rev-parse", "HEAD"])
                let actualTree = try await ProjectCommand.git(folder, ["rev-parse", "HEAD^{tree}"])
                guard actualTree == record.tree else { throw AppServerFailure("A Git hook changed the commit contents. Nothing was pushed. Review the local commit before continuing.") }
            }
            record.commit = head; try save(record, folder: folder)
        }
        guard head == record.commit else { throw AppServerFailure("Local history changed after preparing the commit. Restore the prepared branch before retrying.") }
        if !record.indexUpdated {
            if !record.paths.isEmpty { _ = try await ProjectCommand.git(folder, ["--literal-pathspecs", "reset", "-q", "HEAD", "--"] + record.paths) }
            record.indexUpdated = true; try save(record, folder: folder)
        }
        let prior = try await GitHubPullRequests.list(repository: record.repository, branch: record.source)
        if let completed = prior.first(where: { $0.state == "MERGED" && $0.headRefOid == record.commit && $0.baseRefName == record.base }) {
            record.pr = try await GitHubPullRequests.get(completed.url)
            try save(record, folder: folder)
            return record.pr!
        }
        if let closed = prior.first, closed.state != "OPEN" { throw AppServerFailure("This branch's PR is \(closed.state.lowercased()). Review a new branch before sharing further changes.") }
        if !record.pushed {
            _ = try await GitHubGit.remote(folder, arguments: ["push", "origin", record.commit! + ":refs/heads/" + record.source])
            record.pushed = true; try save(record, folder: folder)
        }
        let matching = try await GitHubPullRequests.list(repository: record.repository, branch: record.source, state: "open")
        let pr: LinkedPullRequest
        if let existing = matching.first {
            pr = try GitHubPullRequests.decode(await GitHubAccount.shared.api("/repos/\(record.repository)/pulls/\(existing.number)", method: "PATCH", body: .object(["title": .string(record.title), "body": .string(record.body)])))
        } else {
            pr = try GitHubPullRequests.decode(await GitHubAccount.shared.api("/repos/\(record.repository)/pulls", method: "POST", body: .object([
                "title": .string(record.title), "body": .string(record.body), "head": .string(record.source), "base": .string(record.base)])))
        }
        var pushed = pr; pushed.pushedAt = Date()
        record.pr = pushed; try save(record, folder: folder)
        return pushed
    }
    public func acknowledge(folder: String) throws { if FileManager.default.fileExists(atPath: file(folder).path) { try FileManager.default.removeItem(at: file(folder)) } }
    public func hasPending(folder: String) -> Bool { FileManager.default.fileExists(atPath: file(folder).path) }
    public func refreshUncommittedPreparation(folder: String) async throws {
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file(folder)))
        guard record.commit == nil, !record.pushed, record.pr == nil,
              try await ProjectCommand.git(folder, ["rev-parse", "HEAD"]) == record.original else {
            throw AppServerFailure("This operation already prepared a commit. Retry submission to reconcile it with GitHub first.")
        }
        try acknowledge(folder: folder)
    }
    func selectedTree(folder: String, paths: [String]) async throws -> String {
        let index = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-index-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: index) }
        let env = ["GIT_INDEX_FILE": index.path]
        _ = try await ProjectCommand.data("/usr/bin/git", ["-C", folder, "read-tree", "HEAD"], environmentOverrides: env)
        if !paths.isEmpty { _ = try await ProjectCommand.data("/usr/bin/git", ["--literal-pathspecs", "-C", folder, "add", "-A", "--"] + paths, environmentOverrides: env) }
        return String(decoding: try await ProjectCommand.data("/usr/bin/git", ["-C", folder, "write-tree"], environmentOverrides: env), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func commitSelected(folder: String, paths: [String], title: String, expectedTree: String, identity: GitHubIdentity? = nil) async throws {
        let index = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-index-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: index) }
        var env = ["GIT_INDEX_FILE": index.path]
        if let identity {
            let email = "\(identity.id)+\(identity.login)@users.noreply.github.com"
            env.merge(["GIT_AUTHOR_NAME": identity.login, "GIT_AUTHOR_EMAIL": email, "GIT_COMMITTER_NAME": identity.login, "GIT_COMMITTER_EMAIL": email]) { _, new in new }
        }
        _ = try await ProjectCommand.data("/usr/bin/git", ["-C", folder, "read-tree", "HEAD"], environmentOverrides: env)
        _ = try await ProjectCommand.data("/usr/bin/git", ["--literal-pathspecs", "-C", folder, "add", "-A", "--"] + paths, environmentOverrides: env)
        let tree = String(decoding: try await ProjectCommand.data("/usr/bin/git", ["-C", folder, "write-tree"], environmentOverrides: env), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard tree == expectedTree else { throw AppServerFailure("Selected files changed. Refresh the preview before committing.") }
        _ = try await ProjectCommand.data("/usr/bin/git", ["-C", folder, "commit", "-m", title], environmentOverrides: env)
    }
}
