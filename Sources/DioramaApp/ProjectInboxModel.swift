import Foundation
import Observation
import DioramaCore

struct InboxSource: Sendable {
    var project: String
    var conversation: String
    var title: String
    var session: Session
    var aliases: [String] = []
    var agentName: String = "Main agent"
    var key: String { project + ":" + conversation + ":" + session.id }
}

@Observable final class ProjectInboxModel {
    let store: ProjectInboxStore
    var revision = 0
    var notice: String?
    var historyNotices: [String: String] = [:]
    var indexing = false
    @ObservationIgnored private var sourceWarnings: [String: (String, String)] = [:]
    @ObservationIgnored private let started = Date()
    @ObservationIgnored private var pending: [String: InboxSource] = [:]
    @ObservationIgnored private var stamps: [String: String] = [:]
    @ObservationIgnored private var publication: Task<Void, Never>?
    private func publish() {
        guard publication == nil else { return }
        publication = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }; self.revision += 1; self.publication = nil
        }
    }
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let history = ProjectInboxHistoryReader()
    @ObservationIgnored private var liveWorker: Task<Void, Never>?
    @ObservationIgnored private let liveHistory = InboxLiveHistory()
    init(store: ProjectInboxStore = ProjectInboxStore()) { self.store = store }
    func enqueue(_ sources: [InboxSource]) {
        for source in sources {
            let stamp = "\(source.session.modified.timeIntervalSince1970):\(source.session.bytes):\(source.session.url?.path ?? ""):\(source.agentName):\(source.title)"
            guard stamps[source.key] != stamp else { continue }
            pending[source.key] = source
        }
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            self.indexing = true
            defer { self.worker = nil; self.indexing = false }
            while !self.pending.isEmpty, !Task.isCancelled {
                let batch = Array(self.pending.values.sorted { $0.session.modified > $1.session.modified }.prefix(2))
                for source in batch { self.pending.removeValue(forKey: source.key) }
                let history = self.history
                let results = await withTaskGroup(of: (InboxSource, ProjectInboxHistory.Result).self) { group in
                    for source in batch { group.addTask { (source, await history.read(source.session, identity: source.key)) } }
                    var results: [(InboxSource, ProjectInboxHistory.Result)] = []
                    for await result in group { results.append(result) }
                    return results
                }
                for (source, result) in results {
                    AgentCompletionViews.shared.register(result.updates, provider: source.session.provider.rawValue, session: source.session.sessionID)
                    if let notice = result.notice { self.sourceWarnings[source.key] = (source.project, notice) }
                    else { self.sourceWarnings.removeValue(forKey: source.key) }
                    let warning = self.sourceWarnings.values.filter { $0.0 == source.project }.map { $0.1 }.sorted().first
                    if self.historyNotices[source.project] != warning { self.historyNotices[source.project] = warning }
                    do {
                        if try await self.store.merge(project: source.project, conversation: source.conversation, previous: source.aliases) { self.publish() }
                        if try await self.store.ingest(project: source.project, conversation: source.conversation, title: source.title,
                            updates: result.updates, agentName: source.agentName, historicalBefore: self.started, sourceModified: source.session.modified) { self.publish() }
                        let threadID = source.project + ":" + source.conversation
                        if let thread = try await self.store.summaries([threadID])[threadID] {
                            for reference in thread.updates.suffix(20) { AgentCompletionViews.shared.seed(reference.id, unread: !reference.read, historicalUnread: true) }
                        }
                        if source.session.url != nil {
                            self.stamps[source.key] = "\(source.session.modified.timeIntervalSince1970):\(source.session.bytes):\(source.session.url?.path ?? ""):\(source.agentName):\(source.title)"
                        }
                    } catch { self.notice = "Inbox could not save: " + error.localizedDescription }
                }
            }
        }
    }
    func live(_ source: InboxSource, event: WireValue, entries: [Entry]) {
        let preceding = liveWorker
        liveWorker = Task {
            await preceding?.value
            let updates = await liveHistory.receive(source.session, event: event, entries: entries)
            AgentCompletionViews.shared.register(updates, provider: source.session.provider.rawValue, session: source.session.sessionID)
            for update in updates { AgentCompletionViews.shared.seed(update.id, unread: true) }
            do {
                if try await store.ingest(project: source.project, conversation: source.conversation, title: source.title,
                                          updates: updates, agentName: source.agentName, historicalBefore: started) { publish() }
            } catch { notice = "Inbox could not save: " + error.localizedDescription }
        }
    }
    func act(_ id: String, _ action: InboxAction, viewed: Set<String>? = nil, through: String? = nil) async {
        do { if try await store.act(id, action, viewed: viewed, through: through) { revision += 1 } }
        catch { notice = "Inbox change was not saved: " + error.localizedDescription }
    }
}

private actor InboxLiveHistory {
    private var buffers: [String: Data] = [:]
    private var latest: [String: InboxUpdate] = [:]
    func receive(_ session: Session, event: WireValue, entries: [Entry]) -> [InboxUpdate] {
        let p = event["params"]
        if session.provider == .claude, event["method"].string == "diorama/claudeActivity" {
            let row = p["event"]
            guard row["parent_tool_use_id"].string == nil else { return [] }
            if row["type"].string == "user", !row["message"]["content"].array.contains(where: { $0["type"].string == "tool_result" }) { buffers[session.id] = Data(); latest.removeValue(forKey: session.id) }
            guard let data = try? JSONEncoder().encode(row) else { return [] }
            if buffers.values.reduce(0, { $0 + $1.count }) > 64 * 1024 * 1024 { buffers.removeAll() }
            if buffers[session.id, default: Data()].count + data.count > 16 * 1024 * 1024 { buffers[session.id] = Data() }
            buffers[session.id, default: Data()].append(data); buffers[session.id]?.append(10)
            let terminal = row["type"].string == "result" || row["message"]["stop_reason"].string == "end_turn"
            guard terminal else { return [] }
            let result = ProjectInboxHistory.parse(buffers[session.id] ?? Data(), session: session).updates
            if let last = result.last { latest[session.id] = last }
            if row["type"].string == "result" { buffers.removeValue(forKey: session.id) }
            return result
        }
        if session.provider == .claude, event["method"].string == "turn/completed", var last = latest.removeValue(forKey: session.id) {
            last.outcome = p["turn"]["status"].string ?? "unknown"; last.runtimeOutcome = true
            return [last]
        }
        guard session.provider == .codex, event["method"].string == "turn/completed", let turn = p["turn"]["id"].string else { return [] }
        return InboxUpdate.make(session: session, turn: turn, entries: entries, outcome: p["turn"]["status"].string ?? "unknown",
                                date: ActivityParser.date(p["timestamp"].string)).map { value in var reported = value; reported.runtimeOutcome = true; return [reported] } ?? []
    }
}

extension LibraryModel {
    func inboxSources() -> [InboxSource] {
        projects.projects.flatMap { project in
            projects.sessions(project, library: self).filter { $0.parentID == nil && $0.classification != .subagent && $0.classification != .internalReview }.flatMap { session in
                planSources(session).filter { $0.parentID == nil && $0.classification != .subagent }.map {
                    InboxSource(project: project.id, conversation: session.id, title: markdownTitle(session.title), session: $0, aliases: conversations.record(session.id)?.segments.map { $0.provider + ":" + $0.nativeID } ?? [], agentName: agentDisplayName(session, project: project.id))
                }
            }
        }
    }
    func refreshProjectInbox() { guard !paused else { return }; projectInbox.enqueue(inboxSources()) }
}
