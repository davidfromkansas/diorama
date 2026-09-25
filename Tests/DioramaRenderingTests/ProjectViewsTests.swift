import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ProjectViewsTests {
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
