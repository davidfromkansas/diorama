import Foundation
import Testing
@testable import DioramaCore

struct ClaudeArchiveTests {
    private func sandbox() throws -> (ClaudeDesktopPaths, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-archive-\(UUID().uuidString)")
        let metadata = root.appendingPathComponent("claude-code-sessions/org/user")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        return (ClaudeDesktopPaths(metadata: root.appendingPathComponent("claude-code-sessions"), transcripts: root.appendingPathComponent("projects"),
                                   registry: root.appendingPathComponent("registry")), metadata)
    }

    @Test func desktopArchiveFlipsOnlyTheFlag() throws {
        let (paths, folder) = try sandbox()
        let id = "local_" + UUID().uuidString.lowercased()
        let original: [String: Any] = ["sessionId": id, "cliSessionId": UUID().uuidString.lowercased(), "cwd": "/tmp/project", "title": "Recipe scaler",
                                       "isArchived": false, "completedTurns": 3, "enabledMcpTools": ["a": true], "remoteMcpServersConfig": [] as [Any], "lastActivityAt": 1_791_406_242_000]
        let file = folder.appendingPathComponent(id + ".json")
        try JSONSerialization.data(withJSONObject: original).write(to: file)
        try ClaudeArchive(paths: paths, defaults: UserDefaults(suiteName: UUID().uuidString)!).setDesktopArchived(id, archived: true)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(saved["isArchived"] as? Bool == true)
        #expect(Set(saved.keys) == Set(original.keys))
        #expect(saved["title"] as? String == "Recipe scaler" && saved["completedTurns"] as? Int == 3 && saved["lastActivityAt"] as? Int == 1_791_406_242_000)
        #expect((saved["enabledMcpTools"] as? [String: Bool]) == ["a": true])
    }

    @Test func dioramaRemembersClaudeConversationsItArchived() throws {
        let (paths, _) = try sandbox()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let archive = ClaudeArchive(paths: paths, defaults: defaults)
        let cli = Session(id: "Claude Code:abc", provider: .claude, url: nil, sessionID: "abc", title: "CLI task", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        try archive.setArchived(cli, archived: true)
        #expect(archive.archivedIDs == ["Claude Code:abc"])
        try archive.setArchived(cli, archived: false)
        #expect(archive.archivedIDs.isEmpty)
        // A Desktop conversation whose file is gone can't be archived silently.
        var desktop = cli; desktop.desktopSessionID = "local_" + UUID().uuidString.lowercased()
        #expect(throws: (any Error).self) { try archive.setArchived(desktop, archived: true) }
    }
}
