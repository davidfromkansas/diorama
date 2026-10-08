import DioramaCore
import SwiftUI

/// How a pull request's health reads everywhere it's shown: the serving window and the service board.
enum PRHealthStyle {
    static let problem = SidebarStyle.Tint(band: Color(red: 1.0, green: 0.93, blue: 0.92), text: ModalStyle.red, dot: Color(red: 0.86, green: 0.25, blue: 0.20))
    static func tint(_ health: PRHealth) -> SidebarStyle.Tint {
        switch health {
        case .checking: SidebarStyle.tint(.inProgress)
        case .ready, .merged: SidebarStyle.tint(.done)
        case .behind: SidebarStyle.tint(.needsYou)
        case .checksFailed, .conflicted: problem
        case .blocked, .closed: SidebarStyle.tint(.idle)
        }
    }
    static func icon(_ health: PRHealth) -> String {
        switch health {
        case .checking: "circle.dashed"
        case .ready: "checkmark.circle.fill"
        case .behind: "arrow.down.circle"
        case .blocked: "hand.raised.circle"
        case .checksFailed: "xmark.circle.fill"
        case .conflicted: "exclamationmark.triangle.fill"
        case .merged: "arrow.triangle.merge"
        case .closed: "minus.circle"
        }
    }
    /// The short label on a pill ("checks 2/5", "conflicts").
    static func pill(_ pr: LinkedPullRequest) -> String {
        switch pr.health {
        case .checking: pr.checks.isEmpty ? "checks queued" : "checks \(pr.finishedChecks)/\(pr.checks.count)"
        case .ready: "ready to merge"
        case .behind: "behind \(pr.baseRefName ?? "base")"
        case .blocked: pr.isDraft ? "draft" : "needs review"
        case .checksFailed: "needs a fix"
        case .conflicted: "needs a fix: conflicts"
        case .merged: "merged"
        case .closed: "closed"
        }
    }
    /// The serving window's band title.
    static func title(_ pr: LinkedPullRequest) -> String {
        let base = pr.baseRefName ?? "the base branch"
        switch pr.health {
        case .checking: return "PR #\(pr.number) · checks running"
        case .ready: return "PR #\(pr.number) · \(pr.checks.isEmpty ? "no checks" : "\(pr.checks.count) checks passed") · Ready to merge"
        case .behind: return "PR #\(pr.number) · behind \(base)"
        case .blocked: return "PR #\(pr.number) · \(pr.isDraft ? "draft" : "waiting on a required review")"
        case .checksFailed: return "PR #\(pr.number) · Needs a fix · " + ListFormatter.localizedString(byJoining: pr.failedChecks.map(\.title)) + " failed"
        case .conflicted: return "PR #\(pr.number) · Needs a fix · conflicts with \(base)"
        case .merged: return "PR #\(pr.number) merged"
        case .closed: return "PR #\(pr.number) closed"
        }
    }
}

/// The pull request at the serving window: its health band, head → base, each check, and (on a
/// conflict) the files and the base commits that changed them.
struct ServingPRSection: View {
    let pr: LinkedPullRequest
    let conflicts: PRConflicts?
    let refreshing: Bool
    var body: some View {
        let health = pr.health, tint = PRHealthStyle.tint(health)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: PRHealthStyle.icon(health)).font(.system(size: 12, weight: .semibold))
                Text(PRHealthStyle.title(pr)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                if refreshing { ProgressView().controlSize(.mini) }
                if health == .checking, !pr.checks.isEmpty {
                    Text("\(pr.finishedChecks) of \(pr.checks.count) done").font(.system(size: 12)).monospacedDigit()
                }
                if let url = URL(string: pr.url) {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square").font(.system(size: 12)) }
                        .help("Open #\(pr.number) on GitHub").accessibilityLabel("Open on GitHub").pointingHand()
                }
            }
            .foregroundStyle(tint.text)
            .padding(.horizontal, 16).frame(height: SidebarStyle.bandHeight).frame(maxWidth: .infinity)
            .background(tint.band)
            .overlay(alignment: .bottom) { ModalDivider() }
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(SidebarStyle.secondary)
                Text(pr.headRefName).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(SidebarStyle.secondary)
                Text(pr.baseRefName ?? "base").font(.system(size: 11.5, design: .monospaced)).lineLimit(1)
                Spacer(minLength: 6)
                mergePill
            }
            .padding(.horizontal, 16).frame(height: 32).overlay(alignment: .bottom) { ModalDivider() }
            if let conflicts, !conflicts.files.isEmpty {
                ForEach(conflicts.files) { file in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.merge").font(.system(size: 11)).foregroundStyle(ModalStyle.red).frame(width: 16)
                        Text(file.path).font(ModalStyle.mono).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        if let first = file.changedBy.first {
                            Text("also changed by “\(first)”").font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 32).overlay(alignment: .bottom) { ModalDivider() }
                    .help(file.changedBy.isEmpty ? file.path : "On \(conflicts.base): " + file.changedBy.joined(separator: "\n"))
                }
            }
            ForEach(sortedChecks.prefix(8)) { check in checkRow(check) }
            if pr.checks.count > 8 {
                Text("and \(pr.checks.count - 8) more checks").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { ModalDivider() }
            }
            if pr.statusCheckRollup != nil, pr.checks.isEmpty, pr.state == "OPEN" {
                Text("No CI checks reported for this pull request yet.").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { ModalDivider() }
            }
        }
    }
    /// Failed first, then running, then the rest.
    private var sortedChecks: [PRCheck] {
        let rank = ["Failed": 0, "Running": 1, "Cancelled": 2]
        return pr.checks.enumerated().sorted { (rank[$0.element.result] ?? 3, $0.offset) < (rank[$1.element.result] ?? 3, $1.offset) }.map(\.element)
    }
    @ViewBuilder private var mergePill: some View {
        switch pr.mergeable {
        case true? where pr.mergeableState != "behind": pill("no conflicts", SidebarStyle.tint(.done))
        case false?: pill("conflicts", PRHealthStyle.problem)
        case _ where pr.mergeableState == "behind": pill("behind", SidebarStyle.tint(.needsYou))
        default: if pr.state == "OPEN" { pill("checking merge", SidebarStyle.tint(.idle)) }
        }
    }
    private func pill(_ text: String, _ tint: SidebarStyle.Tint) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint.text)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(tint.dot.opacity(0.14)))
    }
    private func checkRow(_ check: PRCheck) -> some View {
        let (icon, color): (String, Color) = switch check.result {
        case "Passed": ("checkmark.circle.fill", SidebarStyle.tint(.done).dot)
        case "Failed": ("xmark.circle.fill", PRHealthStyle.problem.dot)
        case "Running": ("circle.dashed", SidebarStyle.tint(.inProgress).dot)
        default: ("minus.circle", SidebarStyle.secondary)
        }
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 16)
            Text(check.title).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text(check.result.lowercased()).font(.system(size: 11.5)).foregroundStyle(SidebarStyle.secondary)
            if let link = check.url, let url = URL(string: link) {
                Link("Log", destination: url).font(.system(size: 11.5)).pointingHand()
            }
        }
        .padding(.horizontal, 16).frame(height: 30).overlay(alignment: .bottom) { ModalDivider() }
        .accessibilityElement(children: .combine)
    }
}
