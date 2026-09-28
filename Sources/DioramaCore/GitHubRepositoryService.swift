import Foundation
import CryptoKit

public actor GitHubRepositoryService {
    public static let shared = GitHubRepositoryService()
    public func clone(_ input: String, to folder: String) async throws {
        let name = input.contains(":") ? try GitHubGit.https(input).name : try GitHubAccount.validRepository(input)
        guard !FileManager.default.fileExists(atPath: folder) else { throw AppServerFailure("That folder already exists. Choose another location.") }
        let repo = try await GitHubAccount.shared.repository(name)
        _ = try await GitHubGit.run(folder: nil, repository: repo.full_name, arguments: ["clone", "--", "https://github.com/" + repo.full_name + ".git", folder])
    }
    private struct Publication: Codable {
        var account: Int
        var name: String
        var isPrivate: Bool
        var repositoryID: Int?
    }
    public func publish(folder: String, name: String, privateRepository: Bool) async throws -> GitHubRepo {
        try await GitHubCheckoutLocks.shared.acquire(folder)
        do {
            let result = try await publishLocked(folder: folder, name: name, privateRepository: privateRepository)
            await GitHubCheckoutLocks.shared.release(folder)
            return result
        } catch { await GitHubCheckoutLocks.shared.release(folder); throw error }
    }
    private func publishLocked(folder: String, name: String, privateRepository: Bool) async throws -> GitHubRepo {
        let name = try GitHubAccount.validRepository(name)
        let identity = try await GitHubAccount.shared.identity()
        let branch = await ProjectGit.currentBranch(folder)
        guard branch != "HEAD" else { throw AppServerFailure("Create a local branch before publishing this detached checkout.") }
        let commit = try await ProjectCommand.git(folder, ["rev-parse", "--verify", "HEAD^{commit}"])
        let key = SHA256.hash(data: Data(URL(fileURLWithPath: folder).resolvingSymlinksInPath().path.utf8)).map { String(format: "%02x", $0) }.joined()
        let journal = ProjectStorage.directory.appendingPathComponent("github-publish-" + key + ".json")
        let existing = try? await ProjectCommand.git(folder, ["remote", "get-url", "origin"])
        var record: Publication
        var repository: GitHubRepo?
        if FileManager.default.fileExists(atPath: journal.path) {
            record = try JSONDecoder().decode(Publication.self, from: Data(contentsOf: journal))
            guard record.account == identity.id, record.name == name, record.isPrivate == privateRepository else {
                throw AppServerFailure("Finish the pending publication with its original account, repository and visibility.")
            }
            do {
                let found = try await GitHubAccount.shared.repository(name)
                guard let expectedID = record.repositoryID, found.id == expectedID else {
                    throw AppServerFailure("A repository exists at this destination, but its creation could not be confirmed. Review it on GitHub and connect it explicitly before pushing.")
                }
                repository = found
            } catch let error as GitHubAPIError where error.status == 404 {
                guard record.repositoryID == nil else { throw error }
            }
        } else {
            guard existing == nil else { throw AppServerFailure("This project already has an origin remote. It was not changed.") }
            do {
                _ = try await GitHubAccount.shared.repository(name)
                throw AppServerFailure("That GitHub repository already exists. Connect it explicitly instead of publishing over it.")
            } catch let error as GitHubAPIError where error.status == 404 { }
            record = Publication(account: identity.id, name: name, isPrivate: privateRepository)
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: journal, options: .atomic)
        }
        if repository == nil {
            let parts = name.split(separator: "/").map(String.init)
            let endpoint = parts[0].lowercased() == identity.login.lowercased() ? "/user/repos" : "/orgs/\(parts[0])/repos"
            let data = try await GitHubAccount.shared.api(endpoint, method: "POST", body: .object(["name": .string(parts[1]), "private": .bool(privateRepository), "auto_init": .bool(false)]))
            repository = try JSONDecoder().decode(GitHubRepo.self, from: data)
            record.repositoryID = repository?.id
            try JSONEncoder().encode(record).write(to: journal, options: .atomic)
        }
        guard let repository, repository.private == privateRepository else { throw AppServerFailure("Repository visibility differs from the preview. Review it before continuing.") }
        if let existing {
            guard try GitHubGit.https(existing).name.lowercased() == repository.full_name.lowercased() else { throw AppServerFailure("The remote changed. It was not overwritten.") }
        } else { _ = try await ProjectCommand.git(folder, ["remote", "add", "origin", "https://github.com/" + repository.full_name + ".git"]) }
        _ = try await GitHubGit.remote(folder, arguments: ["push", "origin", commit + ":refs/heads/" + branch])
        try FileManager.default.removeItem(at: journal)
        return repository
    }
}
