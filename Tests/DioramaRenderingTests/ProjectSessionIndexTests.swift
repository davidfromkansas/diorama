import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ProjectSessionIndexTests {
    @Test func membershipPreservesOrderAndRefreshesMetadataAndAssociations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("alias")
        let folder = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let library = LibraryModel(execution: ExecutionController(transport: MessagesFixtureTransport()), projects: projects)
        let project = DioramaProject(name: "Repo", folder: folder.path, commonDirectory: folder.appendingPathComponent(".git").path, base: "main", remote: nil)
        let paths = [folder.path, root.appendingPathComponent("worktree").path, alias.path, root.appendingPathComponent("other").path]
        library.sessions = paths.enumerated().map { index, path in
            Session(id: "Codex:\(index)", provider: .codex, url: nil, sessionID: String(index), title: "Original", project: path, modified: .distantPast, bytes: 0, archived: false, parentID: nil)
        }
        #expect(projects.sessions(project, library: library).map(\.sessionID) == ["0", "2"])
        projects.associations[paths[1]] = project.commonDirectory
        #expect(projects.sessions(project, library: library).map(\.sessionID) == ["0", "1", "2"])
        library.sessions[0] = library.sessions[0].updated(title: "Updated")
        #expect(projects.sessions(project, library: library).first?.title == "Updated")
        library.sessions.remove(at: 0)
        #expect(projects.sessions(project, library: library).map(\.sessionID) == ["1", "2"])
        projects.associations.removeValue(forKey: paths[1])
        #expect(projects.sessions(project, library: library).map(\.sessionID) == ["2"])
    }

    @Test func largeRosterRepeatedProjectLookupsStayWithinFrameBudget() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let library = LibraryModel(execution: ExecutionController(transport: MessagesFixtureTransport()), projects: projects)
        let folders = (0..<40).map { root.appendingPathComponent("project-\($0)").path }
        library.sessions = (0..<6000).map { index in
            Session(id: "Codex:\(index)", provider: .codex, url: nil, sessionID: String(index), title: "History", project: folders[index % folders.count], modified: .distantPast, bytes: 0, archived: false, parentID: nil)
        }
        let tabs = folders.prefix(8).map { DioramaProject(name: "Tab", folder: $0, commonDirectory: $0 + "/.git", base: "main", remote: nil) }
        let cold = ContinuousClock().measure { for tab in tabs { #expect(projects.sessions(tab, library: library).count == 150) } }
        let warm = ContinuousClock().measure { for _ in 0..<100 { for tab in tabs { _ = projects.sessions(tab, library: library) } } }
        print("Project roster lookup: cold eight tabs \(cold); 800 cached lookups \(warm)")
        #expect(warm < .milliseconds(100), "Cached lookup must not repeat filesystem or roster scans while scrolling")
    }
}
