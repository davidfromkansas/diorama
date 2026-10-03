import AppKit
import DioramaCore
import Testing
@testable import DioramaApp

@MainActor struct AgentSidebarTests {
    private func agent(_ status: WorkspaceAgentStatus, freshness: WorkspaceAgentFreshness = .live) -> WorkspaceAgent {
        .init(id: "main", name: "Otto", provider: "Codex", task: "Task", action: "", status: status, reportedStatus: status.rawValue, freshness: freshness)
    }
    @Test func suppliedIconsAndViewportBoundary() {
        #expect(AgentStatusIcon.images.count == 4)
        let clip = NSRect(x: 0, y: 100, width: 300, height: 200)
        #expect(!AgentCompletionVisibility.Probe.completionVisible(.init(x: 0, y: 150, width: 280, height: 300), in: clip))
        #expect(AgentCompletionVisibility.Probe.completionVisible(.init(x: 0, y: 50, width: 280, height: 200), in: clip))
        #expect(!AgentCompletionVisibility.Probe.completionVisible(.init(x: 0, y: 0, width: 280, height: 50), in: clip))
    }
    @Test func claudeCompletionRetainsNativeIdentityWithoutChangingRenderer() {
        let data = Data(#"{"type":"assistant","uuid":"row","message":{"id":"native-message","content":[{"type":"text","text":"Done"}],"stop_reason":"end_turn"}}"#.utf8) + Data([10])
        let entries = ClaudeNormalizer.parse(data, scope: "fixture").entries
        #expect(entries.first?.completionMessageID == "native-message")
        #expect(entries.first?.claude == nil)
    }
    @Test func marqueeStopsAndResetsWhenCellIsReused() {
        let view = AgentHoverTitle.Marquee(frame: .init(x: 0, y: 0, width: 100, height: 20))
        view.configure(text: String(repeating: "Long title ", count: 10), active: true, size: 13, bold: true)
        view.layout()
        #expect(view.label.layer?.animation(forKey: "marquee") != nil)
        view.configure(text: "Short", active: false, size: 13, bold: true); view.layout()
        #expect(view.label.layer?.animationKeys()?.isEmpty != false)
        #expect(view.label.frame.minX == -2) // Compensates NSTextField’s built-in text inset.
    }
    @Test func replayDoesNotResurrectMigratedCompletion() throws {
        let suite = "sidebar-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentCompletionViews(defaults: defaults)
        var old = agent(.done, freshness: .lastKnown); old.completionKey = "Codex:s:old"
        #expect(store.isViewed(old))
        store.seed("Codex:s:old", unread: true)
        #expect(store.isViewed(old))
        store.seed("Codex:s:old", unread: true, historicalUnread: true)
        #expect(!store.isViewed(old))
        store.mark("Codex:s:old"); store.seed("Codex:s:old", unread: true, historicalUnread: true)
        #expect(store.isViewed(old))
    }
    @Test func contextMenuTargetsClickedAgentAndNeverParent() throws {
        let model = LiveAgentRosterModel()
        let main = SpatialAgent(projectID: "p", conversationID: "first", value: agent(.ready))
        var childValue = agent(.done)
        childValue = WorkspaceAgent(id: "child", name: "Child", provider: "Codex", task: "Child task", action: "", status: .done, reportedStatus: "Done", freshness: .lastKnown)
        let child = SpatialAgent(projectID: "p", conversationID: "second", value: childValue)
        model.ingest([main, child]); model.flushForTesting()
        let parent = LiveAgentRosterTable(model: model, animate: false, paused: false, recentExpanded: false, jumpRevision: 0, open: { _ in }, archive: { _ in })
        let coordinator = LiveAgentRosterTable.Coordinator(parent)
        coordinator.ids = [main.id, child.id]
        coordinator.rows = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.id, $0) })
        let menu = try #require(coordinator.menu(at: 0))
        #expect(menu.items.first?.representedObject as? String == main.id)
        #expect(menu.items.first?.isEnabled == true)
        #expect(coordinator.menu(at: 1)?.items.first?.isEnabled == false)
    }
    @Test func statusPriorityAndViewedTransitions() {
        #expect(AgentSidebarStatus.allCases.map(\.label) == ["Blocked", "Working", "Done", "Unknown", "Idle"])
        #expect(AgentSidebarStatus.resolve(agent(.waiting), viewed: true) == .blocked)
        #expect(AgentSidebarStatus.resolve(agent(.working), viewed: false) == .working)
        #expect(AgentSidebarStatus.resolve(agent(.working, freshness: .lastKnown), viewed: false) == .unknown)
        #expect(AgentSidebarStatus.resolve(agent(.done), viewed: false) == .done)
        #expect(AgentSidebarStatus.resolve(agent(.done, freshness: .unavailable), viewed: true) == .idle)
        for state in [WorkspaceAgentStatus.failed, .stopped] {
            #expect(AgentSidebarStatus.resolve(agent(state), viewed: false) == .blocked)
            #expect(AgentSidebarStatus.resolve(agent(state), viewed: true) == .idle)
        }
    }
    @Test func historicalBaselineReplayAndRestart() throws {
        let suite = "sidebar-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentCompletionViews(defaults: defaults, now: Date(timeIntervalSince1970: 100))
        var old = agent(.done, freshness: .lastKnown); old.completionKey = "Codex:s:old"; old.meaningfulUpdatedAt = Date(timeIntervalSince1970: 90)
        #expect(store.isViewed(old))
        var new = old; new.completionKey = "Codex:s:new"; new.meaningfulUpdatedAt = Date(timeIntervalSince1970: 101)
        #expect(!store.isViewed(new)); store.mark(new.completionKey!)
        #expect(store.isViewed(new)); store.seed(new.completionKey!, unread: true)
        #expect(store.isViewed(new))
        store.flush()
        let restored = AgentCompletionViews(defaults: defaults, now: Date(timeIntervalSince1970: 200))
        #expect(restored.isViewed(new)); #expect(restored.baseline == store.baseline)
        new.completionKey = "Codex:s:next"; #expect(!restored.isViewed(new))
        new.completionKey = "Codex:s:new:agent:child"; #expect(!restored.isViewed(new))
    }
    @Test func knownUnreadHistoryOverridesDefaultMigration() throws {
        let suite = "sidebar-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentCompletionViews(defaults: defaults)
        var old = agent(.done, freshness: .lastKnown); old.completionKey = "Claude:s:old"
        store.seed("Claude:s:old", unread: true)
        #expect(!store.isViewed(old))
    }
    @Test func statusSortDoesNotChangeActivityTimes() {
        var reducer = AgentRosterReducer()
        let values = [WorkspaceAgentStatus.ready, .unknown, .done, .working, .waiting].enumerated().map { i, state in
            var value = agent(state); value.meaningfulUpdatedAt = Date(timeIntervalSince1970: Double(i))
            return SpatialAgent(projectID: "p", conversationID: String(i), value: value)
        }
        reducer.ingest(values, received: Date()); reducer.updateStatuses { _ in false }
        #expect(reducer.ordered.map(\.sidebarStatus) == [.blocked, .working, .done, .unknown, .idle])
        let times = reducer.activityTimes
        reducer.updateStatuses { _ in true }; #expect(reducer.activityTimes == times)
    }
}
