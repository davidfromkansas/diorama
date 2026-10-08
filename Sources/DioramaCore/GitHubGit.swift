import Foundation

public enum GitHubGit {
    public static func https(_ remote: String) throws -> (name: String, url: String) {
        guard let repo = GitHubRepository.parse(remote), repo.host == "github.com" else { throw AppServerFailure("Only GitHub.com repositories are supported. The remote was not changed.") }
        let name = try GitHubAccount.validRepository(repo.name)
        if let parsed = URL(string: remote), parsed.scheme != nil {
            guard parsed.scheme == "https", parsed.user == nil, parsed.password == nil, parsed.port == nil, parsed.query == nil, parsed.fragment == nil else { throw AppServerFailure("Choose a plain GitHub HTTPS repository URL.") }
        } else { guard remote.hasPrefix("git@github.com:") else { throw AppServerFailure("Unsupported GitHub remote.") } }
        return (name, "https://github.com/" + name + ".git")
    }
    public static func run(folder: String?, repository: String, arguments: [String]) async throws -> String {
        let (args, environment) = try await invocation(repository: repository, arguments: arguments)
        return try await GitHubAccount.shared.performGit {
            let data = try await ProjectCommand.data("/usr/bin/git", args, folder: folder, environmentOverrides: environment)
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    /// Like `run`, but reports Git's combined output as it arrives (for live clone progress).
    /// Cancelling the task terminates Git.
    public static func stream(folder: String?, repository: String, arguments: [String], output: @escaping @Sendable (String) -> Void) async throws {
        let (args, environment) = try await invocation(repository: repository, arguments: arguments)
        _ = try await GitHubAccount.shared.performGit {
            let code = try await ProjectCommand.stream("/usr/bin/git", args, folder: folder, environmentOverrides: environment, output: output)
            guard code == 0 else { throw AppServerFailure("Git exited with status \(code). See the output above.") }
            return ""
        }
    }
    /// Git arguments and environment that use only Diorama's own GitHub credential for `repository`.
    private static func invocation(repository: String, arguments: [String]) async throws -> ([String], [String: String]) {
        let name = try GitHubAccount.validRepository(repository)
        guard let token = try await GitHubAccount.shared.accessToken() else { throw AppServerFailure("Connect GitHub in Settings to continue.") }
        let appHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/DioramaReporter")
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("DioramaReporter")
        guard let helper = [appHelper, sibling].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw AppServerFailure("Diorama's Git credential helper is missing. Reinstall the app.") }
        let quoted = "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let args = ["-c", "credential.helper=", "-c", "credential.helper=!" + quoted + " --github-credential",
                    "-c", "credential.useHttpPath=true", "-c", "http.followRedirects=false"] + arguments
        var environment = ["DIORAMA_GITHUB_REPOSITORY": name, "GIT_ASKPASS": "/usr/bin/false", "SSH_ASKPASS": "/usr/bin/false"]
        if GitHubCredentials.isDevelopmentBuild { environment[GitHubCredentials.developmentTokenVariable] = token }
        return (args, environment)
    }
    public static func remote(_ folder: String, name: String = "origin", arguments: [String]) async throws -> String {
        let remote = try await ProjectCommand.git(folder, ["remote", "get-url", name])
        let destination = try https(remote)
        // Git's remote.url is multi-valued: -c does not replace its first URL.
        // Use the verified HTTPS URL as the operand and reject URL rewrites.
        let resolved = try await ProjectCommand.git(folder, ["ls-remote", "--get-url", destination.url])
        guard resolved == destination.url else { throw AppServerFailure("Git configuration redirects this GitHub URL. Review the URL rewrite before continuing.") }
        guard let index = arguments.indices.dropFirst().first(where: { arguments[$0] == name }) else { throw AppServerFailure("Missing GitHub remote operand.") }
        var args = arguments
        args[index] = destination.url
        if arguments.first == "fetch", index == arguments.count - 1 { args.append("refs/heads/*:refs/remotes/\(name)/*") }
        return try await run(folder: folder, repository: destination.name, arguments: args)
    }
}
