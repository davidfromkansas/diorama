import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct HomeTests {
    private func agent(_ conversation: String, _ status: WorkspaceAgentStatus, project: String, reason: WorkspaceAttentionReason = .other) -> SpatialAgent {
        var value = WorkspaceAgent(id: "main", name: "main", provider: "Codex", task: "Task", action: "Act", status: status, reportedStatus: status.rawValue, freshness: .live)
        value.attentionReason = reason; value.completionKey = conversation; value.meaningfulUpdatedAt = Date()
        return SpatialAgent(projectID: project, conversationID: conversation, value: value)
    }
    private func team(_ agent: SpatialAgent) -> SpatialTeam {
        let id = agent.conversationID
        return SpatialTeam(projectID: agent.projectID, session: Session(id: id, provider: .codex, url: nil, sessionID: id, title: "Task " + id, project: "/tmp",
            modified: Date(), bytes: 0, archived: false, parentID: nil), agents: [agent])
    }
    private func project(_ id: String, _ agents: [(String, WorkspaceAgentStatus, WorkspaceAttentionReason)]) -> SpatialProject {
        SpatialProject(id: id, name: id.uppercased(), teams: agents.map { team(agent($0.0, $0.1, project: id, reason: $0.2)) })
    }
    private func items(_ project: SpatialProject) -> [AgentSidebarItem] {
        AgentSidebar.items(project.teams.map { AgentSidebar.Input(session: $0.session, agents: $0.agents) }, catalog: [], order: { $1 })
    }
    private var fixture: [SpatialProject] {
        [project("p1", [("a", .waiting, .input), ("b", .working, .other)]),
         project("p2", [("c", .working, .other), ("d", .working, .other)]),
         project("p3", [("e", .done, .other)]),
         project("p4", [("f", .ready, .other)])]
    }

    @Test func needsInputThenWorkingThenDoneUnread() {
        let cards = HomeRank.cards(fixture, items: items) { _ in false }
        #expect(cards.map(\.id) == ["p1", "p2", "p3"]) // p4 is idle: Recent projects
        #expect(cards[0].rows.map(\.state) == [.needsInput, .working])
        #expect(cards[2].rows.map(\.state) == [.toReview])
        #expect(HomeRank.needsYou(cards).map(\.id) == ["p1"])
        // Active: nobody waiting, someone working. p1 waits, so it's only in Needs you; p3 is only finished work.
        #expect(HomeRank.active(cards).map(\.id) == ["p2"])
        #expect(HomeRank.needsReview(cards).map(\.id) == ["p3"])
        #expect(HomeRank.opening(needsYou: 1, active: 3) == .needsYou)
        #expect(HomeRank.opening(needsYou: 0, active: 3) == .active)
        #expect(HomeRank.opening(needsYou: 0, active: 0, needsReview: 2) == .needsReview)
        #expect(HomeRank.opening(needsYou: 0, active: 0) == .recent)
    }

    @Test func readingFinishedWorkMovesItOutOfActive() {
        let cards = HomeRank.cards(fixture, items: items) { _ in true }
        #expect(!cards.contains { $0.id == "p3" })
    }

    @Test func finishedWorkWaitsUntilOpenedAndDecided() {
        // Work run in Diorama reaches the pass with a review state, like the app's sidebar inputs.
        func cards(viewed: Bool, _ state: KitchenReviews.State) -> [HomeProjectCard] {
            let items = { (project: SpatialProject) in
                AgentSidebar.items(project.teams.map { AgentSidebar.Input(session: $0.session, agents: $0.agents, review: state) }, catalog: [], order: { $1 })
            }
            return HomeRank.cards([project("p3", [("e", .done, .other)])], items: items, viewed: { _ in viewed }, review: { _ in state })
        }
        // Opened but undecided: still to review, and no longer "Not opened yet".
        let opened = cards(viewed: true, .awaiting)
        #expect(HomeRank.needsReview(opened).map(\.id) == ["p3"])
        #expect(opened.first?.rows.first?.opened == true)
        // Decided but never opened: still waits until it's opened.
        #expect(HomeRank.needsReview(cards(viewed: false, .committed)).map(\.id) == ["p3"])
        // Opened and decided: done.
        #expect(HomeRank.needsReview(cards(viewed: true, .committed)).isEmpty)
    }

    @Test func sectionMenuStacksTheSectionsBeforeTheCurrentOne() {
        // Furthest back first; the current section last, pinned above the cards. The list wraps.
        #expect(HomeSectionMenu.order(.needsYou) == [.active, .needsReview, .recent, .needsYou])
        #expect(HomeSectionMenu.order(.needsReview) == [.recent, .needsYou, .active, .needsReview])
    }

    @Test func providerOrbSaysWhatsLeftAndWhenItRefills() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        let sunday = Calendar.current.nextDate(after: now, matching: DateComponents(weekday: 1), matchingPolicy: .nextTime)!
        let window = LimitWindow(provider: .claude, usedPercent: 55, resetsAt: sunday, status: .ok, observedAt: now)
        #expect(HomeProviderOrb.detail(window, now: now) == "45% left · refills " + sunday.formatted(.dateTime.weekday(.abbreviated)))
        #expect(HomeProviderOrb.detail(nil, now: now) == "Not reported yet")
        let reached = LimitWindow(provider: .codex, usedPercent: 100, resetsAt: sunday, status: .exhausted, observedAt: now)
        #expect(HomeProviderOrb.detail(reached, now: now) == "Limit reached")
    }

    @Test func tiesKeepTheirOrderSoCardsDontJump() {
        let cards = HomeRank.cards([project("x", [("x1", .working, .other)]), project("y", [("y1", .working, .other)])], items: items) { _ in false }
        #expect(HomeRank.active(cards, previous: ["y", "x"]).map(\.id) == ["y", "x"])
        #expect(HomeRank.active(cards, previous: ["x", "y"]).map(\.id) == ["x", "y"])
    }

    @Test func sourceBadgeFollowsTheRepository() {
        var project = DioramaProject(name: "A", folder: "/tmp/a", commonDirectory: "", base: "", remote: nil)
        #expect(HomeRank.source(project) == .local)
        project.commonDirectory = "/tmp/a/.git"
        #expect(HomeRank.source(project) == .git)
        project.remote = "git@github.com:me/a.git"
        #expect(HomeRank.source(project) == .github)
    }

    @Test func cardRowPlacesTheFrontCardFirstAndWraps() {
        typealias Row = HomeCardRow<HomeProjectCard, EmptyView>
        let front = Row.place(slot: 0, frontWidth: 780, width: 1280)
        let next = Row.place(slot: 1, frontWidth: 780, width: 1280)
        #expect(front.x == 0 && front.angle == 0 && next.x > front.x + 700 && next.angle < 0)
        #expect(!Row.place(slot: 5, frontWidth: 780, width: 1280).visible && next.scale < 1)
    }

    /// DIORAMA_HOME_CAPTURE=1 renders the whole page with an empty library to /tmp/diorama-home-page.png.
    @Test func captureHomePage() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_HOME_CAPTURE"] == "1" else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let model = LibraryModel(execution: ExecutionController(), projects: projects, conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")))
        model.portfolio = PortfolioStore(cache: nil)
        let host = NSHostingView(rootView: HomeView(library: model, visible: false).frame(width: 1440, height: 854))
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 854); host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-home-page.png"))
    }

    /// DIORAMA_HOME_CAPTURE=1 renders Home's pieces with sample projects to /tmp/diorama-home-*.png.
    @Test func captureHome() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_HOME_CAPTURE"] == "1" else { return }
        let cards = HomeRank.cards(fixture, items: items) { _ in false }
        let week = [3, 5, 2, 8, 6, 1, 7].map { TokenSplit(input: Int64($0) * 180_000, output: Int64($0) * 40_000) }
        let actions = HomeCardActions(openAgent: { _ in }, newTask: { _ in }, openKitchen: { _ in })
        let recent = (0..<7).map { HomeRecentProject(id: "r\($0)", name: ["Receipt Scanner", "Movement Lab", "Landing Page", "Tax Helper", "Weather Bot", "Recipe Box", "CLI Tools"][$0],
                                                      source: [.github, .git, .local][$0 % 3], idle: $0 % 3, openedAt: Date().addingTimeInterval(-Double($0) * 86_400 * 3), stale: $0 == 2 ? 2 : 0) }
        for (name, section) in [("needs", HomeSectionKind.needsYou), ("active", .active), ("review", .needsReview), ("recent", .recent)] {
            let shown = section == .needsYou ? HomeRank.needsYou(cards) : section == .needsReview ? HomeRank.needsReview(cards) : HomeRank.active(cards)
            let view = ZStack(alignment: .topLeading) {
                HomeBackdrop(horizon: 360)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HomeSectionMenu(current: section, badges: [.needsYou: 1, .active: 1, .needsReview: 1, .recent: recent.count]) { _ in }
                        Spacer()
                        HomeProviderOrb(provider: .claude, window: LimitWindow(provider: .claude, usedPercent: 55, resetsAt: Date().addingTimeInterval(86_400), status: .ok, observedAt: Date()),
                                        state: .connected, signingIn: false, open: {}) {}
                        HomeProviderOrb(provider: .codex, window: nil, state: .signedOut, signingIn: false, open: {}) {}
                        HomeGitHubOrb {}
                        HomeAddProjectButton { _ in }
                    }.frame(height: 140).padding(.horizontal, 80)
                    if section == .recent {
                        HomeCardRow(cards: recent, front: .constant(0), tilt: ProcessInfo.processInfo.environment["DIORAMA_HOME_FLAT"] != "1") { project, _ in
                            HomeRecentCardView(project: project, usage: PortfolioUsageSummary(tokens: 12_400_000, coverage: .reported), days: week, actions: actions) {}
                        }.padding(.leading, 80).padding(.top, 12)
                    } else {
                        HomeCardRow(cards: shown, front: .constant(0), tilt: ProcessInfo.processInfo.environment["DIORAMA_HOME_FLAT"] != "1") { card, front in
                            HomeProjectCardView(card: card, front: front, days: week, actions: actions)
                        }.padding(.leading, 80).padding(.top, 12)
                    }
                    Spacer()
                }
            }.frame(width: 1440, height: 900).environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900); host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-home-\(name).png"))
        }
    }
}
