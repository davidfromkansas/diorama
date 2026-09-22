import Foundation
import Testing
@testable import DioramaCore

struct ProjectTests {
    func repository() async throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-project-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try await ProjectCommand.git(root.path, ["init", "-b", "main"])
        _ = try await ProjectCommand.git(root.path, ["config", "user.name", "Diorama Test"])
        _ = try await ProjectCommand.git(root.path, ["config", "user.email", "test@example.invalid"])
        try Data("original".utf8).write(to: root.appendingPathComponent("sample.txt"))
        _ = try await ProjectCommand.git(root.path, ["add", "sample.txt"])
        _ = try await ProjectCommand.git(root.path, ["commit", "-m", "Seed"])
        return root
    }
    @Test func isolatedWorktreesContextAndRetry() async throws {
        let root = try await repository(); defer { try? FileManager.default.removeItem(at: root) }
        var project = try await ProjectGit.discover(root.path)
        project.context.instructions = "Use existing components"
        project.context.references = ["sample.txt"]
        let trees = root.appendingPathComponent("isolated")
        let first = try await ProjectGit.createWorkspace(project: project, id: "first", root: trees)
        let second = try await ProjectGit.createWorkspace(project: project, id: "second", root: trees)
        #expect(first.branch != second.branch)
        try Data("changed".utf8).write(to: URL(fileURLWithPath: first.folder).appendingPathComponent("sample.txt"))
        #expect(try String(contentsOf: root.appendingPathComponent("sample.txt"), encoding: .utf8) == "original")
        #expect(try await ProjectGit.preview(folder: second.folder, path: "sample.txt") == "original")
        #expect(try await ProjectGit.createWorkspace(project: project, id: "first", root: trees).folder == first.folder)
        project.context.instructions = "New instruction"
        #expect(first.context.instructions == "Use existing components")
        #expect(first.context.prompt(folder: first.folder, commit: first.baseCommit).contains(first.folder + "/sample.txt"))
        #expect(try await ProjectGit.discover(second.folder).commonDirectory == project.commonDirectory)
        await #expect(throws: (any Error).self) { try await ProjectGit.cleanup(project: project, workspace: first) }
        #expect(FileManager.default.fileExists(atPath: first.folder))
        try await ProjectGit.cleanup(project: project, workspace: second)
        #expect(!FileManager.default.fileExists(atPath: second.folder))
        #expect(try await ProjectCommand.git(root.path, ["rev-parse", "--verify", second.branch]) == second.baseCommit)
    }
    @Test func latestRemoteAndExplicitOfflineFallback() async throws {
        let remote = try await repository(); defer { try? FileManager.default.removeItem(at: remote) }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: local) }
        _ = try await ProjectCommand.run("/usr/bin/git", ["clone", remote.path, local.path])
        let project = try await ProjectGit.discover(local.path)
        try Data("new remote".utf8).write(to: remote.appendingPathComponent("sample.txt"))
        _ = try await ProjectCommand.git(remote.path, ["commit", "-am", "Update"])
        let work = try await ProjectGit.createWorkspace(project: project, id: "fresh", root: local.appendingPathComponent("trees"))
        #expect(try await ProjectGit.preview(folder: work.folder, path: "sample.txt") == "new remote")
        #expect(try await ProjectGit.preview(folder: local.path, path: "sample.txt") == "original")
        _ = try await ProjectCommand.git(local.path, ["remote", "set-url", "origin", "/nonexistent/diorama-test-remote"])
        await #expect(throws: (any Error).self) {
            try await ProjectGit.createWorkspace(project: project, id: "offline", root: local.appendingPathComponent("trees"))
        }
        let cached = try await ProjectGit.createWorkspace(project: project, id: "offline", useCached: true, root: local.appendingPathComponent("trees"))
        #expect(cached.baseCommit == work.baseCommit)
    }
    @Test func projectStoragePreservesDraftAndContext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects.json")
        var p = DioramaProject(name: "Example", folder: "/example", commonDirectory: "/example/.git", base: "origin/main", remote: "example")
        p.draft = "Do not lose this"; p.context.references = ["docs/spec.md", "https://example.com"]
        p.pendingWorkspace = "recovery"
        try ProjectStorage.save([p], to: file)
        #expect(try ProjectStorage.load(from: file) == [p])
        try Data("invalid json".utf8).write(to: file)
        #expect(throws: (any Error).self) { try ProjectStorage.load(from: file) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "invalid json")
    }
    @Test func projectDraftModesSurviveStorageAndLegacyFiles() throws {
        var project = DioramaProject(name: "Draft", folder: "/fixture", commonDirectory: "/fixture/.git", base: "main", remote: nil)
        project.draft = "Plan this change"
        project.draftMode = "plan"
        project.draftGoal = false
        let data = try JSONEncoder().encode(project)
        let restored = try JSONDecoder().decode(DioramaProject.self, from: data)
        #expect(restored.draftMode == "plan")
        #expect(restored.draftGoal == false)
        #expect(restored.draft == project.draft)
        project.draftMode = "default"; project.draftGoal = true
        #expect(try JSONDecoder().decode(DioramaProject.self, from: JSONEncoder().encode(project)).draftGoal == true)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "draftMode"); legacy.removeValue(forKey: "draftGoal")
        let old = try JSONDecoder().decode(DioramaProject.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.draftMode == nil && old.draftGoal == nil)
        #expect(old.draft == project.draft)
    }
    @Test func cleanupProtectsUnmergedAndIgnoredFiles() async throws {
        let root = try await repository(); defer { try? FileManager.default.removeItem(at: root) }
        let p = try await ProjectGit.discover(root.path)
        let work = try await ProjectGit.createWorkspace(project: p, id: "protected", root: root.appendingPathComponent("trees"))
        try Data("new".utf8).write(to: URL(fileURLWithPath: work.folder).appendingPathComponent("sample.txt"))
        _ = try await ProjectCommand.git(work.folder, ["commit", "-am", "Unmerged change"])
        await #expect(throws: (any Error).self) { try await ProjectGit.cleanup(project: p, workspace: work) }
        #expect(FileManager.default.fileExists(atPath: work.folder))
    }

    @Test func ignoredFilesPreventCleanupEvenWhenGitStatusIsClean() async throws {
        let root = try await repository(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("private-cache/\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
        _ = try await ProjectCommand.git(root.path, ["add", ".gitignore"])
        _ = try await ProjectCommand.git(root.path, ["commit", "-m", "Ignore local cache"])
        let project = try await ProjectGit.discover(root.path)
        let work = try await ProjectGit.createWorkspace(project: project, id: "ignored", root: root.appendingPathComponent("trees"))
        let cache = URL(fileURLWithPath: work.folder).appendingPathComponent("private-cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let contents = Data("Keep this local file".utf8)
        try contents.write(to: cache.appendingPathComponent("notes.txt"))
        #expect(try await ProjectCommand.git(work.folder, ["status", "--porcelain"]).isEmpty)
        #expect(!(try await ProjectGit.files(folder: work.folder)).contains("private-cache/notes.txt"))
        #expect(try await ProjectGit.files(folder: work.folder, showIgnored: true).contains("private-cache/notes.txt"))
        await #expect(throws: (any Error).self) { try await ProjectGit.cleanup(project: project, workspace: work) }
        #expect(try Data(contentsOf: cache.appendingPathComponent("notes.txt")) == contents)
    }

    @Test func attachmentsKeepExactBaseContentsAndOccupiedFoldersArePreserved() async throws {
        let root = try await repository(); defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("  Reference text\n\n".utf8)
        try original.write(to: root.appendingPathComponent("sample.txt"))
        _ = try await ProjectCommand.git(root.path, ["commit", "-am", "Save reference"])
        let project = try await ProjectGit.discover(root.path)
        let commit = try await ProjectCommand.git(root.path, ["rev-parse", "HEAD"])
        let snapshot = try await ProjectGit.snapshot(folder: root.path, path: "sample.txt", revision: commit)
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
        try Data("Updated after attachment".utf8).write(to: root.appendingPathComponent("sample.txt"))
        #expect(try Data(contentsOf: snapshot) == original)
        let trees = root.appendingPathComponent("trees")
        let occupied = trees.appendingPathComponent(project.id).appendingPathComponent("occupied")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        try original.write(to: occupied.appendingPathComponent("keep.txt"))
        await #expect(throws: (any Error).self) {
            try await ProjectGit.createWorkspace(project: project, id: "occupied", root: trees)
        }
        #expect(try Data(contentsOf: occupied.appendingPathComponent("keep.txt")) == original)
    }
}
