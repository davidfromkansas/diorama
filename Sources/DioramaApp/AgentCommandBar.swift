import DioramaCore
import SwiftUI

/// The selected chef's command bar under the kitchen (Overcooked by way of an RTS unit panel):
/// who it is, the order it's cooking, what it has been doing, and the skills it can use.
struct AgentCommandBar: View {
    let agent: SpatialAgent
    @Bindable var library: LibraryModel
    /// Opens the serving-window review when this chef's dish waits for one.
    var review: (() -> Void)? = nil
    /// Opens what it's waiting on you for: its pending request, or the question it asked.
    var requestReview: (() -> Void)? = nil
    let close: () -> Void
    static let height: CGFloat = 248

    private var value: WorkspaceAgent { agent.value }
    private var session: Session? { library.sessions.first { $0.id == agent.conversationID } }
    private var task: ExecutedTask? { session.flatMap { library.execution.tasks[$0.sessionID] } }
    private var project: DioramaProject? { library.projects.projects.first { $0.id == agent.projectID } }
    private var workspace: ProjectWorkspace? { session.flatMap { session in project?.workspaces.first { $0.threadID == session.sessionID } } }
    /// The worktree's files changed since the task began.
    @State private var changes: ChangesSnapshot?

    var body: some View {
        // The chef card takes three fifths or more: it carries the facts and the changed files, while the
        // activity feed reads fine narrower. Skills live in the pantry now (armed from there).
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 8) {
                // At least 560 wide when the bar allows it, always leaving Activity 200.
                card.frame(width: max(250, min(max(560, (geometry.size.width - 8) * 0.6), geometry.size.width - 208)))
                activity.frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Palette.frame)
        .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.14)).frame(height: 1) }
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command bar for " + value.name)
        // Reloaded as the agent reports more work, so the file list follows its edits.
        .task(id: "\(agent.conversationID)|\(value.feed.count)|\(value.status.rawValue)") { await loadChanges() }
    }

    // MARK: Agent and order

    /// Who the chef is and the order it's cooking, in one card: the title with its status and
    /// actions, then its facts beside the files it changed.
    private var card: some View {
        Panel(inset: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ScrollingTitle(text: title).help(title)
                    HStack(spacing: 8) {
                        StatusPill(text: statusText, tint: SidebarStyle.tint(group))
                        if let requestReview, agent.needsAttention {
                            Button("Review request", action: requestReview).buttonStyle(ModalPrimaryButtonStyle(height: 28)).pointingHand()
                                .help("Answer what it's waiting on")
                        }
                        if let review, KitchenReviews.shared.state(agent.conversationID) != nil || value.status == .done {
                            Button("Review", action: review).buttonStyle(ModalPrimaryButtonStyle(height: 28)).pointingHand()
                                .help("Open the serving-window review")
                        }
                        Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 24, height: 28).contentShape(Rectangle()) }
                            .buttonStyle(.plain).foregroundStyle(Palette.paper.opacity(0.6)).pointingHand()
                            .help("Deselect (Esc)").accessibilityLabel("Deselect " + value.name)
                    }
                    .fixedSize()
                }
                HStack(alignment: .top, spacing: 20) {
                    facts
                    changeList.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }
    /// The task title: the conversation's, else the agent's own task.
    private var title: String {
        let conversation = session.map { TaskTitle.full($0.displayTitle) } ?? ""
        return conversation.isEmpty ? TaskTitle.full(value.task) : conversation
    }
    /// Assignee and cost, then the branch beneath them, each a small label over its value.
    private var facts: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Fact(label: "Assignee", width: 150) {
                    Text(value.name) + Text(model.map { " · " + $0 } ?? "").foregroundStyle(SidebarStyle.secondary)
                }
                Fact(label: "Cost", width: 90) { Text(tokens ?? "—").monospacedDigit() }
            }
            GridRow {
                Fact(label: "Branch", width: 256) {
                    Text(workspace?.branch ?? value.branch ?? "No branch").font(.system(size: 12, design: .monospaced)).lineLimit(2)
                }
                .gridCellColumns(2)
            }
        }
    }
    /// Every file the task changed since it began, committed or not, with its line counts.
    private var changeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            let files = changes?.files ?? []
            HStack(alignment: .firstTextBaseline) {
                Text(files.isEmpty ? "Changes" : "Changes · \(files.count) file\(files.count == 1 ? "" : "s")").font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).layoutPriority(1)
                Spacer(minLength: 8)
                if let changes, !files.isEmpty { DiffCount(added: changes.added, removed: changes.removed, size: 12) }
            }
            .foregroundStyle(Palette.paper)
            if files.isEmpty {
                Text(workspace == nil ? "Not working in a project worktree." : value.isWorking ? "No file changes yet." : "No file changes.")
                    .font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            } else {
                // Three rows show; more scroll inside the box.
                let shown = CGFloat(min(files.count, 3))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            if index > 0 { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
                            ChangedFileRow(file: file)
                        }
                    }
                }
                .frame(height: shown * ChangedFileRow.height + shown - 1)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            }
        }
    }
    private func loadChanges() async {
        guard let workspace else { changes = nil; return }
        changes = try? await SessionChanges.snapshot(workspace, scope: .session)
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
    /// The agent panel's group for this chef, for the icon and status colours.
    private var group: AgentSidebarGroup {
        if agent.needsAttention || value.status == .failed { return .needsYou }
        if KitchenReviews.shared.state(agent.conversationID) != nil || value.status == .done { return .done }
        return value.isWorking ? .inProgress : .idle
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
        case .done: SidebarStyle.tint(.done).text
        case .failed: SidebarStyle.tint(.needsYou).text
        }
    }
}

/// A framed section of the command bar; `paper` sections look like an order ticket.
struct CommandBarPanel<Content: View>: View {
    var title: String? = nil
    var inset: CGFloat = 12
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.35))
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(inset)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
    }
}

/// A thin progress track in the selection ring's green.
/// The agent's own list as a bar with its step count; while it revises an earlier list after
/// feedback, that list dimmed; while it works without one, a sweep (never a made-up fraction).
struct PlanProgressRow: View {
    let progress: AgentPlan.Progress
    /// The turn is still running: the label names the current step ("Finishing" once all are
    /// done); afterwards it says how many were done, so a turn that stopped short shows it.
    var running = false
    var body: some View {
        switch progress {
        case .steps(let done, let total):
            row(ProgressBar(fraction: Double(done) / Double(max(1, total))),
                label: !running ? "\(done) of \(total) steps done" : done >= total ? "Finishing" : "Step \(done + 1) of \(total)")
        case .revising(let done, let total):
            row(ProgressBar(fraction: Double(done) / Double(max(1, total))).opacity(0.4), label: "Updating plan…")
        case .working:
            row(SweepBar(), label: "Working · no checklist")
        case .none:
            EmptyView()
        }
    }
    private func row(_ bar: some View, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            bar
            Text(label).font(.caption2.monospacedDigit()).foregroundStyle(Palette.paper.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
    }
}
private struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                Capsule().fill(Palette.ring.gradient).frame(width: max(4, geometry.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent done")
    }
}
/// Activity without a known end: a short highlight gliding along the track (still under
/// Reduce Motion).
private struct SweepBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                if reduceMotion {
                    Capsule().fill(Palette.ring.opacity(0.5)).frame(width: geometry.size.width * 0.3)
                } else {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        Capsule().fill(Palette.ring.gradient).frame(width: geometry.size.width * 0.3)
                            .offset(x: (geometry.size.width * 1.3) * phase - geometry.size.width * 0.3)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .accessibilityLabel("Working, no checklist")
    }
}
private typealias Panel = CommandBarPanel

/// A small grey label over its value.
private struct Fact<Value: View>: View {
    let label: String
    var width: CGFloat = 124
    @ViewBuilder let value: Value
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            value.font(.system(size: 13)).foregroundStyle(Palette.paper).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .topLeading)
    }
}

/// Lines added and removed, in green and red.
private struct DiffCount: View {
    let added: Int
    let removed: Int
    var size: CGFloat = 11
    var body: some View {
        (Text("+\(added)").foregroundStyle(ChangedFileRow.green) + Text(" −\(removed)").foregroundStyle(ChangedFileRow.red))
            .font(.system(size: size, design: .monospaced)).monospacedDigit().lineLimit(1).fixedSize()
            .accessibilityLabel("\(added) lines added, \(removed) removed")
    }
}

/// One changed file: its kind, name and folder, and its line counts.
private struct ChangedFileRow: View {
    let file: ChangedFile
    static let height: CGFloat = 30
    static let green = Color(red: 0.12, green: 0.48, blue: 0.23)
    static let red = Color(red: 0.71, green: 0.14, blue: 0.09)
    var body: some View {
        let url = URL(fileURLWithPath: file.path)
        let folder = url.deletingLastPathComponent().relativePath
        HStack(spacing: 8) {
            Text(kind.letter).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(kind.color).frame(width: 12)
            let name = Text(url.lastPathComponent).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.paper).lineLimit(1)
            // The folder shows when it fits; a narrow bar keeps just the name.
            ViewThatFits(in: .horizontal) {
                if folder != ".", !folder.isEmpty {
                    HStack(spacing: 8) { name; Text("/" + folder).font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).lineLimit(1) }
                }
                name.truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DiffCount(added: file.added, removed: file.removed).padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .help(file.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.status) \(file.path), \(file.added) added, \(file.removed) removed")
    }
    private var kind: (letter: String, color: Color) {
        switch file.status {
        case "Added", "Copied": ("A", Self.green)
        case "Deleted": ("D", Self.red)
        case "Renamed": ("R", Color(red: 0.16, green: 0.36, blue: 0.75))
        case "Conflicted": ("U", .orange)
        default: ("M", Color(red: 0.54, green: 0.35, blue: 0.0))
        }
    }
}

/// The task title in two lines; a longer one scrolls slowly through the rest and back, waiting
/// while the pointer is over it, and stays put with Reduce Motion (the full text is its tooltip).
private struct ScrollingTitle: View {
    let text: String
    @State private var overflow: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let spacing: CGFloat = 2
    private static let window = ceil(NSLayoutManager().defaultLineHeight(for: font)) * 2 + spacing
    var body: some View {
        Text(text).font(Font(Self.font)).lineSpacing(Self.spacing).foregroundStyle(Palette.paper)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { overflow = max(0, $0 - Self.window) }
            .offset(y: offset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.window, alignment: .top)
            .clipped()
            .onHover { hovering = $0 }
            .task(id: overflow) { await scroll() }
    }
    private func scroll() async {
        offset = 0
        guard overflow > 1, !reduceMotion else { return }
        let duration = max(1.5, Double(overflow) / 14)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.5))
            if hovering || Task.isCancelled { continue }
            withAnimation(.easeInOut(duration: duration)) { offset = -overflow }
            try? await Task.sleep(for: .seconds(duration + 2.5))
            withAnimation(.easeInOut(duration: duration)) { offset = 0 }
            try? await Task.sleep(for: .seconds(duration))
        }
    }
}

private struct StatusPill: View {
    let text: String
    let tint: SidebarStyle.Tint
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(tint.band)).foregroundStyle(tint.text)
    }
}

/// The command bar's colours, in the agent panel's light style: a warm strip holding two
/// light cards, dark text, and the panel's blue for progress.
enum CommandBarPalette {
    static let frame = Color(red: 0.969, green: 0.957, blue: 0.937)
    static let panel = SidebarStyle.background
    static let paper = SidebarStyle.title
    static let accent = SidebarStyle.accent
    static let ring = SidebarStyle.accent
}
private typealias Palette = CommandBarPalette

/// A skill dragged from the pantry onto the composer.
struct ArmedSkill: Codable, Transferable {
    let name: String
    let path: String
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .json) }
    var input: CapabilityInput { CapabilityInput(name: name, path: path, kind: "skill") }
}
