import Foundation
import Testing
@testable import DioramaCore
@testable import DioramaApp

@MainActor struct ComposerDraftModeTests {
    @Test func editingDraftPreservesExplicitPlanModeAndLegacyDraftDecodes() throws {
        let previous = UserDefaults.standard.data(forKey: "conversationDrafts")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "conversationDrafts") }
            else { UserDefaults.standard.removeObject(forKey: "conversationDrafts") }
        }
        let model = LibraryModel()
        let id = "test-" + UUID().uuidString
        model.saveDraft(id, text: "", attachments: [], mode: "plan")
        model.saveDraft(id, text: "Keep planning", attachments: [])
        #expect(model.drafts[id]?.mode == "plan")
        let data = try #require(UserDefaults.standard.data(forKey: "conversationDrafts"))
        let restored = try JSONDecoder().decode([String: ConversationDraft].self, from: data)
        #expect(restored[id]?.mode == "plan")
        #expect(restored[id]?.text == "Keep planning")
        let legacy = try JSONDecoder().decode(ConversationDraft.self, from: Data(#"{"text":"old draft","attachments":[]}"#.utf8))
        #expect(legacy.mode == nil)
    }
}
