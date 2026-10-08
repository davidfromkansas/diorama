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
            carrier.sync(wanted: wanted.map { ["pantry": $0] } ?? [:], area: area, reducedMotion: false, delta: delta, carrySocket: socket, fit: nil, floor: floor, counterTop: 0.9)
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
        carrier.sync(wanted: ["pantry": .init(kind: .skill, name: "pdf")], area: "pantry", reducedMotion: true, delta: 0.1, carrySocket: nil, fit: nil, floor: floor, counterTop: 0.9)
        carrier.sync(wanted: [:], area: nil, reducedMotion: true, delta: 0.1, carrySocket: nil, fit: nil, floor: floor, counterTop: 0.9)
        carrier.sync(wanted: [:], area: "stove", reducedMotion: true, delta: 0.1, carrySocket: nil, fit: nil, floor: floor, counterTop: 0.9)
        #expect(carrier.placement == .none)
    }

    @Test func theModelsAreBundled() {
        #expect(PantryCarry.models.count == 4)
    }

    @Test func thePlateCarriesTheStepTheAgentIsStarting() {
        func plan(_ statuses: [String]) -> AgentPlan {
            var snapshot = SessionActivitySnapshot()
            snapshot.records = statuses.enumerated().map { index, status in
                SessionActivityRecord(id: "s\(index)", provider: "Codex", sessionID: "s", turnID: "t", nativeID: "s\(index)", kind: "step",
                                      title: "Step \(index)", status: status, detail: "", source: "test", observedAt: Date(), data: .null)
            }
            return AgentPlan.reported(in: snapshot, provider: "Codex", sessionID: "s", currentTurn: "t")
        }
        var working = agent(tool: "update_plan"); working.plan = plan(["completed", "in_progress", "pending"])
        #expect(PantryCarry.planItem(for: working) == .init(kind: .plan, name: "Step 1"))
        var next = agent(tool: "update_plan"); next.plan = plan(["completed", "pending"])
        #expect(PantryCarry.planItem(for: next).name == "Step 1")
        // Nothing specific yet: the task's short title.
        #expect(PantryCarry.planItem(for: agent(tool: "")).name == TaskTitle.compact("Task"))
        #expect(AgentSidebar.phrase(agent(tool: "webSearch")) == "Researching online…")
        // No list: what it's doing.
        #expect(PantryCarry.planItem(for: agent(tool: "Read", detail: "SettingsView.swift")).name == AgentSidebar.phrase(agent(tool: "Read", detail: "SettingsView.swift")))
    }

    @Test func fromPrepThePlateIsCarriedAndSetDownWhereverTheChefGoesNext() {
        let carrier = PantryCarrier(models: [.skill: SCNNode(), .plan: SCNNode()])
        let floor = SCNNode(), socket = SCNNode()
        let plate = PantryCarry.Item(kind: .plan, name: "Wire up the toggles")
        func tick(_ wanted: [String: PantryCarry.Item], _ area: String?) {
            carrier.sync(wanted: wanted, area: area, reducedMotion: false, delta: 0.1, carrySocket: socket, fit: nil, floor: floor, counterTop: 0.9)
        }
        tick(["prep": plate], "prep")
        #expect(carrier.placement == .counter && carrier.item == plate && carrier.origin == "prep")
        // The plan moves on while it's still at prep: same plate, new step.
        tick(["prep": .init(kind: .plan, name: "Run the tests")], "prep")
        #expect(carrier.item?.name == "Run the tests" && carrier.fading == 0)
        tick(["prep": plate], nil)
        #expect(carrier.placement == .carried && carrier.node?.parent === socket)
        tick(["prep": plate], "stove")
        #expect(carrier.placement == .setDown)
        // Back to prep, then straight to the pantry: the plate is set down there and the jar pops up.
        for _ in 0..<60 { tick([:], "stove") }
        tick(["prep": plate], "prep"); tick(["prep": plate], nil)
        tick(["prep": plate, "pantry": .init(kind: .skill, name: "pdf")], "pantry")
        #expect(carrier.item?.kind == .skill && carrier.origin == "pantry" && carrier.placement == .counter && carrier.fading == 1)
        for _ in 0..<20 { tick(["pantry": .init(kind: .skill, name: "pdf")], "pantry") }
        #expect(carrier.fading == 0)
    }
}
