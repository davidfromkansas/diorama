import Foundation
import Testing
@testable import DioramaCore
@testable import DioramaApp

@MainActor struct ConversationOrganizationTests {
    @Test func newlyCreatedTaskUsesTheSameNormalizedFolderAsTheSidebar() {
        let model = LibraryModel()
        model.execution.tasks["new-task"] = ExecutedTask(id: "new-task", title: "Test", folder: "/private/tmp/Diorama-Acceptance-UI", attached: true)
        model.selectOwned("new-task")
        let selected = model.selectedID
        #expect(model.selectedFolder != nil)
        model.reconcileSelection()
        #expect(model.selectedID == selected)
        #expect(model.selected?.sessionID == "new-task")
    }
    @Test func pinSurvivesModelRecreationAndCanBeRemoved() {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "pinnedConversations")
        defer {
            if let old { defaults.set(old, forKey: "pinnedConversations") }
            else { defaults.removeObject(forKey: "pinnedConversations") }
        }
        let id = "acceptance-" + UUID().uuidString
        let session = Session(id: id, provider: .codex, url: URL(fileURLWithPath: "/tmp/acceptance.jsonl"), sessionID: id, title: "Disposable pin", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let model = LibraryModel()
        model.togglePin(session)
        let restored = LibraryModel()
        #expect(restored.pinned.contains(id))
        restored.togglePin(session)
        #expect(!LibraryModel().pinned.contains(id))
        #expect(Set(defaults.stringArray(forKey: "pinnedConversations") ?? []) == Set(old as? [String] ?? []))
    }
}
