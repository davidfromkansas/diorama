import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct LiveToolsTests {
    private func chef(_ id: String, _ name: String, tool: String, detail: String = "", at: Date, working: Bool = true) -> SpatialAgent {
        var value = WorkspaceAgent(id: id, name: name, provider: "Claude", task: "Task", action: "Working", status: working ? .working : .done,
                                   reportedStatus: "working", freshness: .live, observedAt: at)
        value.latestTool = tool; value.latestToolDetail = detail; value.lastToolAt = at
        return SpatialAgent(projectID: "p", conversationID: "c-" + id, value: value)
    }

    @Test func toolCallsNameTheirServerPluginOrSkill() {
        let github = LiveResources.resource(tool: "mcp__github__list_issues", detail: "")
        #expect(github?.id == "server:github" && github?.name == "GitHub" && github?.brand?.slug == "github")
        let vercel = LiveResources.resource(tool: "mcp__plugin_vercel_vercel__deploy", detail: "")
        #expect(vercel?.name == "Vercel" && vercel?.plugin == "vercel")
        #expect(LiveResources.resource(tool: "mcp__claude_ai_Slack__send", detail: "")?.name == "Slack")
        #expect(LiveResources.resource(tool: "mcp__postgres__query", detail: "")?.brand?.slug == "postgresql")
        #expect(LiveResources.resource(tool: "Skill", detail: "swift-testing")?.kind == .skill)
        #expect(LiveResources.resource(tool: "exec_command", detail: "cat ~/.codex/skills/pdf/SKILL.md")?.id == "skill:pdf")
        // Built-in tools are stations, and opaque connector ids can't be named.
        #expect(LiveResources.resource(tool: "Bash", detail: "npm test") == nil)
        #expect(LiveResources.resource(tool: "mcp__1a59c906-04da-521d-bda7-7f71b9f9e01c__batch", detail: "") == nil)
        #expect(LiveResources.resource(tool: "mcp__acme-internal__ping", detail: "")?.name == "Acme Internal")
    }

    @Test func codexMCPCallsCarryTheirServer() throws {
        let event: WireValue = .object(["method": .string("item/started"), "params": .object(["item": .object(["id": .string("i1"), "type": .string("mcpToolCall"), "server": .string("linear"), "tool": .string("create_issue")])])])
        var snapshot = SessionActivitySnapshot()
        SessionActivityReducer.ingest(event, provider: .codex, sessionID: "s", into: &snapshot)
        #expect((snapshot.records + snapshot.events).contains { $0.title == "mcp__linear__create_issue" })
    }

    @Test func newPicksGoToTheFrontAndTheCalmWindowBatchesThem() {
        let model = LiveToolsModel()
        let start = Date()
        model.observe([chef("a", "Sage", tool: "Read", at: start)], now: start)
        model.observe([chef("a", "Sage", tool: "mcp__github__get", at: start + 1)], now: start + 1)
        #expect(model.slots.map(\.id) == ["server:github"] && model.slots[0].users == ["Sage"])
        #expect(model.caption?.text == "called GitHub")
        // The chef who picked it up sends a spark to the bar, cleared once it lands.
        #expect(model.sparks.count == 1 && model.sparks[0].agentID.hasSuffix("1:a") && !model.sparks[0].skill)
        model.landed(model.sparks[0])
        #expect(model.sparks.isEmpty)
        // Inside the 1.5 s window a second pick waits, then lands in front.
        model.observe([chef("a", "Sage", tool: "mcp__github__get", at: start + 1), chef("b", "Eli", tool: "mcp__linear__list", at: start + 1.5)], now: start + 1.5)
        #expect(model.slots.first?.id == "server:github")
        model.flush(now: start + 3)
        #expect(model.slots.map(\.id) == ["server:linear", "server:github"])
    }

    @Test func reuseWithinTwentySecondsPulsesInPlaceAndThePointerHoldsTheOrder() {
        let model = LiveToolsModel()
        let start = Date()
        model.observe([chef("a", "Sage", tool: "Read", at: start)], now: start)
        model.observe([chef("a", "Sage", tool: "mcp__github__a", at: start + 1)], now: start + 1)
        model.observe([chef("a", "Sage", tool: "mcp__linear__a", at: start + 3)], now: start + 3)
        model.observe([chef("a", "Sage", tool: "mcp__github__b", at: start + 5)], now: start + 5)
        #expect(model.slots.map(\.id) == ["server:linear", "server:github"])
        #expect(model.slots[1].pulses == 1)
        model.frozen = true
        model.observe([chef("a", "Sage", tool: "mcp__slack__post", at: start + 8)], now: start + 8)
        #expect(model.slots.first?.id == "server:linear")
        model.frozen = false
        model.flush(now: start + 9)
        #expect(model.slots.first?.id == "server:slack")
    }

    @Test func idleToolsDropOutPastFiveAndSkillsFlipTheirOwnSlot() {
        let model = LiveToolsModel()
        var now = Date()
        model.observe([chef("a", "Sage", tool: "Read", at: now)], now: now)
        for server in ["one", "two", "three", "four", "five", "six"] {
            now += 2
            model.observe([chef("a", "Sage", tool: "mcp__\(server)__x", at: now)], now: now)
        }
        #expect(model.slots.count == 5 && model.slots.first?.id == "server:six" && !model.slots.contains { $0.id == "server:one" })
        now += 2
        model.observe([chef("a", "Sage", tool: "Skill", detail: "swift-testing", at: now)], now: now)
        #expect(model.skill?.resource.name == "swift-testing" && model.slots.count == 5)
        #expect(model.caption?.text == "used the swift-testing skill")
    }

    /// Opt-in render of the bar and the All palette's rows.
    @Test func captureLiveBar() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_UTILITY_CAPTURE"] == "1" else { return }
        let now = Date()
        let agents = [chef("a", "Sage", tool: "mcp__github__get", at: now), chef("b", "Eli", tool: "mcp__postgres__query", at: now),
                      chef("c", "Opal", tool: "mcp__plugin_vercel_vercel__deploy", at: now)]
        let view = VStack(spacing: 30) {
            LiveToolsBar(agents: agents, total: 64) {}
            HStack(spacing: 10) {
                ForEach(["GitHub", "Linear", "Slack", "Figma", "Sentry", "Notion", "Stripe", "Supabase", "Acme Internal", "Blender"], id: \.self) { BrandIcon(name: $0) }
            }
        }
        .padding(40).frame(width: 900).background(Color(red: 0.48, green: 0.31, blue: 0.2))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-live-bar.png"))
    }

    @Test func skillsFoldIntoNamespaceStacks() {
        func skill(_ name: String) -> AllResourcesPalette.Entry {
            .init(item: CapabilityLibraryItem(id: "s:" + name, name: name, kind: .skill, provider: .codex), providers: [.codex])
        }
        let groups = AllResourcesPalette.skillGroups(["vercel:auth", "vercel:ai-sdk", "pdf", "solo:one", "unity:a", "unity:b", "unity:c"].map(skill))
        #expect(groups.stacks.map(\.name) == ["vercel", "unity"] && groups.stacks[1].skills.count == 3)
        #expect(groups.loose.map(\.item.name) == ["pdf", "solo:one"])
    }

    /// Opt-in render of the All palette's grid with a realistic inventory.
    @Test func captureAllGrid() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_UTILITY_CAPTURE"] == "1" else { return }
        var items: [CapabilityLibraryItem] = []
        for (name, state) in [("GitHub", CapabilityAvailability.available), ("Linear", .available), ("Slack", .connectionNeeded), ("Figma", .available), ("Sentry", .unverified),
                              ("Postgres", .available), ("Notion", .available), ("Stripe", .disabled), ("Supabase", .available), ("arcade", .connectionNeeded), ("computer-use", .unverified),
                              ("cua_repl", .unverified), ("Blender", .available), ("Docker", .available), ("Cloudflare", .unverified), ("Google Calendar", .available)] {
            items.append(.init(id: "m:" + name, name: name, kind: .tool, provider: .codex, source: "MCP server", availability: state))
        }
        for name in ["Arcade", "ChatGPT Space", "Codex Document Control"] { items.append(.init(id: "a:" + name, name: name, kind: .app, provider: .codex, availability: .available)) }
        for name in ["pdf", "plugin-creator", "presentations", "sites", "spreadsheets", "unity", "visualize", "work-pets", "vercel", "figma", "github"] {
            items.append(.init(id: "p:" + name, name: name, kind: .plugin, provider: .codex, availability: .available))
        }
        for name in ["vercel:ai-sdk", "vercel:auth", "vercel:bootstrap", "vercel:deploy", "unity:scenes", "unity:shaders", "sf:asset-check", "sf:miniature-style",
                     "company-research", "img2threejs", "pdf", "docx", "swift-testing", "artifact-design"] {
            items.append(.init(id: "s:" + name, name: name, description: "Does " + name, kind: .skill, provider: .codex, availability: .available))
        }
        let snapshot = CapabilityLibrarySnapshot(context: .init(provider: .codex, folder: "/tmp"), items: items)
        let palette = AllResourcesPalette(library: LibraryModel(), folder: "/tmp", sessions: [:], armFor: ("c", "Sage"),
                                          claude: CapabilityLibrarySnapshot(context: .init(provider: .claude, folder: "/tmp")), codex: snapshot) {}
            .frame(width: 1000, height: 760).padding(20).background(Color(red: 0.48, green: 0.31, blue: 0.2))
        let host = NSHostingView(rootView: palette)
        host.frame = NSRect(x: 0, y: 0, width: 1040, height: 800)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-all-grid.png"))
    }
}
