import Foundation
import Testing
@testable import DioramaCore

struct ProviderPermissionDefaultsTests {
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("defaults-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        return url
    }

    @Test func codexReadsTheSameKeysTheCodexAppWrites() throws {
        let home = try home(), files = ProviderPermissionDefaults(home: home)
        #expect(files.choice(for: .codex) == .user) // Nothing set: Codex's built-in default.
        #expect(!files.isSet(for: .codex))
        try "model = \"gpt\"\napprovals_reviewer = \"auto_review\"\n\n[desktop]\nfollowUpQueueMode = \"queue\"\n".write(to: files.codexConfig, atomically: true, encoding: .utf8)
        #expect(files.choice(for: .codex) == .autoReview)
        try "approval_policy = \"never\" # yolo\nsandbox_mode = 'danger-full-access'\n".write(to: files.codexConfig, atomically: true, encoding: .utf8)
        #expect(files.choice(for: .codex) == .fullAccess)
        try "default_permissions = \"team\"\n".write(to: files.codexConfig, atomically: true, encoding: .utf8)
        #expect(files.choice(for: .codex) == nil) // A custom profile isn't one of Diorama's presets.
    }

    @Test func codexDefaultChangesOnlyItsTopLevelKeys() throws {
        let home = try home(), files = ProviderPermissionDefaults(home: home)
        let original = "# my config\nmodel = \"gpt\"\napprovals_reviewer = \"auto_review\"\n\n[desktop]\napproval_policy = \"untouched\"\nfollowUpQueueMode = \"queue\"\n"
        try original.write(to: files.codexConfig, atomically: true, encoding: .utf8)
        try files.set(.fullAccess, for: .codex)
        let written = try String(contentsOf: files.codexConfig, encoding: .utf8)
        #expect(written == "# my config\nmodel = \"gpt\"\napproval_policy = \"never\"\nsandbox_mode = \"danger-full-access\"\n\n[desktop]\napproval_policy = \"untouched\"\nfollowUpQueueMode = \"queue\"\n")
        #expect(files.choice(for: .codex) == .fullAccess)
        try files.set(.autoReview, for: .codex)
        #expect(files.choice(for: .codex) == .autoReview)
        #expect(try String(contentsOf: files.codexConfig, encoding: .utf8).contains("[desktop]\napproval_policy = \"untouched\""))
        #expect(throws: (any Error).self) { try files.set(.acceptEdits, for: .codex) }
    }

    @Test func claudeDefaultKeepsTheRestOfSettings() throws {
        let home = try home(), files = ProviderPermissionDefaults(home: home)
        #expect(files.choice(for: .claude) == nil)
        try #"{"model": "opus", "permissions": {"allow": ["Bash(ls:*)"]}}"#.write(to: files.claudeSettings, atomically: true, encoding: .utf8)
        try files.set(.acceptEdits, for: .claude)
        #expect(files.choice(for: .claude) == .acceptEdits)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: files.claudeSettings)) as! [String: Any]
        #expect(json["model"] as? String == "opus")
        #expect((json["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
        // The original is kept once, since rewriting reformats the file.
        #expect(FileManager.default.fileExists(atPath: files.claudeSettings.appendingPathExtension("diorama-backup").path))
        try files.set(.fullAccess, for: .claude)
        #expect(files.choice(for: .claude) == .fullAccess)
    }
}
