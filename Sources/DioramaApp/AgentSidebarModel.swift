import Foundation
import DioramaCore

/// The agent sidebar's groups, in display order.
enum AgentSidebarGroup: Int, CaseIterable, Identifiable, Codable {
    /// Blocked on you: a permission, an answer, an approval, or a failed turn.
    case needsYou
    /// Running a turn (planning, reading, editing, testing, waiting on a tool), or reworking.
    case inProgress
    /// Finished work you haven't reviewed at the serving window yet.
    case done
    /// Nothing running, nothing to answer, nothing to review.
    case idle
    var id: Int { rawValue }
    var title: String {
        switch self { case .needsYou: "Needs you"; case .inProgress: "In progress"; case .done: "Done"; case .idle: "Idle" }
    }
}

/// The status bar under a row: checklist steps, or a sweep while the agent works without one.
enum AgentSidebarProgress: Equatable {
    case steps(done: Int, total: Int)
    /// Working without a checklist: activity, not a fraction.
    case working
}

/// One sidebar row: a conversation (its main agent; helpers stay inside it).
struct AgentSidebarItem: Identifiable, Equatable {
    /// The main agent's identity (what the kitchen selects).
    let id: String
    let conversationID: String
    let projectID: String?
    /// The conversation's title, as Codex or Claude show it.
    let title: String
    let group: AgentSidebarGroup
    /// "Working", "Needs approval", "Done"… (line 2, in the group's colour).
    let status: String
    /// The model's display name ("Claude Opus 5.5", "GPT-6 Astra"), or the provider's.
    let model: String
    /// Line 3 for In progress and Idle rows.
    let activity: String
    /// Pending requests (approvals, questions) for Review request.
    let requests: Int
    /// When the sidebar first saw this conversation: rows keep their place as activity changes.
    let order: Date
    /// In progress: steps or a sweep. Needs you: the steps reached before it paused. Done and
    /// Idle: none.
    var progress: AgentSidebarProgress? = nil
    /// When finished work was reported done (Done rows): shown on the status line, newest first.
    var finishedAt: Date? = nil
    // Shown on the task board's larger cards.
    /// "Claude" or "Codex".
    var provider = ""
    var branch: String? = nil
    /// Files edited in the latest turn.
    var files = 0
    /// What the agent is asking, while it waits on you.
    var question: String? = nil
    var hasAction: Bool { group == .needsYou || group == .done }
    var actionTitle: String {
        if group == .done { return "Review changes" }
        return requests > 1 ? "Review \(requests) requests" : "Review request"
    }
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [title, model, status].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum AgentSidebar {
    struct Input {
        let session: Session
        let agents: [SpatialAgent]
        var review: KitchenReviews.State?
        /// The model the conversation runs on, when the execution layer knows it.
        var model: String?
        var requests = 0
        /// The pending question or request, in a line (from the protocol request or the chat).
        var question: String? = nil
    }

    /// One row per conversation, grouped from its lifecycle: pending input first, then a running
    /// turn, then unreviewed finished work, then idle. Silence never moves a row: a turn reported
    /// running stays In progress (marked "no recent updates") until its end is reported.
    static func items(_ inputs: [Input], catalog: [ExecutionModel], order: (String, Date) -> Date, now: Date = Date()) -> [AgentSidebarItem] {
        inputs.compactMap { input in
            guard let main = input.agents.first(where: { $0.value.isMain }) else { return nil }
            let value = main.value
            let helperWaiting = input.agents.contains { !$0.value.isMain && $0.value.status == .waiting }
            let group: AgentSidebarGroup
            let status: String
            var activity = ""
            if value.status == .waiting || value.status == .failed || helperWaiting || input.requests > 0 {
                group = .needsYou
                if value.status == .failed { status = "Failed" }
                else {
                    switch value.attentionReason {
                    case .approval: status = "Needs approval"
                    case .input: status = "Needs an answer"
                    case .other: status = input.requests > 0 ? "Needs approval" : "Blocked"
                    }
                }
            } else if value.status == .working || input.review == .reworking {
                group = .inProgress
                status = workStatus(value)
                activity = main.fresh || input.review == .reworking ? phrase(value) : "No recent updates"
            } else if let review = input.review, [.awaiting, .committed, .shipped].contains(review) {
                group = .done
                status = (review == .committed ? "Committed" : review == .shipped ? "PR open" : "Done") + finishedText(value.meaningfulUpdatedAt ?? input.session.modified, now: now)
            } else {
                group = .idle
                switch value.status {
                case .stopped: status = "Stopped"; activity = "Stopped before finishing"
                case .unknown: status = "Unverified"; activity = "Waiting for the connection"
                default: status = "Idle"; activity = "Waiting for a task"
                }
            }
            var progress: AgentSidebarProgress?
            let plan = value.plan.flatMap { $0.hasTasks && !$0.tasksPreviousTurn && $0.checklist.count > 1 ? $0 : nil }
            switch group {
            case .inProgress: progress = plan.map { .steps(done: $0.completedTaskCount, total: $0.checklist.count) } ?? .working
            case .needsYou: progress = plan.map { .steps(done: $0.completedTaskCount, total: $0.checklist.count) }
            case .done, .idle: progress = nil
            }
            return AgentSidebarItem(id: main.id, conversationID: main.conversationID, projectID: main.projectID,
                                    title: TaskTitle.full(input.session.displayTitle), group: group, status: status,
                                    model: modelName(input.model ?? value.reportedModel, provider: value.provider, catalog: catalog),
                                    activity: activity, requests: input.requests,
                                    order: order(main.conversationID, value.meaningfulUpdatedAt ?? input.session.modified), progress: progress,
                                    finishedAt: group == .done ? value.meaningfulUpdatedAt ?? input.session.modified : nil,
                                    provider: value.provider, branch: value.branch.flatMap { $0.isEmpty ? nil : $0 },
                                    files: value.turnWork.files.count, question: group == .needsYou ? input.question : nil)
        }
        // Newest conversation first within each group; a row's place is fixed by its first sighting.
        // Done is ranked by when the work finished, latest first.
        .sorted {
            if $0.group != $1.group { return $0.group.rawValue < $1.group.rawValue }
            if $0.group == .done, let a = $0.finishedAt, let b = $1.finishedAt, a != b { return a > b }
            return $0.order != $1.order ? $0.order > $1.order : $0.id < $1.id
        }
    }

    /// " 2:41 PM" today, " yesterday", or " Oct 5": when the work was finished.
    static func finishedText(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return " " + date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return " yesterday" }
        return " " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    struct Summary: Equatable { var active = 0, needsYou = 0, done = 0 }
    static func summary(_ items: [AgentSidebarItem]) -> Summary {
        Summary(active: items.filter { $0.group == .inProgress }.count, needsYou: items.filter { $0.group == .needsYou }.count,
                done: items.filter { $0.group == .done }.count)
    }
    static func summaryText(_ summary: Summary) -> String {
        "\(summary.active) active · \(summary.needsYou) \(summary.needsYou == 1 ? "needs" : "need") you · \(summary.done) done"
    }

    /// What a running agent is doing, in one word.
    static func workStatus(_ agent: WorkspaceAgent) -> String {
        guard !agent.latestTool.isEmpty else { return "Working" }
        switch KitchenActivity.classify(tool: agent.latestTool, detail: agent.latestToolDetail) {
        case .planning: return "Planning"
        case .researching: return "Researching"
        case .testing: return "Testing"
        case .checking: return "Checking"
        case .resources: return "Fetching"
        case .commands: return "Running"
        case .editing, .other: return "Working"
        }
    }
    /// A short, human description of the latest step ("Editing SettingsView.swift…"), never a
    /// raw command, argument list or event name.
    static func phrase(_ agent: WorkspaceAgent) -> String {
        let tool = agent.latestTool, detail = agent.latestToolDetail
        guard !tool.isEmpty else { return "Working…" }
        let firstLine = detail.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        // A path when the detail is one (`/a/b/File.swift`), never a whole command line.
        let file = !firstLine.contains(" ") && (firstLine.hasPrefix("/") || firstLine.contains(".")) ? (firstLine as NSString).lastPathComponent : ""
        let script = KitchenActivity.withoutHeredocs(KitchenActivity.shellScript(detail)).lowercased()
        switch KitchenActivity.classify(tool: tool, detail: detail) {
        case .planning: return "Planning next steps…"
        case .editing:
            let written = KitchenActivity.commandTools.contains(tool.lowercased()) ? KitchenActivity.writtenFiles(command: detail).first.map { ($0 as NSString).lastPathComponent } : nil
            if let name = written ?? (file.isEmpty ? nil : file) { return "Editing \(name)…" }
            return "Editing files…"
        case .researching:
            // Web tools first: "webSearch" also contains "search".
            if tool.lowercased().contains("web") { return "Researching online…" }
            if ["grep", "rg ", "find ", "search", "glob"].contains(where: { script.contains($0) || tool.lowercased().contains($0) }) { return "Searching the code…" }
            return file.isEmpty ? "Reading the project…" : "Reading \(file)…"
        case .testing: return "Running tests…"
        case .checking: return "Checking the result…"
        case .resources:
            let name = KitchenActivity.skillName(detail) ?? (tool.hasPrefix("mcp__") ? tool.split(separator: "_").dropFirst(2).first.map(String.init) : nil)
            return name.map { "Using \($0)…" } ?? "Fetching a skill…"
        case .commands:
            if script.contains("install") { return "Installing packages…" }
            if script.contains("build") { return "Building…" }
            if script.contains("lint") { return "Linting…" }
            if script.contains("server") || script.contains(" dev") { return "Starting a server…" }
            if tool.lowercased() == "write_stdin" { return "Waiting for output…" }
            return "Running a command…"
        case .other:
            if ["sleep", "wait"].contains(tool.lowercased()) { return "Waiting…" }
            return "Working…"
        }
    }

    /// The model's display name: the provider catalog's name for it when listed, otherwise its
    /// published identifier written out ("claude-opus-5-5" → "Claude Opus 5.5"), otherwise the
    /// provider. Internal identifiers with dates or paths are never shown as they are.
    static func modelName(_ model: String?, provider: String, catalog: [ExecutionModel]) -> String {
        let providerName = provider == Provider.claude.rawValue ? "Claude" : provider == Provider.codex.rawValue ? "Codex" : provider
        guard var id = model?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return providerName.isEmpty ? "Model unavailable" : providerName }
        if let listed = catalog.first(where: { $0.id == id || $0.id == "claude/" + id }), !listed.name.isEmpty, listed.name != listed.id,
           !listed.name.lowercased().hasPrefix("default") { return listed.name }
        if id.hasPrefix("claude/") { id.removeFirst(7) }
        // Drop a trailing date stamp ("-20251001").
        var parts = id.split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard !parts.isEmpty else { return providerName }
        var words: [String] = []
        var index = 0
        while index < parts.count {
            let part = parts[index]
            // Version numbers written as "5-5" read as "5.5".
            if part.allSatisfy(\.isNumber), index + 1 < parts.count, parts[index + 1].allSatisfy(\.isNumber), parts[index + 1].count <= 2 {
                words.append(part + "." + parts[index + 1]); index += 2; continue
            }
            words.append(part.lowercased() == "gpt" ? "GPT" : part.prefix(1).uppercased() + part.dropFirst())
            index += 1
        }
        if words.first == "GPT", words.count > 1, words[1].first?.isNumber == true { words[0] = "GPT-" + words.remove(at: 1) }
        if provider == Provider.claude.rawValue, words.first != "Claude" { words.insert("Claude", at: 0) }
        return words.joined(separator: " ")
    }
}

/// When the sidebar first saw each conversation, kept across launches so rows keep their place.
final class AgentSidebarOrder {
    static let shared = AgentSidebarOrder()
    private let defaults: UserDefaults
    private let key = "agentSidebar.firstSeen.v1"
    private var seen: [String: Date]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seen = (defaults.dictionary(forKey: key) as? [String: Double])?.mapValues { Date(timeIntervalSince1970: $0) } ?? [:]
    }
    func order(_ conversation: String, first: Date) -> Date {
        if let date = seen[conversation] { return date }
        seen[conversation] = first
        let snapshot = seen.mapValues(\.timeIntervalSince1970), defaults = defaults, key = key
        DispatchQueue.main.async { defaults.set(snapshot, forKey: key) }
        return first
    }
}

/// Collapsed groups, remembered per project.
enum AgentSidebarCollapse {
    static func key(_ project: String) -> String { "agentSidebar.collapsed." + project }
    static func load(_ project: String, defaults: UserDefaults = .standard) -> Set<AgentSidebarGroup> {
        Set((defaults.array(forKey: key(project)) as? [Int] ?? []).compactMap(AgentSidebarGroup.init(rawValue:)))
    }
    static func save(_ groups: Set<AgentSidebarGroup>, project: String, defaults: UserDefaults = .standard) {
        defaults.set(groups.map(\.rawValue).sorted(), forKey: key(project))
    }
}
