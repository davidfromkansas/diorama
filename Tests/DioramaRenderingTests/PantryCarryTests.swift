import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct PantryCarryTests {
    private func agent(tool: String, detail: String = "") -> WorkspaceAgent {
        var value = WorkspaceAgent(id: "main", name: "Sage", provider: "Claude", task: "Task", action: "Working", status: .working,
                                   reportedStatus: "working", freshness: .live, observedAt: Date())
        value.latestTool = tool; value.latestToolDetail = detail
        return value
    }

    @Test func eachKindOfPantryVisitCarriesItsOwnThing() {
        #expect(PantryCarry.item(for: agent(tool: "Skill", detail: "swift-testing")) == .init(kind: .skill, name: "swift-testing"))
        #expect(PantryCarry.item(for: agent(tool: "exec_command", detail: "cat ~/.codex/skills/pdf/SKILL.md")) == .init(kind: .skill, name: "pdf"))
        #expect(PantryCarry.item(for: agent(tool: "mcp__github__list_issues")) == .init(kind: .connector, name: "GitHub"))
        #expect(PantryCarry.item(for: agent(tool: "mcp__plugin_vercel_vercel__deploy")) == .init(kind: .plugin, name: "Vercel"))
        #expect(PantryCarry.item(for: agent(tool: "Skill", detail: "vercel:deploy")) == .init(kind: .plugin, name: "Vercel"))
        #expect(PantryCarry.item(for: agent(tool: "exec_command", detail: "sed -n 1,80p ~/.codex/plugins/cache/openai-curated-remote/vercel/0.54.1/skills/domains/SKILL.md")) == .init(kind: .plugin, name: "Vercel"))
        #expect(PantryCarry.item(for: agent(tool: "Read", detail: "/Users/me/.claude/plugins/cache/claude-plugins-official/vercel/0.50.0/skills/vercel-agent/SKILL.md")) == .init(kind: .plugin, name: "Vercel"))
        // Codex code mode fetches skills as MCP resources; a plugin's comes in its crate.
        #expect(PantryCarry.item(for: agent(tool: "read_mcp_resource", detail: "skill://plugin_connector_690a/domains")) == .init(kind: .plugin, name: "domains"))
        #expect(PantryCarry.item(for: agent(tool: "read_mcp_resource", detail: "skill://pdf")) == .init(kind: .skill, name: "pdf"))
        var owed = agent(tool: "web__run"); owed.turnWork.started(tool: "read_mcp_resource", detail: "skill://plugin_connector_690a/domains", call: "c")
        #expect(PantryCarry.item(for: owed) == .init(kind: .plugin, name: "domains"))
        #expect(PantryCarry.item(for: agent(tool: "Bash", detail: "npm test")) == nil)
    }

    /// From the real two-agent replay (Codex code mode and Claude Code on the same plugin task).
    @Test func realSessionsCarryThePluginNotTheirPlumbing() {
        // Listing resources is browsing: nothing to carry.
        #expect(PantryCarry.item(for: agent(tool: "list_mcp_resources")) == nil)
        #expect(PantryCarry.item(for: agent(tool: "mcp__codex__list_mcp_resource_templates")) == nil)
        // After the read, a web search: the turn's skill URI wins over its plumbing entries.
        var codex = agent(tool: "webSearch")
        for (tool, detail) in [("list_mcp_resources", ""), ("mcp__codex_apps__read_mcp_resource", ""), ("read_mcp_resource", "skill://plugin_connector_690a/domains")] {
            codex.turnWork.started(tool: tool, detail: detail, call: nil)
        }
        #expect(PantryCarry.item(for: codex)?.kind == .plugin)
        // Codex app connectors are named by the app.
        #expect(PantryCarry.item(for: agent(tool: "mcp__codex_apps__github_search_repositories")) == .init(kind: .connector, name: "GitHub"))
        // Claude's Skill call is remembered by the skill it named, so the owed visit carries it too.
        var claude = agent(tool: "Read", detail: "/Users/me/.claude/plugins/cache/claude-plugins-official/vercel/0.50.0/skills/vercel-cli/references/domains-and-dns.md")
        claude.turnWork.started(tool: "Skill", detail: "vercel:vercel-cli", call: nil)
        #expect(claude.turnWork.resources == ["vercel:vercel-cli"])
        #expect(PantryCarry.item(for: claude) == .init(kind: .plugin, name: "Vercel"))
        // Codex reading the plugin's SKILL.md with cat, then searching: still the plugin's crate.
        var cat = agent(tool: "webSearch")
        cat.turnWork.started(tool: "exec_command", detail: "cat /Users/me/.codex/plugins/cache/openai-curated-remote/vercel/0.54.1/skills/domains/SKILL.md", call: nil)
        #expect(cat.turnWork.resources == ["vercel:domains"])
        #expect(PantryCarry.item(for: cat) == .init(kind: .plugin, name: "Vercel"))
    }

    @Test func itWaitsOnTheCounterIsCarriedAwayThenSetDownAndFades() {
        let carrier = PantryCarrier(models: [.skill: SCNNode(), .plugin: SCNNode(), .connector: SCNNode()])
        let floor = SCNNode(), socket = SCNNode()
        let skill = PantryCarry.Item(kind: .skill, name: "pdf")
        func tick(_ wanted: PantryCarry.Item?, _ area: String?, _ delta: Float = 0.1) {
            carrier.sync(wanted: wanted, area: area, reducedMotion: false, delta: delta, carrySocket: socket, fit: nil, floor: floor, counterTop: 0.9)
        }
        tick(skill, "pantry")
        #expect(carrier.placement == .counter && carrier.carrying && carrier.node?.parent === floor)
        tick(skill, nil)
        #expect(carrier.placement == .carried && carrier.node?.parent === socket)
        tick(nil, "cooking")
        #expect(carrier.placement == .setDown && !carrier.carrying && carrier.node?.parent === floor)
        for _ in 0..<50 { tick(nil, "cooking") }
        #expect(carrier.placement == .none && carrier.node == nil)
        // A new visit for another thing replaces it; nothing to fetch, nothing spawned.
        tick(skill, "pantry"); tick(.init(kind: .connector, name: "GitHub"), "pantry")
        #expect(carrier.item?.kind == .connector)
        carrier.clear(); tick(nil, "pantry")
        #expect(carrier.placement == .none)
    }

    @Test func reducedMotionSetsItDownWithoutTheFade() {
        let carrier = PantryCarrier(models: [.skill: SCNNode()])
        let floor = SCNNode()
        carrier.sync(wanted: .init(kind: .skill, name: "pdf"), area: "pantry", reducedMotion: true, delta: 0.1, carrySocket: nil, fit: nil, floor: floor, counterTop: 0.9)
        carrier.sync(wanted: nil, area: nil, reducedMotion: true, delta: 0.1, carrySocket: nil, fit: nil, floor: floor, counterTop: 0.9)
        carrier.sync(wanted: nil, area: "prep", reducedMotion: true, delta: 0.1, carrySocket: nil, fit: nil, floor: floor, counterTop: 0.9)
        #expect(carrier.placement == .none)
    }

    @Test func theModelsAreBundled() {
        #expect(PantryCarry.models.count == 3)
    }
}
