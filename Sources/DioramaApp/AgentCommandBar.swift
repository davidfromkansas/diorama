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
    /// Low enough to leave the kitchen room with both side panels open.
    static let height: CGFloat = 240

    private var value: WorkspaceAgent { agent.value }
    private var session: Session? { library.sessions.first { $0.id == agent.conversationID } }
    private var task: ExecutedTask? { session.flatMap { library.execution.tasks[$0.sessionID] } }
    private var project: DioramaProject? { library.projects.projects.first { $0.id == agent.projectID } }
    private var workspace: ProjectWorkspace? { session.flatMap { session in project?.workspaces.first { $0.threadID == session.sessionID } } }
    /// The worktree's files changed since the task began (a preview or test can pass some in).
    @State var changes: ChangesSnapshot? = nil
    /// The changes browser, open on a file.
    @State private var browsing: ChangesBrowsing?

    /// Progress (milestones and activity, newest first) or the task's changed files.
    enum Tab: Hashable { case progress, changes }
    /// Every agent opens on Progress; Changes is one click away.
    @State private var tab = Tab.progress

    var body: some View {
        card
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
            .onChange(of: agent.conversationID) { tab = .progress }
    }

    // MARK: Agent and order

    /// One card that fits beside both side panels: the task and who's on it, then two tabs.
    /// Progress shows the milestones beside the activity (activity alone when there are no
    /// milestones), newest first; Changes lists the files it changed, even when there are none.
    private var card: some View {
        Panel(inset: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 16).padding(.top, 12)
                tabs.padding(.horizontal, 16).padding(.top, 8)
                Rectangle().fill(SidebarStyle.divider).frame(height: 1)
                Group {
                    switch tab {
                    case .progress: progress
                    case .changes: changeList.padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
    /// The task's title, and under it who's on it: agent, model, cost and branch.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.paper)
                    .lineLimit(1).truncationMode(.tail).help(title)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Text(value.name).foregroundStyle(Palette.paper)
                    if let model { Text("·"); Text(model) }
                    if let tokens { Text("·"); Text(tokens).monospacedDigit() }
                    if let branch {
                        Text("·")
                        Label(branch, systemImage: "arrow.triangle.branch").labelStyle(.titleAndIcon)
                            .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    }
                }
                .font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    }
    /// The branch it works on, when Diorama knows one.
    private var branch: String? {
        let name = workspace?.branch.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }
    private var tabs: some View {
        HStack(spacing: 20) {
            tabButton(.progress, "Progress")
            // Always there, so you can see when nothing changed.
            tabButton(.changes, "Changes · \(changes?.files.count ?? 0)")
            Spacer(minLength: 0)
        }
    }
    private func tabButton(_ id: Tab, _ label: String) -> some View {
        Button { tab = id } label: {
            Text(label).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(tab == id ? Palette.paper : SidebarStyle.secondary)
                .padding(.bottom, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(tab == id ? Palette.paper : .clear).frame(height: 2) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand()
        .accessibilityAddTraits(tab == id ? [.isSelected] : [])
    }
    /// Milestones beside the activity, newest first in both; activity alone without milestones.
    private var progress: some View {
        HStack(alignment: .top, spacing: 0) {
            if !MilestoneList.milestones(value.plan).isEmpty {
                MilestoneList(plan: value.plan, working: value.isWorking, newestFirst: true)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(SidebarStyle.divider).frame(width: 1)
            }
            activity
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    /// Every file the task changed since it began, committed or not, with its line counts; the
    /// list scrolls in the column's height, and any row opens the changes browser on it.
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
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            if index > 0 { Rectangle().fill(SidebarStyle.divider).frame(height: 1) }
                            Button { browse(file.path) } label: { ChangedFileRow(file: file).contentShape(Rectangle()) }
                                .buttonStyle(.plain).pointingHand()
                        }
                    }
                }
                .frame(maxHeight: CGFloat(files.count) * (ChangedFileRow.height + 1))
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                Button { browse(nil) } label: {
                    Text(files.count == 1 ? "Open in the changes browser" : "Browse all \(files.count) files").font(.system(size: 12, weight: .medium)).underline()
                }
                .buttonStyle(.plain).foregroundStyle(SidebarStyle.tint(.inProgress).text).pointingHand()
            }
        }
        .sheet(item: $browsing) { ChangesBrowser(browsing: $0) }
    }
    private func browse(_ path: String?) {
        guard let workspace else { return }
        browsing = ChangesBrowsing(workspace: workspace, snapshot: changes, start: path)
    }
    /// The task's title as the agent panel, the chef's tag and the conversation header show it
    /// (`TaskLabels`); the conversation's own title until there is one.
    private var title: String {
        let label = TaskLabels.shared.title(agent)
        if !label.isEmpty { return label }
        let conversation = session.map { TaskTitle.full($0.displayTitle) } ?? ""
        return conversation.isEmpty ? TaskTitle.full(value.task) : conversation
    }
    private func loadChanges() async {
        guard let workspace else { return }
        changes = try? await SessionChanges.snapshot(workspace, scope: .session)
        if let changes { SessionChangeCounts.shared.record(workspace, changes) }
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

    /// What it has been doing, newest first.
    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest activity").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.paper)
            if value.feed.isEmpty {
                Text("Nothing reported yet.").font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
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
    var width: CGFloat? = 124
    @ViewBuilder let value: Value
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            value.font(.system(size: 13)).foregroundStyle(Palette.paper).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .topLeading)
        .fixedSize(horizontal: width == nil, vertical: false)
    }
}

/// Lines added and removed, in green and red.
struct DiffCount: View {
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
struct ChangedFileRow: View {
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
            // The folder shows when it fits; a narrow column keeps just the name.
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

/// The agent's milestones (its reported plan) as a timeline: done ones checked in green, the one
/// it's on (or next up) ringed in blue, the rest still to do. Steps it finished in earlier turns
/// come first. A long plan scrolls, opening on the current step.
struct MilestoneList: View {
    let plan: AgentPlan?
    var working = false
    /// The last step at the top and the first at the bottom.
    var newestFirst = false

    enum State: Equatable { case done, now, next, todo }
    struct Milestone: Identifiable, Equatable { let id: Int; let title: String; let state: State }

    /// Earlier turns' finished steps, then this turn's list; the step in progress is "now", or
    /// when none is, the first not done is "next".
    static func milestones(_ plan: AgentPlan?) -> [Milestone] {
        guard let plan else { return [] }
        let steps = plan.earlier.map { ($0.title, "completed") } + plan.checklist.map { ($0.title, $0.status.lowercased()) }
        let active = steps.firstIndex { ["in_progress", "inprogress", "in progress", "running"].contains($0.1) }
        let next = active ?? steps.firstIndex { $0.1 != "completed" }
        return steps.enumerated().map { i, step in
            let state: State = step.1 == "completed" ? .done : i == next ? (active == nil ? .next : .now) : .todo
            return Milestone(id: i, title: step.0.trimmingCharacters(in: .whitespacesAndNewlines), state: state)
        }
    }

    var body: some View {
        let items = Self.milestones(plan)
        VStack(alignment: .leading, spacing: 8) {
            header(items)
            if items.isEmpty {
                Text(working ? "No milestones yet. They appear once the agent shares a plan." : "This task has no milestones.")
                    .font(.system(size: 12)).foregroundStyle(SidebarStyle.secondary)
            } else {
                let shown = newestFirst ? Array(items.reversed()) : items
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                                // A rail segment is green where it joins two finished steps.
                                let above = index > 0 ? shown[index - 1] : nil, below = index + 1 < shown.count ? shown[index + 1] : nil
                                MilestoneRow(item: item, first: above == nil, last: below == nil,
                                             previousDone: above.map { $0.state == .done && item.state == .done } ?? false,
                                             nextDone: below.map { $0.state == .done && item.state == .done } ?? false).id(item.id)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .onAppear { scroll(reader, items) }
                    .onChange(of: items.first { $0.state == .now || $0.state == .next }?.id) { scroll(reader, items) }
                }
            }
        }
    }
    /// "Milestones", one segment per step (green done, blue current, grey to do), the count, and a
    /// ↺ when the list is from the last turn: one line at any width.
    private func header(_ items: [Milestone]) -> some View {
        let done = items.filter { $0.state == .done }.count
        let lastTurn = plan?.tasksPreviousTurn == true
        return HStack(spacing: 10) {
            Text("Milestones").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.paper)
            if !items.isEmpty {
                HStack(spacing: items.count > 12 ? 1.5 : 3) {
                    ForEach(items) { item in
                        Capsule().fill(item.state == .done ? MilestoneRow.green : item.state == .now || item.state == .next ? SidebarStyle.accent : Color.black.opacity(0.1))
                    }
                }
                .frame(maxWidth: 160).frame(height: 6)
                .accessibilityHidden(true)
                Text("\(done)/\(items.count)").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Palette.paper)
                    .accessibilityLabel("\(done) of \(items.count) milestones done")
                if lastTurn {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .bold)).foregroundStyle(SidebarStyle.secondary)
                        .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.05)))
                        .help("From the last turn").accessibilityLabel("From the last turn")
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
    private func scroll(_ reader: ScrollViewProxy, _ items: [Milestone]) {
        // The current step near the top, with the last finished one above it for context.
        guard let current = items.first(where: { $0.state == .now || $0.state == .next }) else { return }
        // Newest first, the step after it sits above it instead.
        reader.scrollTo(newestFirst ? min(items.count - 1, current.id + 1) : max(0, current.id - 1), anchor: .top)
    }
}

/// One milestone on the timeline: its marker on a rail (green between finished steps), then its
/// title; the current one bold, with a "Now" or "Up next" tag.
private struct MilestoneRow: View {
    let item: MilestoneList.Milestone
    let first: Bool
    let last: Bool
    /// The segments above and below are green when they join two finished steps.
    let previousDone: Bool
    var nextDone: Bool? = nil
    static let green = Color(red: 0.18, green: 0.62, blue: 0.31)
    private static let rail = Color.black.opacity(0.12)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(first ? .clear : (previousDone ? Self.green : Self.rail)).frame(width: 2, height: 9)
                    Rectangle().fill(last ? .clear : ((nextDone ?? (item.state == .done)) ? Self.green : Self.rail)).frame(width: 2).frame(maxHeight: .infinity)
                }
                marker.padding(.top, 2)
            }
            .frame(width: 18)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title).font(.system(size: 13, weight: item.state == .now || item.state == .next ? .semibold : .regular))
                    .foregroundStyle(item.state == .done ? SidebarStyle.secondary : item.state == .todo ? Palette.paper.opacity(0.72) : Palette.paper)
                    .fixedSize(horizontal: false, vertical: true)
                if item.state == .now || item.state == .next {
                    Text(item.state == .now ? "Now" : "Up next").font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(SidebarStyle.tint(.inProgress).band))
                        .foregroundStyle(SidebarStyle.tint(.inProgress).text)
                }
            }
            .padding(.bottom, last ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title + ", " + (item.state == .done ? "done" : item.state == .now ? "in progress" : item.state == .next ? "up next" : "not started"))
    }

    @ViewBuilder private var marker: some View {
        switch item.state {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white, Self.green)
        case .now, .next:
            ZStack {
                Circle().fill(Color.white)
                Circle().strokeBorder(SidebarStyle.accent, lineWidth: 2)
                Circle().fill(SidebarStyle.accent).padding(4.5).opacity(item.state == .now ? 1 : 0)
            }
            .frame(width: 15, height: 15)
        case .todo:
            Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1.5).background(Circle().fill(Color.white)).frame(width: 15, height: 15)
        }
    }
}

