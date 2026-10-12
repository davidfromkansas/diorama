import SwiftUI
import DioramaCore

/// Where an agent stands on Home, most urgent first.
enum HomeAgentState: Int, Comparable {
    /// Finished work waiting on you: not opened yet, or opened but not decided (Commit, Merge,
    /// PR or Mark done). Which of the two is on the row's `opened`.
    case needsInput, working, toReview, idle
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Home's three sections, in menu order.
enum HomeSectionKind: Int, CaseIterable, Identifiable {
    case needsYou, active, needsReview, recent
    var id: Int { rawValue }
    var title: String { ["Needs you", "Active", "Needs review", "Recent projects"][rawValue] }
}

/// One agent row on a project card: the project sidebar's row, plus where it ranks on Home.
struct HomeAgentRow: Identifiable, Equatable {
    let item: AgentSidebarItem
    let state: HomeAgentState
    let focus: SpatialFocus
    /// Reported as running, but nothing heard for `HomeRank.quietAfter`: still shown on its card
    /// ("No recent updates"), but it no longer counts as working.
    var quiet = false
    /// For `.toReview`: you've opened the result, so it only waits on your decision.
    var opened = false
    var id: String { item.id }
}

/// A project with agents waiting, working or finished but unread.
struct HomeProjectCard: Identifiable, Equatable {
    let id: String
    let name: String
    /// Rows for every agent that isn't idle, most urgent first.
    var rows: [HomeAgentRow]
    var waitingSince: Date?
    var lastActivity: Date?
    /// Agents in a state; quiet sessions don't count as working.
    func count(_ state: HomeAgentState) -> Int { rows.filter { $0.state == state && !$0.quiet }.count }
    /// Finished work not opened yet.
    var unopened: Int { rows.filter { $0.state == .toReview && !$0.opened }.count }
    var best: HomeAgentState { rows.map(\.state).min() ?? .idle }
}

/// A project on the Recent projects grid.
struct HomeRecentProject: Identifiable, Equatable {
    enum Source: Equatable { case github, git, local }
    let id: String
    let name: String
    let source: Source
    let idle: Int
    let openedAt: Date?
    let stale: Int
    /// Its conversations' last tasks, newest first.
    var tasks: [AgentSidebarItem] = []
}

enum HomeRank {
    /// A turn with no activity for this long no longer counts as working: Diorama can't tell a
    /// silent long build from a session abandoned mid-turn, and the latter would lead Active forever.
    static let quietAfter: TimeInterval = 30 * 60

    /// One rule for every place Home counts agents: blocked first, then running, then finished
    /// work nobody has opened.
    /// Finished work waits on you until you've both opened it and decided on it. Work Diorama
    /// can't commit or merge (it ran outside Diorama) only needs opening.
    static func state(_ item: AgentSidebarItem, agent: WorkspaceAgent?, viewed: Bool, review: KitchenReviews.State? = nil) -> HomeAgentState {
        switch item.group {
        case .needsYou: return .needsInput
        case .inProgress: return .working
        case .done:
            // Committed or a PR opened is a decision; only work still at the pass waits on one.
            if let review, review != .awaiting { return viewed ? .idle : .toReview }
            return .toReview
        case .idle:
            guard let agent else { return .idle }
            return AgentSidebarStatus.resolve(agent, viewed: viewed) == .done ? .toReview : .idle
        }
    }

    /// Cards for every project with something to show, from the sidebar's rows.
    static func cards(_ projects: [SpatialProject], items: (SpatialProject) -> [AgentSidebarItem], viewed: (WorkspaceAgent) -> Bool,
                      review: (String) -> KitchenReviews.State? = { _ in nil }, now: Date = Date()) -> [HomeProjectCard] {
        projects.compactMap { project in
            let agents = Dictionary(project.teams.flatMap(\.agents).map { ($0.id, $0) }) { first, _ in first }
            let rows = items(project).compactMap { item -> HomeAgentRow? in
                let agent = agents[item.id]
                let seen = agent.map { viewed($0.value) } ?? true
                let state = state(item, agent: agent?.value, viewed: seen, review: review(item.conversationID))
                guard state != .idle else { return nil }
                let focus: SpatialFocus = agent.map { .agent(project: $0.projectID, conversation: $0.conversationID, agent: $0.id, expanded: true) }
                    ?? .team(project: project.id, conversation: item.conversationID)
                let heard = agent.flatMap { $0.value.meaningfulUpdatedAt ?? $0.value.observedAt } ?? .distantPast
                return HomeAgentRow(item: item, state: state, focus: focus, quiet: state == .working && now.timeIntervalSince(heard) > quietAfter, opened: seen)
            }
            // Only quiet sessions: nothing to show on Home's cards, so it's a Recent project.
            guard rows.contains(where: { !$0.quiet }) else { return nil }
            let dates = { (state: HomeAgentState) in rows.filter { $0.state == state }.compactMap { agents[$0.id]?.value.meaningfulUpdatedAt } }
            // Rows keep the sidebar's order within a state, so a card doesn't reshuffle as activity changes.
            // Within finished work, what you haven't opened comes before what only needs a decision.
            let ordered = rows.enumerated().sorted { a, b in
                if a.element.state != b.element.state { return a.element.state < b.element.state }
                if a.element.state == .toReview, a.element.opened != b.element.opened { return !a.element.opened }
                return a.offset < b.offset
            }.map(\.element)
            return HomeProjectCard(id: project.id, name: project.name, rows: ordered,
                                   waitingSince: dates(.needsInput).min(), lastActivity: rows.compactMap { agents[$0.id]?.value.meaningfulUpdatedAt }.max())
        }
    }

    /// Needs you: the most agents waiting first, then whoever has waited longest.
    static func needsYou(_ cards: [HomeProjectCard], previous: [String] = []) -> [HomeProjectCard] {
        stable(cards.filter { $0.count(.needsInput) > 0 }, previous: previous) { a, b in
            if a.count(.needsInput) != b.count(.needsInput) { return a.count(.needsInput) > b.count(.needsInput) }
            return nil
        } fallback: { a, b in (a.waitingSince ?? .distantFuture) < (b.waitingSince ?? .distantFuture) }
    }

    /// Active: agents working and nobody waiting (those are in Needs you until answered). The
    /// most working first, then the most to review.
    static func active(_ cards: [HomeProjectCard], previous: [String] = []) -> [HomeProjectCard] {
        stable(cards.filter { $0.count(.needsInput) == 0 && $0.count(.working) > 0 }, previous: previous) { a, b in
            if a.count(.working) != b.count(.working) { return a.count(.working) > b.count(.working) }
            if a.count(.toReview) != b.count(.toReview) { return a.count(.toReview) > b.count(.toReview) }
            return nil
        } fallback: { a, b in (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast) }
    }

    /// Needs review: nothing waiting, nothing working, finished work you haven't dealt with. The
    /// most not yet opened first, then the most waiting on a decision.
    static func needsReview(_ cards: [HomeProjectCard], previous: [String] = []) -> [HomeProjectCard] {
        stable(cards.filter { $0.count(.needsInput) == 0 && $0.count(.working) == 0 && $0.count(.toReview) > 0 }, previous: previous) { a, b in
            if a.unopened != b.unopened { return a.unopened > b.unopened }
            if a.count(.toReview) != b.count(.toReview) { return a.count(.toReview) > b.count(.toReview) }
            return nil
        } fallback: { a, b in (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast) }
    }

    /// Orders by rank; ties keep the order they had last time, so cards don't jump while you look.
    private static func stable(_ cards: [HomeProjectCard], previous: [String], rank: (HomeProjectCard, HomeProjectCard) -> Bool?,
                               fallback: (HomeProjectCard, HomeProjectCard) -> Bool) -> [HomeProjectCard] {
        let place = Dictionary(previous.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
        return cards.sorted { a, b in
            if let ranked = rank(a, b) { return ranked }
            switch (place[a.id], place[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return fallback(a, b) || (!fallback(b, a) && a.name < b.name)
            }
        }
    }

    /// The section Home opens on: the first of Needs you, Active and Needs review with anything in it.
    static func opening(needsYou: Int, active: Int, needsReview: Int = 0) -> HomeSectionKind {
        needsYou > 0 ? .needsYou : active > 0 ? .active : needsReview > 0 ? .needsReview : .recent
    }

    static func source(_ project: DioramaProject?) -> HomeRecentProject.Source {
        guard let project else { return .local }
        if let remote = project.remote?.lowercased(), remote.contains("github.com") { return .github }
        return project.isGitBacked ? .git : .local
    }

    /// A project's colour: stable for its id, varied in hue, readable under white text.
    static func colour(_ id: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.52, brightness: 0.52)
    }
}

/// Claude Code and Codex sign-in, checked in one place so Home doesn't poll on its own.
@Observable @MainActor final class AgentConnections {
    static let shared = AgentConnections()
    private(set) var states: [Provider: AgentConnectionState] = [:]
    private(set) var pendingLogin: Provider?
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var checkedAt: Date?

    func state(_ provider: Provider) -> AgentConnectionState { states[provider] ?? .checking }
    /// The development demo shows both signed in without asking either tool.
    func showConnectedForDemo() { states = [.claude: .connected, .codex: .connected] }
    /// The key `diorama/connections` and the executables use.
    static func key(_ provider: Provider) -> String { provider == .claude ? "claude" : "codex" }

    /// Reads `diorama/connections`, at most once a minute unless forced. Like the start screen,
    /// it waits for the app server's check to settle: until then nothing reads as connected,
    /// which would look signed out.
    func refresh(_ execution: ExecutionController, force: Bool = false) async {
        guard !checking, force || (checkedAt.map { Date().timeIntervalSince($0) > 60 } ?? true) else { return }
        checking = true; defer { checking = false }
        let deadline = Date().addingTimeInterval(30)
        while !Task.isCancelled {
            let info = await execution.connectionInfo()
            let settled = !execution.connecting && (execution.connected || execution.error != nil)
                && !info["codexChecking"].bool && !info["claudeChecking"].bool
            if info != .null && (settled || info["codex"].bool || info["claude"].bool) {
                apply(info)
                if settled { checkedAt = Date(); return }
            }
            guard Date() < deadline else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        }
    }

    func apply(_ info: WireValue) {
        for provider in [Provider.claude, .codex] {
            let key = Self.key(provider)
            states[provider] = AgentConnectionState.resolve(installed: AgentExecutable.resolve(key) != nil, connected: info[key].bool,
                                                            checking: info[key + "Checking"].bool, error: info[key + "Error"].string)
        }
        if let pending = pendingLogin, states[pending] == .connected { pendingLogin = nil }
    }

    /// Opens Terminal on the provider's own sign-in, then checks every few seconds for two minutes.
    func signIn(_ provider: Provider, execution: ExecutionController) {
        let key = Self.key(provider)
        guard let binary = AgentExecutable.resolve(key) else { return }
        let shell = "'" + binary.path.replacingOccurrences(of: "'", with: "'\\''") + "'" + (provider == .claude ? " auth login --claudeai" : " login")
        let literal = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var problem: NSDictionary?
        NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(literal)\"\nend tell")?.executeAndReturnError(&problem)
        pendingLogin = provider
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(120)
            while pendingLogin == provider, Date() < deadline {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await refresh(execution, force: true)
            }
            if pendingLogin == provider { pendingLogin = nil }
        }
    }
}
