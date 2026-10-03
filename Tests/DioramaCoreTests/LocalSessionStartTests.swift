import Foundation
import Testing
@testable import DioramaCore

struct LocalSessionStartTests {
    @Test func creationPickerUsesCachedRemoteRefsAndDefaultBranch() async throws {
        let root = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try await ProjectGit.defaultStartReference(root.path) == "main")
        _ = try await ProjectCommand.git(root.path, ["update-ref", "refs/remotes/origin/develop", "HEAD"])
        _ = try await ProjectCommand.git(root.path, ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/develop"])
        #expect(try await ProjectGit.defaultStartReference(root.path) == "origin/develop")
        _ = try await ProjectCommand.git(root.path, ["update-ref", "refs/remotes/origin/main", "HEAD"])
        #expect(try await ProjectGit.defaultStartReference(root.path) == "origin/main")
        let choices = try await ProjectGit.startBranches(root.path)
        #expect(choices.contains("main") && choices.contains("origin/main") && choices.contains("origin/develop"))
        #expect(!choices.contains("origin/HEAD"))
        #expect(try await ProjectGit.localBranches(root.path) == ["main"])
    }
    @Test func defaultsAndDetachedHead() async throws {
        let root = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try await ProjectGit.defaultLocalReference(root.path) == "main")
        _ = try await ProjectCommand.git(root.path, ["branch", "-m", "master"])
        #expect(try await ProjectGit.defaultLocalReference(root.path) == "master")
        _ = try await ProjectCommand.git(root.path, ["branch", "-m", "feature"])
        #expect(try await ProjectGit.defaultLocalReference(root.path) == "feature")
        _ = try await ProjectCommand.git(root.path, ["checkout", "--detach"])
        #expect(try await ProjectGit.defaultLocalReference(root.path) == "HEAD")
    }
    @Test func directPreservesEditsAndRejectsCleanupAndUnsafeSwitch() async throws {
        let root = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try await ProjectGit.discover(root.path)
        _ = try await ProjectCommand.git(root.path, ["branch", "feature"])
        try Data("unsaved".utf8).write(to: root.appendingPathComponent("sample.txt"))
        let options = SessionStartOptions(folder: root.path, reference: "main", createWorktree: false)
        let direct = try await ProjectGit.prepareLocal(project: project, id: "direct", options: options)
        #expect(!direct.isManagedWorktree)
        #expect(try await ProjectGit.preview(folder: root.path, path: "sample.txt") == "unsaved")
        await #expect(throws: (any Error).self) { try await ProjectGit.cleanup(project: project, workspace: direct) }
        let change = SessionStartOptions(folder: root.path, reference: "feature", createWorktree: false)
        await #expect(throws: (any Error).self) { try await ProjectGit.prepareLocal(project: project, id: "switch", options: change, switchConfirmed: true) }
        try Data("original".utf8).write(to: root.appendingPathComponent("sample.txt"))
        await #expect(throws: (any Error).self) { try await ProjectGit.prepareLocal(project: project, id: "switch", options: change) }
        await #expect(throws: (any Error).self) { try await ProjectGit.prepareLocal(project: project, id: "switch", options: change, switchConfirmed: true, activeFolders: [root.path]) }
        _ = try await ProjectGit.prepareLocal(project: project, id: "switch", options: change, switchConfirmed: true)
        #expect(await ProjectGit.currentBranch(root.path) == "feature")
    }
    @Test func emptyRepositoryAndMissingBranchAreRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await ProjectCommand.git(root.path, ["init", "-b", "main"])
        await #expect(throws: (any Error).self) { try await ProjectGit.localBranches(root.path) }
        let seeded = try await ProjectTests().repository()
        defer { try? FileManager.default.removeItem(at: seeded) }
        let project = try await ProjectGit.discover(seeded.path)
        await #expect(throws: (any Error).self) {
            try await ProjectGit.createWorkspace(project: project, id: "missing", base: "missing", root: root.appendingPathComponent("trees"))
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_TAIPEI_LOCAL_PROBE"] == "1"))
    func taipeiStartsWithoutRemoteAccess() async throws {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/ChatGPT/Taipei").path
        let project = try await ProjectGit.discover(folder)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let work = try await ProjectGit.createWorkspace(project: project, id: UUID().uuidString, root: root)
        #expect(work.baseCommit == (try await ProjectCommand.git(folder, ["rev-parse", "main"])))
        _ = try await ProjectCommand.git(folder, ["worktree", "remove", work.folder])
        _ = try await ProjectCommand.git(folder, ["branch", "-d", work.branch])
        try? FileManager.default.removeItem(at: root)
    }
    @Test func oldWorkspaceDecodesAsManaged() throws {
        let workspace = ProjectWorkspace(id: "old", folder: "/old", branch: "main", baseCommit: "abc", context: .init())
        let data = try JSONEncoder().encode(workspace)
        #expect(try JSONDecoder().decode(ProjectWorkspace.self, from: data).isManagedWorktree)
    }
}
