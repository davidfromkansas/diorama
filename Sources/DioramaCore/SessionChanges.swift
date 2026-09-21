import Foundation

public enum ChangeScope: String, CaseIterable, Sendable { case session = "Session changes", uncommitted = "Uncommitted changes" }
public struct ChangedFile: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var oldPath: String?
    public var status: String
    public var added = 0
    public var removed = 0
    public var untracked = false
}
public struct ChangesSnapshot: Equatable, Sendable {
    public var files: [ChangedFile]
    public var head: String
    public var branch: String
    public var dirty: Bool
    public var added: Int { files.reduce(0) { $0 + $1.added } }
    public var removed: Int { files.reduce(0) { $0 + $1.removed } }
}
public enum SessionChanges {
    private static func git(_ folder: String, _ args: [String]) async throws -> String {
        String(decoding: try await ProjectCommand.data("/usr/bin/git", ["--literal-pathspecs", "-C", folder] + args), as: UTF8.self)
    }
    public static func snapshot(_ workspace: ProjectWorkspace, scope: ChangeScope) async throws -> ChangesSnapshot {
        guard !workspace.cleaned, FileManager.default.fileExists(atPath: workspace.folder) else { throw AppServerFailure("Worktree unavailable") }
        let folder = workspace.folder
        let head = try await ProjectCommand.git(folder, ["rev-parse", "HEAD"])
        let branch = (try? await ProjectCommand.git(folder, ["symbolic-ref", "--short", "HEAD"])) ?? "Detached HEAD"
        let base = scope == .session ? workspace.baseCommit : "HEAD"
        let names = try await git(folder, ["diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "--find-renames", base, "--"])
        var files = parseNames(names)
        let untracked = try await git(folder, ["ls-files", "--others", "--exclude-standard", "-z"])
        files += untracked.split(separator: "\0").map { ChangedFile(path: String($0), status: "Added", untracked: true) }
        let stats = try await git(folder, ["diff", "--no-ext-diff", "--no-textconv", "--numstat", "-z", "--find-renames", base, "--"])
        let counts = parseStats(stats)
        for i in files.indices { if let count = counts[files[i].path] { files[i].added = count.0; files[i].removed = count.1 } }
        let conflicts = Set(try await git(folder, ["diff", "--name-only", "--diff-filter=U", "-z"]).split(separator: "\0").map(String.init))
        var seen = Set<String>()
        files = files.filter { seen.insert($0.path).inserted }
        for i in files.indices {
            if conflicts.contains(files[i].path) { files[i].status = "Conflicted" }
            if files[i].untracked {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(files[i].path)
                if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey]), values.isSymbolicLink != true, (values.fileSize ?? 0) <= 512_000,
                   let data = try? Data(contentsOf: url), !data.contains(0), let text = String(data: data, encoding: .utf8) {
                    files[i].added = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
                }
            }
        }
        let status = try await git(folder, ["status", "--porcelain=v1", "-z"])
        return ChangesSnapshot(files: files.sorted { $0.path < $1.path }, head: head, branch: branch, dirty: !status.isEmpty)
    }
    public static func parseNames(_ value: String) -> [ChangedFile] {
        let parts = value.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var result: [ChangedFile] = []; var i = 0
        while i + 1 < parts.count, !parts[i].isEmpty {
            let code = parts[i]; let first = parts[i + 1]; i += 2
            var path = first; var old: String?
            if code.hasPrefix("R") || code.hasPrefix("C"), i < parts.count { old = first; path = parts[i]; i += 1 }
            let labels: [Character: String] = ["A":"Added", "D":"Deleted", "M":"Modified", "R":"Renamed", "C":"Copied", "U":"Conflicted", "T":"Type changed"]
            result.append(ChangedFile(path: path, oldPath: old, status: code.first.flatMap { labels[$0] } ?? "Changed"))
        }
        return result
    }
    public static func parseStats(_ value: String) -> [String: (Int, Int)] {
        let parts = value.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var result: [String: (Int, Int)] = [:]; var i = 0
        while i < parts.count {
            let fields = parts[i].split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false); i += 1
            guard fields.count == 3 else { continue }
            var path = String(fields[2])
            if path.isEmpty, i + 1 < parts.count { path = parts[i + 1]; i += 2 }
            result[path] = (Int(fields[0]) ?? 0, Int(fields[1]) ?? 0)
        }
        return result
    }
    public static func diff(_ file: ChangedFile, workspace: ProjectWorkspace, scope: ChangeScope) async throws -> String {
        guard !workspace.cleaned, FileManager.default.fileExists(atPath: workspace.folder) else { throw AppServerFailure("Worktree unavailable") }
        if file.untracked {
            let url = URL(fileURLWithPath: workspace.folder).appendingPathComponent(file.path)
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { return "Symbolic link: " + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path)) }
            guard (values.fileSize ?? 0) <= 512_000 else { return "File is too large to preview. Open externally to inspect it." }
            let data = try Data(contentsOf: url)
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return "Binary file — open externally to inspect it." }
            var lines = text.components(separatedBy: "\n")
            if text.isEmpty { lines = [] } else if text.hasSuffix("\n") { lines.removeLast() }
            return "@@ -0,0 +1,\(lines.count) @@\n" + lines.map { "+" + $0 }.joined(separator: "\n")
        }
        let paths = [file.oldPath, file.path].compactMap { $0 }
        let patch = try await git(workspace.folder, ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--submodule=short", "--find-renames", scope == .session ? workspace.baseCommit : "HEAD", "--"] + paths)
        return patch.utf8.count > 512_000 ? "Diff is too large to preview. Open externally to inspect it." : patch
    }
}
