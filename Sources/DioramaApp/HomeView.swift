import SwiftUI
import DioramaCore

/// Home: Needs you, Active and Recent projects as an Xbox-style section menu over a row of
/// project cards, with Claude Code, Codex and GitHub at the top right.
struct HomeView: View {
    @Bindable var library: LibraryModel
    var visible = true
    @State private var projects: [SpatialProject] = []
    @State private var refreshTask: Task<Void, Never>?
    /// The last order shown in each section: ties keep it.
    @State private var orders: [HomeSectionKind: [String]] = [:]
    private var store: ProjectTabStore { library.navigation.projectTabs }

    var body: some View {
        if store.home.section == .imported && visible { imported } else { page }
    }

    /// Ranks the projects only when what they show changes: moving between sections and cards
    /// happens in HomeSections, so a key press never re-ranks every project.
    private var page: some View {
        let cards = projectCards
        let needs = HomeRank.needsYou(cards, previous: orders[.needsYou] ?? [])
        let active = HomeRank.active(cards, previous: orders[.active] ?? [])
        let review = HomeRank.needsReview(cards, previous: orders[.needsReview] ?? [])
        let recent = recentProjects(excluding: Set(cards.map(\.id)))
        return HomeSections(library: library, visible: visible, needs: needs, active: active, review: review, recent: recent,
                            openImported: openImportedActivity)
            .onChange(of: needs.map(\.id)) { orders[.needsYou] = needs.map(\.id) }
            .onChange(of: active.map(\.id)) { orders[.active] = active.map(\.id) }
            .onChange(of: review.map(\.id)) { orders[.needsReview] = review.map(\.id) }
            .onChange(of: library.sessionsRevision, initial: true) { refresh() }
            .onChange(of: library.projects.projects.map { $0.id + $0.name }) { refresh() }
            .onChange(of: library.scannedAt) { refresh() }
            .onChange(of: library.observationClock) { refresh() }
            .onChange(of: library.demoRevision) { refresh() }
            .onChange(of: library.windowIsActive) {
                guard library.windowIsActive else { return }
                // The Codex or Claude tools may have changed their default permissions meanwhile.
                ProviderDefaultsStore.shared.reload()
                guard visible else { return }
                refresh()
                guard library.demo == nil else { return }
                Task { await AgentConnections.shared.refresh(library.execution); await GitHubConnection.shared.refresh() }
            }
            .onChange(of: visible, initial: true) { if visible { refresh() } else { refreshTask?.cancel() } }
            .task(id: visible) {
                guard visible, library.demo == nil else { return }
                // Home's cards are where GitHub's state shows, so Home checks it, like the old sidebar button did.
                async let github: Void = GitHubConnection.shared.refresh()
                await AgentConnections.shared.refresh(library.execution)
                await github
            }
            .onDisappear { refreshTask?.cancel() }
    }

    // MARK: Data

    private var projectCards: [HomeProjectCard] {
        _ = AgentCompletionViews.shared.revision // Re-rank when finished work is read.
        return HomeRank.cards(projects, items: { library.agentSidebarItems($0.teams) }, viewed: AgentCompletionViews.shared.isViewed,
                              review: { KitchenReviews.shared.state($0) })
    }
    private func recentProjects(excluding active: Set<String>) -> [HomeRecentProject] {
        let records = Dictionary(library.projects.projects.map { ($0.id, $0) }) { first, _ in first }
        return projects.filter { !active.contains($0.id) }.map { project in
            HomeRecentProject(id: project.id, name: project.name, source: HomeRank.source(records[project.id]),
                              idle: project.teams.count, openedAt: store.lastOpened[project.id], stale: project.summary.stale,
                              tasks: Array(library.agentSidebarItems(project.teams).sorted { $0.order > $1.order }.prefix(6)))
        }.sorted {
            switch (store.lastOpened[$0.id], store.lastOpened[$1.id]) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
    private func refresh() {
        // The development demo records in the background, where the window isn't active.
        guard visible, library.windowIsActive || projects.isEmpty || library.demo != nil else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            // Coalesce discovery notifications and let navigation paint its cached content first.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let next = await library.homeProjectSummaries() else { return }
            if projects != next { projects = next }
        }
    }

    /// Space does what the front card's main button does.
    static func selectLabel(_ section: HomeSectionKind) -> String {
        switch section {
        case .needsYou: "Answer"
        case .active: "Open kitchen"
        case .needsReview: "Review"
        case .recent: "Open"
        }
    }

    // MARK: Imported activity (sessions outside Diorama projects), from the connections panel

    private func openImportedActivity() {
        store.home.section = .imported
        library.projects.selectedID = "imported"
    }
    private var imported: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    store.home.section = .all; library.projects.selectedID = nil; library.selectedID = nil
                } label: { Label("Home", systemImage: "chevron.left") }.buttonStyle(.borderless).pointingHand()
                Text("Imported activity").font(.system(size: 20, weight: .semibold))
                Spacer()
            }.padding(20)
            if let session = library.selected { WorkspaceImportedSession(session: session, library: library) }
            else { WorkspaceHome(library: library, imported: true) }
        }.background(DioramaStyle.canvas)
    }
}

/// Home's page: the section menu, the accounts, and the current section's cards. It owns where
/// you are (section, front cards, focus); HomeView hands it the ranked projects.
private struct HomeSections: View {
    @Bindable var library: LibraryModel
    let visible: Bool
    let needs: [HomeProjectCard]
    let active: [HomeProjectCard]
    let review: [HomeProjectCard]
    let recent: [HomeRecentProject]
    let openImported: () -> Void
    /// The section picked by the user; nil follows the opening rule.
    @State private var chosen: HomeSectionKind?
    /// Each section's front card, by project, so a re-rank doesn't swap the card you're reading.
    @State private var fronts: [HomeSectionKind: String] = [:]
    @State private var settingsOpen = false
    /// The project waiting on "Remove from Diorama?".
    @State private var removing: (id: String, name: String)?
    @FocusState private var focused: Bool
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: ProjectTabStore { library.navigation.projectTabs }

    var body: some View {
        let section = chosen ?? HomeRank.opening(needsYou: needs.count, active: active.count, needsReview: review.count)
        let shown = section == .needsYou ? needs : section == .needsReview ? review : active
        let found = filtered(recent)
        return GeometryReader { geometry in
            let margin: CGFloat = geometry.size.width < 1100 ? 40 : 80
            // The row fills the space between the header and the hints, from small windows up to tall ones.
            let rowHeight = min(HomeCardRow<HomeProjectCard, EmptyView>.maxHeight, max(240, geometry.size.height - 140 - 12 - 56 - 106))
            ZStack(alignment: .topLeading) {
                HomeBackdrop(horizon: 360)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        HomeSectionMenu(current: section, badges: [.needsYou: needs.reduce(0) { $0 + $1.count(.needsInput) }, .active: active.count, .needsReview: review.reduce(0) { $0 + $1.count(.toReview) }, .recent: found.count]) { picked in
                            if picked != section { HomeSound.shared.section(down: picked.rawValue > section.rawValue) }
                            select(picked)
                        }
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        Spacer(minLength: 24)
                        accounts.padding(.top, 16)
                    }
                    .frame(height: 140).padding(.horizontal, margin)
                    if section == .recent {
                        if found.isEmpty { emptyCard(section, width: geometry.size.width - margin, height: rowHeight).padding(.leading, margin).padding(.top, 12) }
                        else {
                            HomeCardRow(cards: found, front: frontBinding(section, ids: found.map(\.id)), height: rowHeight) { project, _ in
                                HomeRecentCardView(project: project, usage: library.portfolio.usage(project.id), days: library.portfolio.home.projectDays[project.id],
                                                   actions: actions) { library.selectProjectTab(project.id) }
                            }.padding(.leading, margin).padding(.top, 12)
                        }
                        hints(section, count: found.count, front: frontIndex(section, ids: found.map(\.id))).padding(.horizontal, margin).padding(.top, 22)
                        Spacer(minLength: 0)
                    } else if shown.isEmpty {
                        emptyCard(section, width: geometry.size.width - margin, height: rowHeight).padding(.leading, margin).padding(.top, 12)
                        Spacer(minLength: 0)
                    } else {
                        HomeCardRow(cards: shown, front: frontBinding(section, ids: shown.map(\.id)), height: rowHeight) { card, front in
                            HomeProjectCardView(card: card, front: front, days: library.portfolio.home.projectDays[card.id], actions: actions)
                        }.padding(.leading, margin).padding(.top, 12)
                        hints(section, count: shown.count, front: frontIndex(section, ids: shown.map(\.id))).padding(.horizontal, margin).padding(.top, 22)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .environment(\.colorScheme, .light)
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space]) { press in
            let ids = section == .recent ? found.map(\.id) : shown.map(\.id)
            if press.key == .space {
                guard !ids.isEmpty else { return .ignored }
                let id = ids[frontIndex(section, ids: ids)]
                HomeSound.shared.select()
                if section == .recent { library.selectProjectTab(id) } else if let card = shown.first(where: { $0.id == id }) { primary(card, section: section) }
                return .handled
            }
            return key(press.key, section: section, ids: ids)
        }
        .onChange(of: visible, initial: true) {
            // Coming back to Home opens on what matters now: Needs you, else Active, else Recent projects.
            if visible { chosen = nil; fronts = [:]; focused = true }
        }
        .confirmationDialog("Remove \(removing?.name ?? "this project") from Diorama?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = removing?.id, !library.projects.busy.contains(id) { library.removeProject(id) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Its folder and files stay on your Mac, and its conversations stay in Codex and Claude.")
        }
    }

    // MARK: Navigation

    /// Entering a section starts at its top-ranked card.
    private func select(_ section: HomeSectionKind) { fronts[section] = nil; chosen = section }
    private func frontIndex(_ section: HomeSectionKind, ids: [String]) -> Int {
        fronts[section].flatMap { ids.firstIndex(of: $0) } ?? 0
    }
    private func frontBinding(_ section: HomeSectionKind, ids: [String]) -> Binding<Int> {
        Binding(get: { frontIndex(section, ids: ids) },
                set: { index in if ids.indices.contains(index) { fronts[section] = ids[index] } })
    }
    private func filtered(_ recent: [HomeRecentProject]) -> [HomeRecentProject] {
        let query = store.home.query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? recent : recent.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private func key(_ key: KeyEquivalent, section: HomeSectionKind, ids: [String]) -> KeyPress.Result {
        let all = HomeSectionKind.allCases
        switch key {
        case .upArrow, .downArrow:
            let step = key == .downArrow ? 1 : all.count - 1
            HomeSound.shared.section(down: key == .downArrow)
            if reduceMotion { select(all[(section.rawValue + step) % all.count]) } else { withAnimation(.spring(duration: 0.35)) { select(all[(section.rawValue + step) % all.count]) } }
            return .handled
        case .leftArrow, .rightArrow:
            guard ids.count > 1 else { return .ignored }
            let next = (frontIndex(section, ids: ids) + (key == .rightArrow ? 1 : ids.count - 1)) % ids.count
            HomeSound.shared.move(key == .rightArrow ? 1 : -1)
            if reduceMotion { fronts[section] = ids[next] } else { withAnimation(.spring(duration: 0.45, bounce: 0.18)) { fronts[section] = ids[next] } }
            return .handled
        default: return .ignored
        }
    }
    private func primary(_ card: HomeProjectCard, section: HomeSectionKind) {
        let row = card.rows.first { $0.state == .needsInput } ?? card.rows.first { $0.state == .toReview }
        if section != .active, let row { actions.openAgent(row.focus) } else { actions.openKitchen(card.id) }
    }
    private var actions: HomeCardActions {
        HomeCardActions(openAgent: { focus in
            guard let project = focus.projectID else { return }
            library.selectProjectTab(project)
            if let conversation = focus.conversationID {
                library.navigate(.project(project, conversation)); library.spatial.focus = focus; library.spatial.conversationPanelVisible = true
            }
        }, newTask: { project in
            library.navigate(.project(project, nil))
            library.spatial.pendingCreation = project
        }, openKitchen: { project in
            library.navigate(.project(project, nil))
            library.spatial.sceneKind = .kitchen
            // Just the kitchen: no conversation panel left open from the last visit.
            library.spatial.conversationPanelVisible = false
        }, removeProject: { id, name in removing = (id, name) })
    }

    // MARK: Pieces

    /// Claude Code, Codex, GitHub and Add project, each its own round button. Claude Code and Codex open the connections panel.
    private var accounts: some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ForEach([Provider.claude, .codex], id: \.self) { provider in
                    HomeProviderOrb(provider: provider, window: library.portfolio.home.weekly[provider],
                                    state: AgentConnections.shared.state(provider), signingIn: AgentConnections.shared.pendingLogin == provider,
                                    open: { settingsOpen = true }) {
                        AgentConnections.shared.signIn(provider, execution: library.execution)
                    }
                }
            }
            .popover(isPresented: $settingsOpen, arrowEdge: .bottom) {
                HomeConnectionsPanel(library: library,
                                     openGitHub: { settingsOpen = false; library.showGitHub = true },
                                     openSettings: { settingsOpen = false; openSettings() },
                                     openImported: { settingsOpen = false; openImported() })
                    .environment(\.colorScheme, .light)
            }
            HomeGitHubOrb { library.showGitHub = true }
            HomeAddProjectButton { library.addProject = $0 }
        }
    }
    private func hints(_ section: HomeSectionKind, count: Int, front: Int) -> some View {
        HStack(spacing: 22) {
            if count > 0 {
                Text("\(front + 1) of \(count)").foregroundStyle(HomeStyle.muted).monospacedDigit()
                HomeKeyHint(keys: ["arrow.left", "arrow.right"], label: "Browse")
                HomeKeyHint(keys: ["space"], label: HomeView.selectLabel(section), tint: HomeStyle.green)
            }
            HomeKeyHint(keys: ["arrow.up", "arrow.down"], label: "Sections")
            if section == .recent {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                    TextField("Search projects", text: Bindable(store).home.query).textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(HomeStyle.ink)
                        .onSubmit { focused = true }
                }
                .padding(.horizontal, 12).frame(width: 280, height: 34)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HomeStyle.border))
            }
        }.font(.system(size: 14.5))
    }
    private func emptyCard(_ section: HomeSectionKind, width: CGFloat, height: CGFloat) -> some View {
        HomeEmptyCard(section: section, searching: section == .recent && !store.home.query.trimmingCharacters(in: .whitespaces).isEmpty)
            .frame(width: HomeCardRow<HomeProjectCard, EmptyView>.frontWidth(width), height: height)
    }
}

/// A lavender sky over a grid-paper floor that recedes toward a soft horizon.
struct HomeBackdrop: View {
    let horizon: CGFloat
    var body: some View {
        Canvas { context, size in
            let sky = Path(CGRect(x: 0, y: 0, width: size.width, height: horizon))
            context.fill(sky, with: .linearGradient(Gradient(colors: [Color(red: 0.886, green: 0.827, blue: 0.965), Color(red: 0.937, green: 0.906, blue: 0.98), Color(red: 0.965, green: 0.949, blue: 0.984)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            let floorRect = CGRect(x: 0, y: horizon, width: size.width, height: max(0, size.height - horizon))
            context.fill(Path(floorRect), with: .linearGradient(Gradient(colors: [Color(red: 0.831, green: 0.8, blue: 0.878), Color(red: 0.902, green: 0.882, blue: 0.925), Color(red: 0.937, green: 0.925, blue: 0.949)]),
                                                               startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: horizon + 420)))
            // Grid lines in perspective: a flat floor seen from above, rows 1 m apart in depth,
            // stopping before they crowd into the horizon.
            let line = Color(red: 0.357, green: 0.165, blue: 0.651)
            let center = size.width / 2, depth = floorRect.height
            let scale = depth * 1.6 // screen drop of the nearest row, per unit of 1 / distance
            var verticals = Path()
            for index in -60...60 {
                let x = center + CGFloat(index) * 140
                // Lines start spread along the horizon rather than at one point, so they don't fan into a blur.
                verticals.move(to: CGPoint(x: center + (x - center) * 0.22, y: horizon))
                verticals.addLine(to: CGPoint(x: center + (x - center) * (depth / 220), y: horizon + depth))
            }
            var rows = Path()
            var distance: CGFloat = 1.6, last = CGFloat.greatestFiniteMagnitude
            while distance < 400 {
                let y = horizon + scale / distance
                if y < horizon + depth {
                    guard last - y > 7 else { break }
                    rows.move(to: CGPoint(x: 0, y: y)); rows.addLine(to: CGPoint(x: size.width, y: y)); last = y
                }
                distance += 0.5
            }
            var faded = context
            faded.clip(to: Path(floorRect))
            faded.stroke(verticals, with: .color(line.opacity(0.11)), lineWidth: 1)
            faded.stroke(rows, with: .color(line.opacity(0.09)), lineWidth: 1)
            // Fade the grid into the horizon.
            faded.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: 140)),
                       with: .linearGradient(Gradient(colors: [Color(red: 0.831, green: 0.8, blue: 0.878), Color(red: 0.831, green: 0.8, blue: 0.878).opacity(0)]),
                                             startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: horizon + 90)))
            context.fill(Path(CGRect(x: 0, y: horizon - 0.5, width: size.width, height: 1)), with: .color(.white.opacity(0.9)))
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }
}
