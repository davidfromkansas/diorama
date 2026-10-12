import SwiftUI
import DioramaCore

/// A project with nothing cooking, as a card in the same row as the active ones: where it lives,
/// its idle agents and their last tasks, when it was opened and its tokens.
struct HomeRecentCardView: View {
    let project: HomeRecentProject
    let usage: PortfolioUsageSummary
    let days: [TokenSplit]?
    let actions: HomeCardActions
    let open: () -> Void
    var body: some View {
        HomeCardFrame(colour: HomeRank.colour(project.id)) {
            Text(project.name).font(.system(size: 30, weight: .bold)).tracking(-0.5).foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.6)
            HomeSourceBadge(source: project.source, onColour: true)
            Spacer(minLength: 0)
            if let days, days.contains(where: { $0.total > 0 }) { HomeTokenSummary(days: days) }
            else { Text("No tokens this week").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75)) }
        } content: {
            HStack(spacing: 6) {
                fact("\(project.idle) idle", symbol: "pause.circle")
                fact(opened, symbol: "clock")
                fact(tokens + " tokens", symbol: "cylinder.split.1x2")
            }.padding(.horizontal, 18).padding(.vertical, 14)
            if project.stale > 0 {
                Label("\(project.stale) last known / unavailable", systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 12)).foregroundStyle(HomeStyle.orangeInk).padding(.horizontal, 18).padding(.bottom, 10)
            }
            Text("LAST TASKS").font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(HomeStyle.muted)
                .padding(.horizontal, 18).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if project.tasks.isEmpty {
                        Text("No tasks yet").font(.system(size: 13)).foregroundStyle(HomeStyle.muted).padding(.horizontal, 18).padding(.vertical, 10)
                    }
                    ForEach(project.tasks) { item in
                        HStack(alignment: .top, spacing: 12) {
                            AgentSidebarIcon(group: .idle).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(HomeStyle.ink).lineLimit(1)
                                Text([item.status, item.model].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 12.5)).foregroundStyle(HomeStyle.muted).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(HomeStyle.rule).frame(height: 1) }
                    }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(HomeStyle.rule).frame(height: 1) }
            HomeCardFooter(project: project.id, name: project.name, actions: actions, urgent: ("Open project", HomeStyle.purple, open))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(HomeSourceBadge.title(project.source)), \(project.idle) idle agents, \(opened), \(tokens) tokens")
    }
    private func fact(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(HomeStyle.secondary)
            .padding(.horizontal, 10).frame(height: 26).background(HomeStyle.rule, in: Capsule()).lineLimit(1).fixedSize()
    }
    private var opened: String {
        guard let date = project.openedAt else { return "Not opened yet" }
        if Calendar.current.isDateInToday(date) { return "Opened today" }
        if Calendar.current.isDateInYesterday(date) { return "Opened yesterday" }
        return "Opened " + date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
    private var tokens: String {
        let count = usage.tokens.map(TokenCount.compact)
        switch usage.coverage {
        case .loading: return count ?? "…"
        case .unavailable: return "No"
        case .partial: return "Partial · " + (count ?? "—")
        case .reported: return count ?? "No"
        }
    }
}

/// GitHub, Git or Local: where the project's code lives.
struct HomeSourceBadge: View {
    let source: HomeRecentProject.Source
    var onColour = false
    var body: some View {
        HStack(spacing: 5) {
            switch source {
            case .github: HomeMark.github.image(size: 12)
            case .git: Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(red: 0.88, green: 0.33, blue: 0.24))
            case .local: Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(HomeStyle.muted)
            }
            Text(Self.title(source)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(HomeStyle.secondary)
        }
        .padding(.horizontal, 8).frame(height: 22).background(onColour ? Color.white.opacity(0.92) : HomeStyle.rule, in: Capsule()).fixedSize()
        .help(Self.help(source))
    }
    static func title(_ source: HomeRecentProject.Source) -> String {
        switch source { case .github: "GitHub"; case .git: "Git"; case .local: "Local" }
    }
    static func help(_ source: HomeRecentProject.Source) -> String {
        switch source { case .github: "Git repository connected to GitHub"; case .git: "Git repository, not on GitHub"; case .local: "Local folder, no Git" }
    }
}
