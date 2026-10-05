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
        HStack(alignment: .top, spacing: 10) {
            identity.frame(width: 196)
            orderTicket.frame(minWidth: 140, maxWidth: .infinity)
            activity.frame(minWidth: 140, maxWidth: .infinity)
            CommandBarSkills(agent: agent, library: library).frame(width: CommandBarSkills.width)
        }
        .padding(10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Palette.frame)
        .overlay(alignment: .top) { Rectangle().fill(Palette.trim).frame(height: 3) }
        .overlay(alignment: .topTrailing) {
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).padding(6) }
                .buttonStyle(.plain).foregroundStyle(Palette.paper.opacity(0.85)).pointingHand()
                .help("Deselect (Esc)").accessibilityLabel("Deselect " + value.name)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command bar for " + value.name)
    }

    // MARK: Identity

    private var identity: some View {
        Panel(title: "Chef") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        Image(systemName: "frying.pan.fill").font(.system(size: 22)).foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(Palette.ring, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(value.name).font(.title3.weight(.bold)).lineLimit(1)
                        StatusPill(text: statusText, color: statusColor)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    fact("cpu", [value.provider, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    if let branch = value.branch, !branch.isEmpty { fact("arrow.triangle.branch", branch) }
                    if let folder = value.worktree { fact("folder", (folder as NSString).lastPathComponent) }
                    if let dish = KitchenFood.dish(for: value.completionKey ?? agent.conversationID) { fact("fork.knife", Self.dishName(dish)) }
                    if let tokens { fact("gauge.with.dots.needle.33percent", tokens) }
                    if let time = value.observedAt { fact("clock", "Updated " + time.formatted(.relative(presentation: .named))) }
                }
                if let review, KitchenReviews.shared.state(agent.conversationID) != nil || value.status == .done {
                    Button(action: review) { Label("Review dish", systemImage: "fork.knife.circle.fill").font(.caption.weight(.semibold)) }
                        .buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.small).pointingHand()
                }
            }
        }
    }
    private func fact(_ icon: String, _ text: String) -> some View {
        Label { Text(text).lineLimit(1).truncationMode(.middle) } icon: { Image(systemName: icon).frame(width: 14) }
            .font(.caption).foregroundStyle(Palette.paper.opacity(0.85))
    }
    private var model: String? {
        let running = task?.model ?? ""
        return running.isEmpty ? value.reportedModel : running
    }
    private var tokens: String? {
        guard case .number(let total)? = task?.workflow.usage["total"]["totalTokens"], total > 0 else { return nil }
        return Int(total).formatted() + " tokens"
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
    static func dishName(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: Order ticket

    private var orderTicket: some View {
        Panel(title: "Order", paper: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(TaskTitle.full(value.task)).font(.callout.weight(.semibold)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let plan = value.plan, plan.hasTasks, plan.checklist.count > 0 {
                        ProgressView(value: Double(plan.completedTaskCount), total: Double(plan.checklist.count)).tint(Palette.accent)
                    }
                    AgentProgressSections(agent: value, fileLimit: 4, compact: true).foregroundStyle(Palette.ink)
                }
            }
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
        case .tool: "wrench.and.screwdriver"
        }
    }
    private var tint: Color {
        switch entry.kind {
        case .failed: .orange
        case .editing: Palette.ring
        case .command: .orange
        case .test: .cyan
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
    let title: String
    var paper = false
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.2)
                .foregroundStyle(paper ? Palette.ink.opacity(0.55) : Palette.trim)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12).fill(paper ? Palette.paper : Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(paper ? Palette.ink.opacity(0.15) : Palette.trim.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
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

/// The agent's skills as a 4-column grid; clicking a tile (or dragging it onto the composer)
/// arms the skill for the next message to this agent.
struct CommandBarSkills: View {
    let agent: SpatialAgent
    @Bindable var library: LibraryModel
    @State private var model = CapabilityLibraryModel()
    private let columns = Array(repeating: GridItem(.fixed(56), spacing: 6), count: 4)
    static let width: CGFloat = 4 * 56 + 3 * 6 + 22

    private var session: Session? { library.sessions.first { $0.id == agent.conversationID } }
    private var context: CapabilityLibraryContext? {
        guard let session, let provider = Provider(rawValue: agent.value.provider) ?? Optional(session.provider) else { return nil }
        // A finished task's worktree may be gone; its project folder still has the same skills.
        let folder = agent.value.worktree.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil } ?? session.project
        return CapabilityLibraryContext(provider: provider, folder: folder, sessionID: session.sessionID)
    }
    private var skills: [CapabilityLibraryItem] { (model.snapshot?.items ?? []).filter { $0.kind == .skill } }
    private var armed: Set<String> { Set((session.map { library.armedCapabilities[$0.id] ?? [] } ?? []).map(\.path)) }

    var body: some View {
        CommandBarPanel(title: "Skills") {
            if skills.isEmpty {
                VStack(spacing: 4) {
                    Text(model.loading ? "Loading skills…" : "No skills found for this agent.")
                    if !model.loading, let error = model.snapshot?.errors.values.first { Text(error).font(.caption2).lineLimit(3).foregroundStyle(.orange.opacity(0.85)) }
                }
                .font(.caption).multilineTextAlignment(.center)
                .foregroundStyle(CommandBarPalette.paper.opacity(0.6)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(skills) { item in
                            SkillTile(item: item, armed: armed.contains(item.source)) { arm(item) }
                                .draggable(ArmedSkill(name: item.name, path: item.source))
                        }
                    }
                }
            }
        }
        .task(id: context) {
            guard let context else { return }
            await model.load(context) { await library.execution.capabilityLibrary($0) }
        }
    }
    private func arm(_ item: CapabilityLibraryItem) {
        guard let session else { return }
        library.arm(CapabilityInput(name: item.name, path: item.source, kind: "skill"), for: session.id)
    }
}

private struct SkillTile: View {
    let item: CapabilityLibraryItem
    let armed: Bool
    let action: () -> Void
    private static let covers: [Color] = [
        Color(red: 0.86, green: 0.36, blue: 0.24), Color(red: 0.22, green: 0.55, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 0.75),
        Color(red: 0.78, green: 0.6, blue: 0.2), Color(red: 0.32, green: 0.6, blue: 0.36),
    ]
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: item.emblem).font(.system(size: 17, weight: .semibold))
                Text(item.name.split(separator: ":").last.map(String.init) ?? item.name)
                    .font(.system(size: 8.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(3)
            .frame(width: 56, height: 56)
            .background(RoundedRectangle(cornerRadius: 9).fill(Self.covers[item.coverIndex % Self.covers.count].gradient))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(armed ? CommandBarPalette.ring : .black.opacity(0.35), lineWidth: armed ? 2.5 : 1))
            .opacity(item.availability == .disabled || item.availability == .connectionNeeded ? 0.4 : 1)
        }
        .buttonStyle(.plain).pointingHand()
        .help(item.name + (item.description.isEmpty ? "" : "\n" + item.description) + (armed ? "\nArmed for your next message" : "\nClick or drag to the message box to arm"))
        .accessibilityLabel((armed ? "Armed skill " : "Skill ") + item.name)
    }
}

/// A skill dragged from the command bar onto the composer.
struct ArmedSkill: Codable, Transferable {
    let name: String
    let path: String
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .json) }
    var input: CapabilityInput { CapabilityInput(name: name, path: path, kind: "skill") }
}
