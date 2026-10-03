import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ProjectViewsTests {
    @Test func plainFolderDetailRendersWithoutGitControls() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let project = DioramaProject(name: "Local notes", folder: root.path, commonDirectory: "", base: "", remote: nil)
        projects.projects = [project]
        let library = LibraryModel(projects: projects)
        for width in [800, 1200] {
            let view = ProjectDetailView(projectID: project.id, projects: projects, library: library)
                .frame(width: CGFloat(width), height: 700)
            let host = NSHostingView(rootView: view)
            host.frame.size = CGSize(width: width, height: 700); host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/diorama-plain-folder-\(width).png"))
        }
    }
    @Test func plainProjectsPersistSeparatelyAndAssociateExternalSessions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("one/project"), secondURL = root.appendingPathComponent("two/project")
        for url in [firstURL, secondURL] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let first = try await ProjectFolder.open(firstURL.path), second = try await ProjectFolder.open(secondURL.path)
        let storage = root.appendingPathComponent("projects.json")
        let model = ProjectModel(storageURL: storage)
        model.add(first); model.add(second); model.add(try await ProjectFolder.open(firstURL.path))
        #expect(model.projects.count == 2)
        #expect(model.selectedID == first.id)
        let session = Session(id: "Claude:plain", provider: .claude, url: nil, sessionID: "plain", title: "External", project: firstURL.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        let library = LibraryModel(projects: model)
        library.sessions = [session]
        #expect(model.sessions(first, library: library).map(\.id) == [session.id])
        #expect(model.sessions(second, library: library).isEmpty)
        model.update(first.id) { $0.selectedSession = session.id; $0.draft = "Keep draft" }
        let restored = ProjectModel(storageURL: storage)
        #expect(restored.projects.count == 2)
        #expect(restored.projects.first?.isGitBacked == false)
        // Shared project storage does not own a window's selection. Restore its
        // separately persisted presentation snapshot before asserting selection.
        #expect(restored.projects.first?.selectedSession == nil)
        let savedSelection = try JSONEncoder().encode(try #require(model.presentation[first.id]))
        restored.presentation[first.id] = try JSONDecoder().decode(ProjectViewSelection.self, from: savedSelection)
        #expect(restored.projects.first?.selectedSession == session.id)
        #expect(restored.projects.first?.draft == "Keep draft")
        await #expect(throws: (any Error).self) { try await restored.prepare(projectID: first.id, base: "", cached: false) }
        #expect(restored.projects.first?.workspaces.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: firstURL.appendingPathComponent(".git").path))
    }
    @Test func contextViewIsReadableInBothAppearances() throws {
        let model = ProjectModel(storageURL: URL(fileURLWithPath: "/tmp/absent-project-fixture-" + UUID().uuidString))
        var p = DioramaProject(name: "Diorama", folder: "/Projects/Diorama", commonDirectory: "/Projects/Diorama/.git", base: "origin/main", remote: "https://github.com/example/diorama")
        p.context.instructions = "Use the existing components. Keep navigation simple. Run relevant tests before finishing."
        p.context.references = ["docs/product-spec.md", "https://example.com/design"]
        model.projects = [p]
        for dark in [true, false] {
            let view = ProjectContextView(projectID: p.id, projects: model)
                .frame(width: 800, height: 780).background(dark ? Color(white: 0.12) : .white)
                .environment(\.colorScheme, dark ? .dark : .light)
            let host = NSHostingView(rootView: view)
            host.frame.size = CGSize(width: 800, height: 780); host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/diorama-project-context-\(dark ? "dark" : "light").png"))
        }
    }
    @Test func explicitProjectsDeduplicateAndRetainNavigation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects.json")
        let model = ProjectModel(storageURL: file)
        let p = DioramaProject(name: "Project", folder: "/repo", commonDirectory: "/repo/.git", base: "main", remote: nil)
        model.add(p)
        var linked = p; linked.id = UUID().uuidString; linked.folder = "/different-worktree"
        model.add(linked)
        #expect(model.projects.count == 1)
        model.update(p.id) { $0.section = "Context"; $0.draft = "Keep this draft" }
        let reloaded = ProjectModel(storageURL: file)
        #expect(reloaded.projects.first?.section == "Sessions")
        let savedSelection = try JSONEncoder().encode(try #require(model.presentation[p.id]))
        reloaded.presentation[p.id] = try JSONDecoder().decode(ProjectViewSelection.self, from: savedSelection)
        #expect(reloaded.projects.first?.section == "Context")
        #expect(reloaded.projects.first?.draft == "Keep this draft")
        model.projects.removeAll(); model.save()
        #expect(try ProjectStorage.load(from: file).isEmpty)
    }
}

extension ProjectViewsTests {
    @Test func localPreparationRetriesRetainLocationAndDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await ProjectCommand.git(root.path, ["init", "-b", "main"])
        _ = try await ProjectCommand.git(root.path, ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-m", "Seed"])
        let storage = root.appendingPathComponent("projects.json")
        let projects = ProjectModel(storageURL: storage)
        var project = try await ProjectGit.discover(root.path)
        project.draft = "Keep my message"
        project.draftStart = SessionStartOptions(folder: root.path, reference: "main", createWorktree: false)
        projects.projects = [project]
        let first = try await projects.prepare(projectID: project.id, base: "main", cached: true, options: project.draftStart)
        let restored = ProjectModel(storageURL: storage)
        let retry = try await restored.prepare(projectID: project.id, base: "missing", cached: true,
            options: SessionStartOptions(folder: "/missing", reference: "missing"))
        #expect(first == retry)
        #expect(restored.projects.first?.draft == "Keep my message")
        #expect(restored.projects.first?.workspaces.count == 1)
        #expect(restored.projects.first?.fetchedAt == nil)
    }
    @Test func newConversationControlsRenderAtNarrowWidth() throws {
        let projects = ProjectModel(storageURL: URL(fileURLWithPath: "/private/tmp/absent-" + UUID().uuidString))
        var project = DioramaProject(name: "Example", folder: "/Projects/Example", commonDirectory: "/Projects/Example/.git", base: "origin/main", remote: nil)
        project.draftStart = SessionStartOptions(folder: project.folder, reference: "main")
        projects.projects = [project]
        let library = LibraryModel(projects: projects)
        let view = ProjectDraftView(projectID: project.id, projects: projects, library: library)
            .frame(width: 760, height: 520).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame.size = CGSize(width: 760, height: 520); host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/diorama-local-start.png"))
    }
}
