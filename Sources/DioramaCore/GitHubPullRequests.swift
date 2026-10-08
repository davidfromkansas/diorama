import Foundation

/// GitHub.com PR transport, using only Diorama's account.
public enum GitHubPullRequests {
    public static func decode(_ data: Data) throws -> LinkedPullRequest {
        let value = try JSONDecoder().decode(WireValue.self, from: data)
        guard let number = value["number"].number, let url = value["html_url"].string,
              let title = value["title"].string, let head = value["head"]["ref"].string,
              let sha = value["head"]["sha"].string else { throw AppServerFailure("GitHub returned an incomplete pull request.") }
        var result = LinkedPullRequest(number: Int(number), title: title, url: url,
            state: value["merged_at"].string != nil || value["merged"].bool ? "MERGED" : (value["state"].string ?? "unknown").uppercased(),
            isDraft: value["draft"].bool, headRefName: head, headRefOid: sha)
        result.headRepository = value["head"]["repo"]["name"].string.map { .init(name: $0) }
        result.headRepositoryOwner = value["head"]["repo"]["owner"]["login"].string.map { .init(login: $0) }
        result.baseRefName = value["base"]["ref"].string
        result.mergedAt = value["merged_at"].string
        result.mergeCommit = value["merge_commit_sha"].string
        result.body = value["body"].string
        result.mergeable = value["mergeable"] == .null ? nil : value["mergeable"].bool
        result.mergeableState = value["mergeable_state"].string
        return result
    }
    public static func identity(_ url: String) throws -> (repository: String, number: Int) {
        guard let link = URL(string: url), link.scheme == "https", link.host == "github.com",
              link.user == nil, link.password == nil else { throw AppServerFailure("Unsupported pull request URL.") }
        let parts = link.path.split(separator: "/")
        guard parts.count == 4, parts[2] == "pull", let number = Int(parts[3]), number > 0 else { throw AppServerFailure("Invalid pull request URL.") }
        return (try GitHubAccount.validRepository(parts[0] + "/" + parts[1]), number)
    }
    public static func get(_ url: String) async throws -> LinkedPullRequest {
        let identity = try identity(url)
        var pr = try decode(await GitHubAccount.shared.api("/repos/\(identity.repository)/pulls/\(identity.number)"))
        // Check failures must not hide a successfully refreshed merge state.
        if let checks = try? await GitHubAccount.shared.api("/repos/\(identity.repository)/commits/\(pr.headRefOid)/check-runs?per_page=100"),
           let statuses = try? await GitHubAccount.shared.api("/repos/\(identity.repository)/commits/\(pr.headRefOid)/status") {
            let runs = try JSONDecoder().decode(WireValue.self, from: checks)["check_runs"].array
            let contexts = try JSONDecoder().decode(WireValue.self, from: statuses)["statuses"].array
            pr.statusCheckRollup = runs.map { PRCheck(name: $0["name"].string, status: $0["status"].string?.uppercased(), conclusion: $0["conclusion"].string?.uppercased(), detailsUrl: $0["html_url"].string) }
                + contexts.map { PRCheck(context: $0["context"].string, state: $0["state"].string?.uppercased(), targetUrl: $0["target_url"].string) }
        }
        pr.updatedAt = Date()
        return pr
    }
    /// Re-reads a pull request just merged until GitHub reports it merged: its API can briefly
    /// return the old open state after a successful merge.
    /// `merged` says GitHub already accepted the merge (its merge reply), so a read that still
    /// lags after the retries is reported as merged.
    public static func confirmMerged(_ url: String, attempts: Int = 20, merged: Bool = false) async throws -> LinkedPullRequest {
        var pr = try await get(url)
        for _ in 1..<max(1, attempts) where pr.state != "MERGED" {
            try await Task.sleep(for: .milliseconds(750))
            pr = try await get(url)
        }
        if merged, pr.state != "MERGED" { pr.state = "MERGED" }
        return pr
    }
    public static func list(repository: String, branch: String, state: String = "all", headOwner: String? = nil) async throws -> [LinkedPullRequest] {
        let repository = try GitHubAccount.validRepository(repository)
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "head", value: (headOwner ?? String(repository.split(separator: "/")[0])) + ":" + branch), URLQueryItem(name: "state", value: state), URLQueryItem(name: "per_page", value: "100")]
        let data = try await GitHubAccount.shared.api("/repos/\(repository)/pulls?" + (components.percentEncodedQuery ?? ""))
        let rows = try JSONDecoder().decode([WireValue].self, from: data)
        return try rows.map { try decode(JSONEncoder().encode($0)) }
    }
    // Retains the discovery service's injectable boundary for existing fixtures.
    public static func command(_ arguments: [String]) async throws -> String {
        let data: Data
        if arguments.prefix(2) == ["pr", "view"], arguments.count > 2 {
            data = try JSONEncoder().encode(await get(arguments[2]))
        } else if arguments.prefix(2) == ["pr", "list"], let ri = arguments.firstIndex(of: "--repo"), let hi = arguments.firstIndex(of: "--head"), ri + 1 < arguments.count, hi + 1 < arguments.count {
            let repository = arguments[ri + 1]
            guard repository.hasPrefix("github.com/") else { throw AppServerFailure("Only GitHub.com is supported.") }
            let owner = arguments.firstIndex(of: "--head-owner").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            let rows = try await list(repository: String(repository.dropFirst(11)), branch: arguments[hi + 1], headOwner: owner)
            var detailed: [LinkedPullRequest] = []
            for row in rows { detailed.append(try await get(row.url)) }
            data = try JSONEncoder().encode(detailed)
        } else { throw AppServerFailure("Unsupported GitHub operation.") }
        return String(decoding: data, as: UTF8.self)
    }
}
