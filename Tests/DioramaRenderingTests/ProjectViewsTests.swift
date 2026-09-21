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
