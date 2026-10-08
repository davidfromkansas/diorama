import Foundation
import Testing
@testable import DioramaCore

private actor LibraryTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    var methods: [String] = []
    func connect() {}
    func request(_ method: String, _ params: WireValue) throws -> WireValue {
        methods.append(method)
        switch method {
        case "skills/list": return .object(["data": .array([.object(["skills": .array([
            .object(["path": .string("/a/SKILL.md"), "name": .string("Design"), "enabled": .bool(true)]),
            .object(["path": .string("/b/SKILL.md"), "name": .string("Design"), "enabled": .bool(false)])
        ])])])])
        case "app/installed": throw AppServerFailure("Offline")
        case "mcpServerStatus/list": return .object(["data": .array([.object(["name": .string("Research"), "authStatus": .string("notLoggedIn")])])])
        default: return .object([:])
        }
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}
@MainActor struct CapabilityLibraryTests {
    @Test func codexPreservesSuccessfulSectionsAndDoesNotMutatePicker() async {
        let transport = LibraryTransport(); let controller = ExecutionController(transport: transport)
        controller.skills = [.string("composer selection")]
        let snapshot = await controller.capabilityLibrary(.init(provider: .codex, folder: "/tmp"))
        #expect(snapshot.items.filter { $0.name == "Design" }.count == 2)
        #expect(snapshot.items.filter { $0.availability == .available }.count == 1)
        #expect(snapshot.items.contains { $0.name == "Research" && $0.availability == .connectionNeeded })
        #expect(snapshot.errors["Apps"] == "Offline")
        #expect(controller.skills == [.string("composer selection")])
        #expect(await transport.methods == ["skills/list", "app/installed", "mcpServerStatus/list"])
    }
    @Test func unboundClaudeDoesNotContactOrStartRuntime() async throws {
        let transport = LibraryTransport(); let controller = ExecutionController(transport: transport)
        _ = await controller.capabilityLibrary(.init(provider: .claude, folder: "/tmp"))
        #expect(await transport.methods.isEmpty)
        let routed = AgentExecutionTransport(codex: transport)
        _ = try await routed.request("diorama/capabilities", .object(["threadId": .string("unknown"), "dioramaProvider": .string("Claude Code")]))
        #expect(await transport.methods.isEmpty)
    }
    @Test func localClaudeRespectsProjectScopeAndDisabledPlugins() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        func write(_ relative: String, _ text: String) throws {
            let url = home.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(".claude/settings.json", #"{"enabledPlugins":{"design@market":false}}"#)
        try write(".claude/skills/research/SKILL.md", "---\nname: Research\ndescription: >\n  Finds useful sources\n  for your work.\n---\n")
        try write("plugin/.claude-plugin/plugin.json", #"{"name":"design","description":"Design toolkit"}"#)
        try write("plugin/skills/draw/SKILL.md", "---\nname: draw\ndescription: Draws\n---")
        let registry: WireValue = .object(["plugins": .object([
            "design@market": .array([.object(["scope": .string("user"), "installPath": .string(home.appendingPathComponent("plugin").path)])]),
            "other@market": .array([.object(["scope": .string("project"), "projectPath": .string("/unrelated"), "installPath": .string("/unrelated/plugin")])])])])
        try write(".claude/plugins/installed_plugins.json", registry.pretty)
        let snapshot = CapabilityLibraryFiles.claude(context: .init(provider: .claude, folder: home.appendingPathComponent("project").path), home: home)
        #expect(snapshot.errors.isEmpty)
        #expect(snapshot.items.count == 3)
        #expect(snapshot.items.first { $0.name == "Research" }?.description == "Finds useful sources for your work.")
        let skill = try #require(snapshot.items.first { $0.name == "design:draw" })
        #expect(skill.availability == .disabled)
        #expect(skill.pluginID == snapshot.items.first { $0.kind == .plugin }?.id)
        #expect(skill.coverIndex == snapshot.items.first { $0.kind == .plugin }?.coverIndex)
    }
    @Test func runtimeDoesNotTurnBuiltinsOrAmbiguousNamesIntoVerifiedSkills() {
        var snapshot = CapabilityLibrarySnapshot(context: .init(provider: .claude, folder: "/tmp"), items: [
            .init(id: "1", name: "design", kind: .skill, provider: .claude),
            .init(id: "2", name: "design", kind: .skill, provider: .claude)
        ])
        ExecutionController.mergeClaude(.object(["commands": .array([
            .object(["name": .string("design")]), .object(["name": .string("help"), "builtin": .bool(true)]),
            .object(["name": .string("unknown-command")])
        ]), "servers": .array([.object(["name": .string("art"), "status": .string("connected"), "tools": .array([.object(["name": .string("paint")])])])])]), into: &snapshot)
        #expect(snapshot.items.filter { $0.kind == .skill }.allSatisfy { $0.availability == .unverified })
        #expect(!snapshot.items.contains { $0.name == "help" || $0.name == "unknown-command" })
        #expect(snapshot.items.contains { $0.name == "paint" && $0.availability == .available })
    }
    @Test func codexConfigurationRequiresEvidenceAndLinksDeclaredApps() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        func write(_ relative: String, _ text: String) throws {
            let file = home.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        try write("config.toml", "[plugins.\"art@market\"]\nenabled = false # previously true\n")
        try write("plugins/cache/market/art/1/.codex-plugin/plugin.json", #"{"name":"art","apps":"./.app.json"}"#)
        try write("plugins/cache/market/art/1/.app.json", #"{"apps":{"studio":{"id":"app-1"}}}"#)
        try write("plugins/cache/market/uninstalled/1/.codex-plugin/plugin.json", #"{"name":"uninstalled"}"#)
        var snapshot = CapabilityLibraryFiles.codex(context: .init(provider: .codex, folder: home.path), home: home)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items.first?.availability == .disabled)
        snapshot.items.append(.init(id: "app", name: "Studio", kind: .app, provider: .codex, source: "app://app-1"))
        CapabilityLibraryFiles.linkPluginMembers(&snapshot)
        #expect(snapshot.items.last?.pluginID == snapshot.items.first?.id)
    }
    @Test func stableIdentityNormalizationAndFreshness() {
        let item = CapabilityLibraryItem(id: "a", name: "A", kind: .skill, provider: .codex)
        var snapshot = CapabilityLibrarySnapshot(context: .init(provider: .codex, folder: "/tmp"), items: [item, item])
        snapshot.normalize(); #expect(snapshot.items.count == 1); #expect(snapshot.isFresh)
        snapshot.loadedAt = Date().addingTimeInterval(-61); #expect(!snapshot.isFresh)
        snapshot.loadedAt = Date(); snapshot.errors["Skills"] = "Failed"; #expect(!snapshot.isFresh)
        #expect((0..<5).contains(item.coverIndex))
    }

    @Test func codexSkillsOnDiskFillInWhenTheRuntimeCannotListThem() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-home-" + UUID().uuidString)
        let skill = home.appendingPathComponent("skills/release")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("skills/.system/hidden"), withIntermediateDirectories: true)
        try "---\nname: release\ndescription: Ship a release.\n---\nBody".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: home) }
        let snapshot = CapabilityLibraryFiles.codexSkills(context: .init(provider: .codex, folder: "/nonexistent"), home: home)
        #expect(snapshot.items.map(\.name) == ["release"])
        #expect(snapshot.items.first?.provider == .codex && snapshot.items.first?.kind == .skill && snapshot.items.first?.description == "Ship a release.")
    }
}
