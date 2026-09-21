import Foundation

public struct GitHubRepository: Codable, Equatable, Sendable {
    public var host: String
    public var name: String
    public var argument: String { host + "/" + name }
    public static func parse(_ remote: String) -> Self? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@"), let colon = value.firstIndex(of: ":") { value = "https://" + value.dropFirst(4).prefix(upTo: colon) + "/" + value.suffix(from: value.index(after: colon)) }
        guard let url = URL(string: value), let host = url.host else { return nil }
        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        guard path.split(separator: "/").count == 2 else { return nil }
        return Self(host: host.lowercased(), name: path)
    }
}
public struct PRCheck: Codable, Equatable, Identifiable, Sendable {
    public var name: String?
    public var context: String?
    public var status: String?
    public var conclusion: String?
    public var state: String?
    public var detailsUrl: String?
    public var targetUrl: String?
    public var id: String { (name ?? context ?? "Check") + (detailsUrl ?? targetUrl ?? "") }
    public var title: String { name ?? context ?? "Check" }
    public var url: String? { detailsUrl ?? targetUrl }
    public var result: String {
        let value = (conclusion?.isEmpty == false ? conclusion : state) ?? status ?? "UNKNOWN"
        switch value {
        case "SUCCESS", "NEUTRAL", "SKIPPED": return "Passed"
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE": return "Failed"
        case "CANCELLED": return "Cancelled"
        case "PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "EXPECTED": return "Running"
        default: return "Unavailable"
        }
    }
}
public struct LinkedPullRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String { url }
    public var number: Int
    public var title: String
    public var url: String
    public var state: String
    public var isDraft: Bool
    public var headRefName: String
    public var headRefOid: String
    public var headRepository: RepositoryName?
    public var headRepositoryOwner: RepositoryOwner?
    public var statusCheckRollup: [PRCheck]?
    public var updatedAt: Date?
    public struct RepositoryName: Codable, Equatable, Sendable { public var name: String }
    public struct RepositoryOwner: Codable, Equatable, Sendable { public var login: String }
    public var checks: [PRCheck] { statusCheckRollup ?? [] }
    public var checkSummary: String {
        if statusCheckRollup == nil { return "Checks unavailable" }
        if checks.isEmpty { return "No checks" }
        for (result, label) in [("Failed", "failed"), ("Running", "running"), ("Cancelled", "cancelled"), ("Unavailable", "unavailable")] {
            let count = checks.filter { $0.result == result }.count
            if count > 0 { return "\(count) check\(count == 1 ? "" : "s") \(label)" }
        }
        return "Checks passed"
    }
    public var summary: String { "PR #\(number) · \(isDraft && state == "OPEN" ? "Draft" : state.capitalized) · \(checkSummary)" }
    public func matches(head: GitHubRepository, branch: String) -> Bool {
        guard let owner = headRepositoryOwner?.login, let repo = headRepository?.name,
              let host = URL(string: url)?.host else { return false }
        return host.lowercased() == head.host && (owner + "/" + repo).lowercased() == head.name.lowercased() && headRefName == branch
    }
    public func excludesLocalChanges(_ snapshot: ChangesSnapshot) -> Bool { snapshot.head != headRefOid || snapshot.dirty }
}
public actor PullRequestService {
    public static let shared = PullRequestService()
    public typealias GitHubCommand = @Sendable ([String]) async throws -> String
    private let command: GitHubCommand
    public init(command: @escaping GitHubCommand = { try await ProjectCommand.gh($0) }) { self.command = command }
    private var inflight: [String: Task<[LinkedPullRequest], Error>] = [:]
    private var cache: [String: (Date, [LinkedPullRequest])] = [:]
    private static let fields = "number,title,url,state,isDraft,headRefName,headRefOid,headRepository,headRepositoryOwner,statusCheckRollup"
    public func discover(project: DioramaProject, workspace: ProjectWorkspace, force: Bool = false) async throws -> [LinkedPullRequest] {
        let command = self.command
        if workspace.cleaned {
            guard let pr = workspace.pullRequest else { return [] }
            return try await query(key: pr.url, force: force) {
                let text = try await command(["pr", "view", pr.url, "--json", Self.fields])
                return [try JSONDecoder().decode(LinkedPullRequest.self, from: Data(text.utf8))]
            }
        }
        let branch = try await ProjectCommand.git(workspace.folder, ["symbolic-ref", "--short", "HEAD"])
        guard let remote = project.remote, let base = GitHubRepository.parse(remote) else { return [] }
        let pushRemote = (try? await ProjectCommand.git(workspace.folder, ["config", "--get", "branch.\(branch).pushRemote"]))
        let defaultPush = (try? await ProjectCommand.git(workspace.folder, ["config", "--get", "remote.pushDefault"]))
        let tracking = (try? await ProjectCommand.git(workspace.folder, ["config", "--get", "branch.\(branch).remote"]))
        let name = pushRemote ?? defaultPush ?? tracking ?? "origin"
        let headRemote = try await ProjectCommand.git(workspace.folder, ["remote", "get-url", name])
        guard let head = GitHubRepository.parse(headRemote) else { return [] }
        let key = base.argument + ":" + head.argument + ":" + branch
        return try await query(key: key, force: force) {
            let text = try await command(["pr", "list", "--repo", base.argument, "--head", branch, "--state", "all", "--limit", "100", "--json", Self.fields])
            return try JSONDecoder().decode([LinkedPullRequest].self, from: Data(text.utf8)).filter { $0.matches(head: head, branch: branch) }
        }
    }
    private func query(key: String, force: Bool, operation: @escaping @Sendable () async throws -> [LinkedPullRequest]) async throws -> [LinkedPullRequest] {
        if let task = inflight[key] { return try await task.value }
        if !force, let (date, rows) = cache[key], Date().timeIntervalSince(date) < 55 { return rows }
        let task = Task { var rows = try await operation(); for i in rows.indices { rows[i].updatedAt = Date() }; return rows }
        inflight[key] = task
        defer { inflight[key] = nil }
        let result = try await task.value; cache[key] = (Date(), result); return result
    }
    public static func fixPrompt(_ pr: LinkedPullRequest) async -> String {
        var prompt = "Investigate and fix the failing CI checks for \(pr.url). Verify the fixes locally.\n"
        var runs = Set<String>()
        for check in pr.checks where check.result == "Failed" {
            prompt += "\n\(check.title): \(check.url ?? "No check link available")\n"
            guard let link = check.url, let url = URL(string: link), url.host == URL(string: pr.url)?.host else { continue }
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 5, parts[2] == "actions", parts[3] == "runs", Int(parts[4]) != nil, runs.insert(parts[4]).inserted else { continue }
            let repo = (url.host ?? "github.com") + "/" + parts[0] + "/" + parts[1]
            if let logs = try? await ProjectCommand.gh(["run", "view", parts[4], "--repo", repo, "--log-failed"]) { prompt += String(logs.prefix(12_000)) + "\n" }
            else { prompt += "Failure output unavailable; use the check link.\n" }
            if runs.count >= 3 { break }
        }
        return prompt
    }
}
