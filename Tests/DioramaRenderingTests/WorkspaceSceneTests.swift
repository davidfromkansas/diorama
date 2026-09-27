import AppKit
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct WorkspaceSceneTests {
    @Test func sceneHasFiniteGroundAndBoundedCamera() throws {
        let view = WorkspaceSceneNSView()
        #expect(view.scene?.rootNode.childNodes.filter { $0.name == "grid" }.count == 42)
        let ground = try #require(view.scene?.rootNode.childNode(withName: "ground", recursively: false)?.geometry as? SCNBox)
        #expect(ground.width == 20 && ground.length == 20)
        #expect(view.pointOfView?.camera?.usesOrthographicProjection == true)
        view.orbit(dx: 100, dy: -10000)
        #expect(view.elevation >= 25 * .pi / 180)
        view.orbit(dx: 0, dy: 10000)
        #expect(view.elevation <= 55 * .pi / 180)
        view.zoom(delta: -10000)
        #expect(view.distance == 16)
        view.zoom(delta: 10000)
        #expect(view.distance == 80)
        view.resetCamera()
        #expect(view.distance == 38 && view.yaw == .pi / 4)
        #expect(view.elevation == .pi / 6)
        #expect(!view.rendersContinuously && !view.isPlaying)
    }


    @Test func orbitKeepsWorldVerticalUprightAndResetRestoresOrientation() throws {
        let view = WorkspaceSceneNSView()
        let camera = try #require(view.pointOfView)
        let original = camera.simdTransform
        for step in 0..<100 {
            view.orbit(dx: 13, dy: step.isMultiple(of: 2) ? 8 : -5)
            // A level camera has no vertical component in its screen-right vector.
            #expect(abs(camera.worldRight.y) < 0.0001)
        }
        view.resetCamera()
        for column in 0..<4 {
            for row in 0..<4 {
                #expect(abs(camera.simdTransform[column][row] - original[column][row]) < 0.00001)
            }
        }
        for (name, dy) in [("low", -10000.0), ("high", 10000.0)] {
            view.resetCamera()
            view.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
            view.orbit(dx: 0, dy: dy)
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/diorama-grid-\(name).png"))
        }
    }

    @Test func navigationResetsSavedTabsButExplicitActionsStillWin() throws {
        _ = NSApplication.shared
        let storage = UserDefaults(suiteName: UUID().uuidString)!
        let navigation = WorkspaceNavigation(defaults: storage)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let project = DioramaProject(name: "Test", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        projects.projects = [project]
        let model = LibraryModel(projects: projects, navigation: navigation)
        let key = project.id + ":session"
        navigation.tabs[key] = .html
        model.navigate(.project(project.id, "session"))
        #expect(navigation.tabs[key] == .workspace)
        model.focusWorkspaceComposer()
        #expect(navigation.tabs[key] == .conversation)
        model.navigate(.project(project.id, nil))
        #expect(navigation.tabs[project.id + ":draft"] == .workspace)
        model.viewMode = .activity
        model.navigate(.imported("imported"))
        #expect(model.viewMode == .workspace)
        let session = Session(id: "Codex:offline", provider: .codex, url: nil, sessionID: "offline", title: "Offline", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        model.openAttention(session)
        #expect(model.viewMode == .activity)
        navigation.flushPersistence()
        let restored = WorkspaceNavigation(defaults: storage)
        #expect(restored.tabs[key] == .conversation)
        #expect(Array(ConversationViewMode.allCases.prefix(2)) == [.workspace, .conversation])
    }

    @Test func sceneRendersAtSupportedSizes() throws {
        for width in [380, 760, 1100] {
            let view = WorkspaceSceneNSView()
            view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
            let image = view.snapshot()
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/diorama-grid-\(width).png"))
            #expect(image.size.width == CGFloat(width))
        }
    }
}
