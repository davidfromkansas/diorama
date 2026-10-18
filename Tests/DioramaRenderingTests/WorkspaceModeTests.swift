import AppKit
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct WorkspaceModeTests {
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

}
