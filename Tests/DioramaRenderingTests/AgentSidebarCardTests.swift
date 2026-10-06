import AppKit
@testable import DioramaCore
import SwiftUI
import Testing
@testable import DioramaApp

@MainActor struct AgentSidebarCardTests {
    func session(_ id: String, _ title: String, provider: Provider = .codex) -> Session {
        Session(id: id, provider: provider, url: nil, sessionID: id, title: title, project: "/p", modified: Date(timeIntervalSince1970: 1000), bytes: 0, archived: false, parentID: nil)
    }
    func agent(_ conversation: String, _ status: WorkspaceAgentStatus, tool: String = "", detail: String = "", attention: WorkspaceAttentionReason = .other,
               provider: Provider = .codex, model: String? = nil, main: Bool = true, freshness: WorkspaceAgentFreshness = .live) -> SpatialAgent {
        var value = WorkspaceAgent(id: main ? "main" : "helper", name: "Agent", provider: provider.rawValue, task: "Task", action: "", status: status,
                                   reportedStatus: status.rawValue, freshness: freshness)
        value.latestTool = tool; value.latestToolDetail = detail; value.attentionReason = attention; value.reportedModel = model
        return SpatialAgent(projectID: "p", conversationID: conversation, value: value)
    }
    func items(_ inputs: [AgentSidebar.Input]) -> [AgentSidebarItem] {
        AgentSidebar.items(inputs, catalog: [], order: { _, date in date })
    }

    @Test func groupsFollowTheLifecycleInOrder() {
        let list = items([
            .init(session: session("idle", "Refactor navigation"), agents: [agent("idle", .ready, provider: .claude)]),
            .init(session: session("done", "Update app icon"), agents: [agent("done", .done)], review: .awaiting),
            .init(session: session("work", "Build settings page"), agents: [agent("work", .working, tool: "apply_patch", detail: "Sources/SettingsView.swift")]),
            .init(session: session("ask", "Fix sign-in flow"), agents: [agent("ask", .waiting, attention: .approval, provider: .claude)]),
            .init(session: session("reviewed", "Old work"), agents: [agent("reviewed", .done)], review: .approved),
        ])
        #expect(list.map(\.conversationID) == ["ask", "work", "done", "idle", "reviewed"])
        #expect(list.map(\.group) == [.needsYou, .inProgress, .done, .idle, .idle])
        let work = list[1]
        #expect(work.status == "Working" && work.activity == "Editing SettingsView.swift…" && !work.hasAction)
        #expect(list[0].status == "Needs approval" && list[0].actionTitle == "Review request")
        #expect(list[2].actionTitle == "Review changes" && list[3].activity == "Waiting for a task")
        #expect(AgentSidebar.summaryText(AgentSidebar.summary(list)) == "1 active · 1 needs you · 1 done")
        #expect(AgentSidebar.summaryText(.init(active: 2, needsYou: 2, done: 0)) == "2 active · 2 need you · 0 done")
    }

    @Test func pendingInputWinsAndSilenceNeverFinishesATurn() {
        // A running turn with a request waiting, or a helper blocked: Needs you.
        let blocked = items([.init(session: session("a", "A"), agents: [agent("a", .working, tool: "Bash", detail: "npm test")], requests: 2),
                             .init(session: session("b", "B"), agents: [agent("b", .working), agent("b", .waiting, main: false)])])
        #expect(blocked.allSatisfy { $0.group == .needsYou })
        #expect(blocked.first { $0.conversationID == "a" }?.actionTitle == "Review 2 requests")
        // Reported running but quiet: still In progress, saying so.
        let quiet = items([.init(session: session("q", "Q"), agents: [agent("q", .working, tool: "Edit", detail: "a.swift", freshness: .lastKnown)])])
        #expect(quiet.first?.group == .inProgress && quiet.first?.activity == "No recent updates")
        // Finished but unreviewed stays Done, never Needs you; reworking is back In progress.
        #expect(items([.init(session: session("d", "D"), agents: [agent("d", .done)], review: .committed)]).first?.status == "Committed")
        #expect(items([.init(session: session("r", "R"), agents: [agent("r", .done)], review: .reworking)]).first?.group == .inProgress)
        // Helpers never get their own row.
        #expect(items([.init(session: session("h", "H"), agents: [agent("h", .working), agent("h", .working, main: false)])]).count == 1)
    }

    @Test func liveActivityReadsAsShortHumanPhrases() {
        func phrase(_ tool: String, _ detail: String) -> String {
            var value = agent("x", .working).value; value.latestTool = tool; value.latestToolDetail = detail
            return AgentSidebar.phrase(value)
        }
        #expect(phrase("Read", "/Users/me/app/AuthService.swift") == "Reading AuthService.swift…")
        #expect(phrase("Bash", "rg -n login Sources") == "Searching the code…")
        #expect(phrase("Bash", "npm test") == "Running tests…")
        #expect(phrase("Bash", "npm run build") == "Building…")
        #expect(phrase("Bash", "npm install three") == "Installing packages…")
        #expect(phrase("update_plan", "") == "Planning next steps…")
        #expect(phrase("computer_use", "Check the layout") == "Checking the result…")
        #expect(phrase("Bash", "python3 - <<'EOF'\np='math.js'; s=open(p).read()\nopen(p,'w').write(s)\nEOF") == "Editing math.js…")
        #expect(phrase("", "") == "Working…")
    }

    @Test func modelNamesAreDisplayNamesNeverRawIdentifiers() {
        let catalog = [ExecutionModel(id: "gpt-6-astra", name: "GPT-6 Astra", efforts: [], defaultEffort: "", isDefault: true)]
        #expect(AgentSidebar.modelName("gpt-6-astra", provider: Provider.codex.rawValue, catalog: catalog) == "GPT-6 Astra")
        #expect(AgentSidebar.modelName("claude-opus-5-5", provider: Provider.claude.rawValue, catalog: []) == "Claude Opus 5.5")
        #expect(AgentSidebar.modelName("claude-haiku-4-5-20251001", provider: Provider.claude.rawValue, catalog: []) == "Claude Haiku 4.5")
        #expect(AgentSidebar.modelName("gpt-5-mini", provider: Provider.codex.rawValue, catalog: []) == "GPT-5 Mini")
        #expect(AgentSidebar.modelName(nil, provider: Provider.codex.rawValue, catalog: []) == "Codex")
    }

    @Test func searchMatchesTitleModelAndStatusAndOrderStaysPut() {
        let list = items([.init(session: session("a", "Improve search"), agents: [agent("a", .working, tool: "Bash", detail: "npm test", provider: .claude, model: "claude-opus-5-5")])])
        #expect(list[0].matches("SEARCH") && list[0].matches("opus") && list[0].matches("testing") && !list[0].matches("deploy"))
        let defaults = UserDefaults(suiteName: "sidebar-order-" + UUID().uuidString)!
        let order = AgentSidebarOrder(defaults: defaults)
        let first = order.order("c", first: Date(timeIntervalSince1970: 5))
        #expect(order.order("c", first: Date(timeIntervalSince1970: 99)) == first)
        AgentSidebarCollapse.save([.done, .idle], project: "p", defaults: defaults)
        #expect(AgentSidebarCollapse.load("p", defaults: defaults) == [.done, .idle])
    }

    @Test func captureSidebarCard() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_SIDEBAR_CAPTURE"] == "1" else { return }
        let fixtures = items([
            .init(session: session("1", "Fix sign-in flow"), agents: [agent("1", .waiting, attention: .approval, provider: .claude, model: "claude-opus-5-5")]),
            .init(session: session("2", "Build settings page"), agents: [agent("2", .working, tool: "apply_patch", detail: "SettingsView.swift", model: "gpt-6-astra")]),
            .init(session: session("3", "Improve search"), agents: [agent("3", .working, tool: "Bash", detail: "npm test", provider: .claude, model: "claude-sonnet-5-5")]),
            .init(session: session("4", "Research auth options for the new sign-in screen and compare providers"), agents: [agent("4", .working, tool: "update_plan", model: "gpt-6-astra")]),
            .init(session: session("5", "Update app icon"), agents: [agent("5", .done, model: "gpt-6-astra")], review: .awaiting),
            .init(session: session("6", "Refactor navigation"), agents: [agent("6", .ready, provider: .claude, model: "claude-opus-5-5")]),
        ])
        for width in [320.0, 280] {
            let card = AgentSidebarCard(items: fixtures, projectID: "fixture", selectedConversation: "2", select: { _ in }, reviewRequest: { _ in }, reviewChanges: { _ in }, create: {})
                .frame(width: width, height: 640).lightFloatingCard().padding(20).background(Color(red: 0.55, green: 0.42, blue: 0.3))
            let host = NSHostingView(rootView: card)
            host.frame = NSRect(x: 0, y: 0, width: width + 40, height: 680)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-agent-sidebar-\(Int(width)).png"))
        }
    }
}
