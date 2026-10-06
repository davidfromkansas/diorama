import DioramaCore
import SwiftUI

/// The selected chef's command bar under the kitchen (Overcooked by way of an RTS unit panel):
/// who it is, the order it's cooking, what it has been doing, and the skills it can use.
struct AgentCommandBar: View {
    let agent: SpatialAgent
    @Bindable var library: LibraryModel
    /// Opens the serving-window review when this chef's dish waits for one.
    var review: (() -> Void)? = nil
    let close: () -> Void
    static let height: CGFloat = 248

    private var value: WorkspaceAgent { agent.value }
    private var session: Session? { library.sessions.first { $0.id == agent.conversationID } }
    private var task: ExecutedTask? { session.flatMap { library.execution.tasks[$0.sessionID] } }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            card.frame(minWidth: 250, maxWidth: .infinity).layoutPriority(1)
            // Skills live in the pantry now (armed from there for the selected chef).
            activity.frame(minWidth: 180, maxWidth: .infinity)
        }
        .padding(8)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Palette.frame)
        .overlay(alignment: .top) { Rectangle().fill(Palette.trim.opacity(0.8)).frame(height: 2) }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command bar for " + value.name)
    }

    // MARK: Agent and order

    /// Who the chef is and the order it's cooking, in one card: a header row, one line of facts,
    /// then the task and its progress.
    private var card: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "frying.pan.fill").font(.system(size: 13)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Palette.accent.gradient))
                        .overlay(Circle().stroke(Palette.ring.opacity(0.9), lineWidth: 1.5))
                    Text(value.name).font(.headline).lineLimit(1)
                    StatusPill(text: statusText, color: statusColor)
                    Spacer(minLength: 4)
                    if let review, KitchenReviews.shared.state(agent.conversationID) != nil || value.status == .done {
                        Button("Review", action: review).buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.small).pointingHand()
                            .help("Open the serving-window review")
                    }
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22).contentShape(Rectangle()) }
                        .buttonStyle(.plain).foregroundStyle(Palette.paper.opacity(0.6)).pointingHand()
                        .help("Deselect (Esc)").accessibilityLabel("Deselect " + value.name)
                }
                Text(facts).font(.caption2).foregroundStyle(Palette.paper.opacity(0.6)).lineLimit(1).truncationMode(.middle)
                Divider().overlay(Palette.paper.opacity(0.08))
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(TaskTitle.full(value.task)).font(.callout.weight(.medium)).foregroundStyle(Palette.paper)
                            .lineLimit(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if let plan = value.plan, plan.hasTasks, !plan.tasksPreviousTurn {
                            ProgressBar(fraction: Double(plan.completedTaskCount) / Double(max(1, plan.checklist.count)))
                        }
                        AgentProgressSections(agent: value, fileLimit: 4, compact: true)
                    }
                }
            }
        }
    }
    /// Provider and model, branch and usage on one line.
    private var facts: String {
        var parts = [[value.provider, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")]
        if let branch = value.branch, !branch.isEmpty { parts.append("⎇ " + branch) }
        if let tokens { parts.append(tokens) }
        return parts.filter { !$0.isEmpty }.joined(separator: "   ")
    }
    private var model: String? {
        let running = task?.model ?? ""
        return running.isEmpty ? value.reportedModel : running
    }
    private var tokens: String? {
        guard case .number(let total)? = task?.workflow.usage["total"]["totalTokens"], total > 0 else { return nil }
        return Int(total).formatted(.number.notation(.compactName)) + " tokens"
    }
    private var statusText: String {
        if agent.needsAttention { return "Needs you" }
        if KitchenReviews.shared.state(agent.conversationID) == .awaiting { return "Ready for review" }
        return value.status.rawValue
    }
    private var statusColor: Color {
        if agent.needsAttention || value.status == .failed { return .orange }
        switch value.status {
        case .working: return Palette.ring
        case .done: return .teal
        default: return .gray
        }
    }

    // MARK: Activity

    private var activity: some View {
        Panel(title: "Activity") {
            if value.feed.isEmpty {
                Text("Nothing reported yet.").font(.caption).foregroundStyle(Palette.paper.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(value.feed.reversed()) { FeedRow(entry: $0) }
                    }
                }
            }
        }
    }
}

/// One line of the activity feed: an icon for the kind of work, the line, and how it went.
private struct FeedRow: View {
    let entry: FeedEntry
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint).frame(width: 15)
            Text(entry.title).font(.caption).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(entry.kind == .started || entry.kind == .finished ? Palette.paper.opacity(0.65) : Palette.paper)
            Spacer(minLength: 4)
            if let outcome = entry.outcome, entry.kind == .test || entry.kind == .command {
                Text(outcomeText(outcome)).font(.caption2.weight(.semibold)).foregroundStyle(outcomeColor(outcome))
            }
        }
        .help(entry.detail.isEmpty ? entry.title : entry.detail)
    }
    private var icon: String {
        switch entry.kind {
        case .started: "bell"
        case .finished: "checkmark.seal"
        case .failed: "xmark.octagon"
        case .interrupted: "pause.circle"
        case .research: "book"
        case .planning: "list.bullet.clipboard"
        case .editing: "knife"
        case .command: "flame"
        case .test: "drop"
        case .resource: "shippingbox"
        case .tool: "wrench.and.screwdriver"
        }
    }
    private var tint: Color {
        switch entry.kind {
        case .failed: .orange
        case .editing: Palette.ring
        case .command: .orange
        case .test: .cyan
        case .resource: .purple
        default: Palette.paper.opacity(0.7)
        }
    }
    private func outcomeText(_ outcome: FeedEntry.Outcome) -> String {
        let time = entry.duration.map { $0 >= 1 ? " · \(Int($0.rounded())) s" : "" } ?? ""
        switch outcome {
        case .running: return "running"
        case .done: return (entry.kind == .test ? "passed" : "done") + time
        case .failed: return "failed" + time
        }
    }
    private func outcomeColor(_ outcome: FeedEntry.Outcome) -> Color {
        switch outcome {
        case .running: Palette.paper.opacity(0.6)
        case .done: Palette.ring
        case .failed: .orange
        }
    }
}

/// A framed section of the command bar; `paper` sections look like an order ticket.
struct CommandBarPanel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased()).font(.system(size: 9.5, weight: .bold, design: .rounded)).tracking(1)
                    .foregroundStyle(Palette.trim.opacity(0.85))
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

/// A thin progress track in the selection ring's green.
private struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(Palette.ring.gradient).frame(width: max(4, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent done")
    }
}
private typealias Panel = CommandBarPanel

private struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.22))).overlay(Capsule().stroke(color, lineWidth: 1)).foregroundStyle(color)
    }
}

/// Kitchen colours: dark steel frame, brass trim, ticket paper and the selection ring's green.
enum CommandBarPalette {
    static let frame = Color(red: 0.13, green: 0.16, blue: 0.17)
    static let panel = Color(red: 0.19, green: 0.23, blue: 0.24)
    static let trim = Color(red: 0.85, green: 0.66, blue: 0.33)
    static let paper = Color(red: 0.97, green: 0.94, blue: 0.86)
    static let ink = Color(red: 0.2, green: 0.17, blue: 0.13)
    static let accent = Color(red: 0.86, green: 0.36, blue: 0.24)
    static let ring = Color(red: 0.35, green: 1, blue: 0.62)
}
private typealias Palette = CommandBarPalette

/// A skill dragged from the pantry onto the composer.
struct ArmedSkill: Codable, Transferable {
    let name: String
    let path: String
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .json) }
    var input: CapabilityInput { CapabilityInput(name: name, path: path, kind: "skill") }
}
