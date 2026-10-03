import Foundation

public enum DescriptiveBranch {
    public static func suggestion(_ task: String) -> String? {
        let text = task.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let stop: Set<String> = ["i", "we", "you", "can", "could", "please", "want", "would", "like", "to", "a", "an", "the", "for", "me", "this", "that", "it", "and", "of", "my"]
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stop.contains($0) && $0.unicodeScalars.allSatisfy { $0.isASCII } }
        guard words.count >= 2, !["hello", "hey", "hi", "help", "continue", "proceed", "yes", "okay", "ok"].contains(words[0]) else { return nil }
        return words.prefix(6).joined(separator: "-")
    }
    public static func valid(_ name: String) -> Bool {
        name.count <= 100 && name.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+){0,5}$"#, options: .regularExpression) != nil
    }
    public static func candidate(_ base: String, suffix: Int) -> String {
        suffix == 1 ? base : base.split(separator: "-").prefix(5).joined(separator: "-") + "-\(suffix)"
    }
}

/// Reservations cover concurrent creations in this app; Git remains authoritative across clients.
actor DescriptiveBranchCreation {
    static let shared = DescriptiveBranchCreation()
    private var reserved = Set<String>()
    func create(project: DioramaProject, id: String, branch requested: String, folder: String, commit: String) async throws -> String {
        guard DescriptiveBranch.valid(requested) else { throw AppServerFailure("Use 1–6 lowercase words separated by hyphens for the new branch.") }
        _ = try await ProjectCommand.git(project.folder, ["check-ref-format", "--branch", requested])
        for suffix in 1...10_000 {
            try Task.checkCancellation()
            let branch = DescriptiveBranch.candidate(requested, suffix: suffix), key = project.commonDirectory + "\u{1F}" + DescriptiveBranch.candidate(requested, suffix: suffix)
            if reserved.contains(key) { continue }
            reserved.insert(key)
            do {
                let refs = try await ProjectCommand.git(project.folder, ["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"])
                let occupied = refs.split(separator: "\n").contains { ref in
                    if ref == "refs/heads/" + branch { return true }
                    let parts = ref.split(separator: "/")
                    return parts.count > 3 && parts[1] == "remotes" && parts.dropFirst(3).joined(separator: "/") == branch
                }
                if occupied { reserved.remove(key); continue }
                do { _ = try await ProjectCommand.git(project.folder, ["worktree", "add", "-b", branch, folder, commit]) }
                catch {
                    let exists = (try? await ProjectCommand.git(project.folder, ["show-ref", "--verify", "refs/heads/" + branch])) != nil
                    if exists && !FileManager.default.fileExists(atPath: folder) { reserved.remove(key); continue }
                    throw error
                }
                _ = try await ProjectCommand.git(project.folder, ["config", "branch." + branch + ".dioramaWorkspace", id])
                reserved.remove(key)
                return branch
            } catch { reserved.remove(key); throw error }
        }
        throw AppServerFailure("Could not reserve a unique branch name. Choose another name.")
    }
}
