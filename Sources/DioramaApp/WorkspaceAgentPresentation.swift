import Foundation
import DioramaCore

enum WorkspaceAgentStatus: String, Equatable {
    case ready = "Ready", working = "Working", waiting = "Waiting"
    case done = "Done", stopped = "Stopped", failed = "Failed", unknown = "Unknown"

    init(reported: String) {
        switch reported.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") {
        case "ready", "idle": self = .ready
        case "running", "working", "inprogress", "submitting": self = .working
        case "pending", "spawnpending", "waiting", "waitingforinput", "awaitingapproval", "blocked": self = .waiting
        case "completed", "finished", "done", "lastturnfinished": self = .done
        case "interrupted", "stopped", "cancelled", "canceled", "shutdown": self = .stopped
        case "failed", "errored", "error", "lastturnfailed": self = .failed
        default: self = .unknown
        }
    }
}

enum WorkspaceAttentionReason: Equatable {
    case approval, input, other

    init(reported: String) {
        switch reported.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") {
        case "awaitingapproval": self = .approval
        case "waitingforinput": self = .input
        default: self = .other
        }
    }
}

enum WorkspaceAgentFreshness: String, Equatable {
    case recentlyObserved = "Recently observed", unavailable = "Unavailable"
    case ready = "Ready to start", live = "Live", lastKnown = "Last known", unverified = "Outcome unverified"
}

struct WorkspaceAgent: Identifiable, Equatable {
    let id: String
    var name: String
    var provider: String
    var task: String
    var action: String
    var status: WorkspaceAgentStatus
    var reportedStatus: String
    var freshness: WorkspaceAgentFreshness
    var parentID: String?
    var parentName: String?
    var activityRecordID: String?
    var observedAt: Date?
    var plan: AgentPlan? = nil
    var planUnavailable = false
    var attentionReason: WorkspaceAttentionReason = .other
    var branch: String?
    var worktree: String?
    var reportedModel: String?
    var completionKey: String?
    var latestActivity = ""
    /// Raw tool name and detail of the latest reported tool call, for kitchen station mapping.
    var latestTool = ""
    var latestToolDetail = ""
    /// Whether the current turn has edited files: before that, work is preparation.
    var turnHasEdits = false
    /// Files edited, commands run and tests in the current turn, for the progress panel.
    var turnWork = TurnWork()
    /// The distilled activity feed for the command bar (oldest first).
    var feed: [FeedEntry] = []
    /// When the agent last wrote a progress note, and last called a tool, in this turn (for the
    /// icon on its kitchen name tag).
    var lastCommentaryAt: Date?
    var lastToolAt: Date?
    var meaningfulUpdatedAt: Date?
    var meaningfulEventID = ""
    var meaningfulUpdateID: String { [meaningfulEventID, reportedStatus, latestActivity].joined(separator: "\u{1E}") }
    mutating func retainMeaningfulState(from previous: WorkspaceAgent) {
        status = previous.status; reportedStatus = previous.reportedStatus
        action = previous.action; latestActivity = previous.latestActivity
        latestTool = previous.latestTool; latestToolDetail = previous.latestToolDetail; turnHasEdits = previous.turnHasEdits
        turnWork = previous.turnWork
        feed = previous.feed
        lastCommentaryAt = previous.lastCommentaryAt; lastToolAt = previous.lastToolAt
        meaningfulUpdatedAt = previous.meaningfulUpdatedAt; meaningfulEventID = previous.meaningfulEventID
        attentionReason = previous.attentionReason
        completionKey = previous.completionKey
    }
    var overheadMessage: String? {
        if freshness == .unverified { return "Connection lost" }
        if freshness == .lastKnown { return "Last known" }
        switch status {
        case .waiting:
            switch attentionReason {
            case .approval: return "Needs Approval 🚨"
            case .input: return "Needs Your Input 💬"
            case .other: return "Waiting"
            }
        case .failed: return "Something went wrong ⚠️"
        case .unknown: return "Status unknown"
        default: return nil
        }
    }
    var isMain: Bool { id == "main" }
    var isWorking: Bool { status == .working && (freshness == .live || freshness == .recentlyObserved) }
    var statusLabel: String {
        if freshness == .unverified || freshness == .unavailable { return freshness.rawValue }
        if freshness == .recentlyObserved { return "Recently observed · " + status.rawValue }
        let label = status == .waiting && !reportedStatus.isEmpty ? reportedStatus : status.rawValue
        return freshness == .lastKnown ? "Last known · " + label : label
    }
    var accessibilityLabel: String { [name, statusLabel, action].filter { !$0.isEmpty }.joined(separator: " · ") }

    static let ready = WorkspaceAgent(id: "main", name: "Main agent", provider: "", task: "Start a conversation to begin.",
        action: "Ready for your first prompt", status: .ready, reportedStatus: "Ready", freshness: .ready)
}

/// Keeps desk order stable and retains agents if a bounded history snapshot drops older records.
struct WorkspaceAgentRoster {
    private(set) var agents: [WorkspaceAgent] = []
    mutating func update(_ incoming: [WorkspaceAgent]) {
        let present = Set(incoming.map(\.id))
        for index in agents.indices where !present.contains(agents[index].id) {
            agents[index].freshness = .lastKnown
        }
        for agent in incoming {
            if let index = agents.firstIndex(where: { $0.id == agent.id }) { agents[index] = agent }
            else { agents.append(agent) }
        }
    }
}

/// A source is one provider segment, so old history cannot make the current segment look live.
struct WorkspaceActivitySource {
    let provider: Provider
    let sessionID: String
    let snapshot: SessionActivitySnapshot
    let task: ExecutedTask?
    var fallbackStatus = "Unknown"
    var observation: ExternalObservationSnapshot?
    var now = Date()
    var paused = false
    var externalFreshness: WorkspaceAgentFreshness {
        if paused { return .lastKnown }
        guard let observation else { return .lastKnown }
        if observation.error != nil { return .unavailable }
        return observation.isRecent(at: now) ? .recentlyObserved : .lastKnown
    }

    var hasLiveExecution: Bool {
        task?.provider == provider && task?.attached == true && task?.phase != .disconnected
    }
    var isLive: Bool { hasLiveExecution && !snapshot.lastKnown }
}

enum WorkspaceAgentPresentation {
    static func agents(title: String, sources: [WorkspaceActivitySource]) -> [WorkspaceAgent] {
        guard let current = sources.last else { return [.ready] }
        // Fresh external evidence can supersede a detached task's saved lifecycle.
        let task = current.task?.attached == true || current.observation == nil ? current.task : nil
        // Active turns also set requiresReconciliation; only disconnection is uncertain.
        let uncertain = task?.phase == .disconnected
        let phase = task?.phase.rawValue ?? current.fallbackStatus
        let mainAction = current.snapshot.records.last {
            $0.kind == "tool" && ($0.parentID == nil || $0.parentID == current.sessionID)
                && WorkspaceAgentStatus(reported: $0.status) == .working
                && (task?.turnID == nil || $0.turnID == task?.turnID)
        }
        let mainStatus = uncertain ? WorkspaceAgentStatus.unknown : WorkspaceAgentStatus(reported: phase)
        var result = [WorkspaceAgent(id: "main", name: "Main agent", provider: current.provider.rawValue,
            task: title,
            action: mainStatus == .working ? action(mainAction) ?? "Working on the conversation" : phase,
            status: mainStatus, reportedStatus: phase,
            freshness: uncertain ? .unverified : current.hasLiveExecution ? .live : current.externalFreshness,
            observedAt: task?.activity.last(where: { $0.state != nil })?.time ?? current.observation?.activity.latestState?.time, attentionReason: WorkspaceAttentionReason(reported: phase))]
        var seen: Set<String> = []
        for source in sources {
            let records = source.snapshot.records.filter { $0.kind == "agent" }
            for record in records {
                let id = identity(record)
                guard seen.insert(id).inserted else { continue }
                let parent = records.first {
                    $0.nativeID == record.parentID || ($0.data["delegationID"].string != nil && $0.data["delegationID"].string == record.parentID)
                }
                let ownedTool = source.snapshot.records.last {
                    $0.kind == "tool" && $0.parentID != nil
                        && ($0.parentID == record.nativeID || $0.parentID == record.data["delegationID"].string)
                        && WorkspaceAgentStatus(reported: $0.status) == .working
                }
                let status = WorkspaceAgentStatus(reported: record.status)
                let runtime = record.data["runtimeStatus"]["type"].string ?? record.data["runtimeStatus"].string
                // Runtime idle is not completion. It also isn't evidence of live typing.
                let observedDuringAttachment = source.task?.liveStartedAt.map { record.observedAt >= $0 } ?? true
                let verified = source.isLive && observedDuringAttachment && runtime != "notLoaded" && runtime != "idle"
                let reportedAction = status == .working
                    ? action(ownedTool) ?? record.data["lastTool"].string : nil
                result.append(WorkspaceAgent(id: id,
                    name: record.reportedAgentName, provider: record.provider,
                    task: record.detail.isEmpty ? record.title : record.detail,
                    action: reportedAction ?? (record.title.isEmpty ? status.rawValue : record.title),
                    status: status, reportedStatus: record.status,
                    freshness: verified ? .live : (!source.paused && source.observation?.error == nil && source.observation != nil && record.recordedAt.map { source.now.timeIntervalSince($0) >= -2 && source.now.timeIntervalSince($0) < 30 } == true ? .recentlyObserved : .lastKnown),
                    parentID: parent.map(identity),
                    parentName: parent?.title ?? (record.parentID == nil || record.parentID == source.sessionID ? "Main agent" : "Unresolved parent"),
                    activityRecordID: record.id, observedAt: record.recordedAt ?? (verified ? record.observedAt : nil),
                    attentionReason: WorkspaceAttentionReason(reported: record.status)))
            }
        }
        for index in result.indices {
            let agent = result[index]
            let parts = agent.id.components(separatedBy: "\u{1F}")
            guard let source = agent.isMain ? sources.last : sources.first(where: { parts.count == 3 && $0.provider.rawValue == parts[0] && $0.sessionID == parts[1] }) else { continue }
            let owner = agent.isMain ? source.sessionID : (parts.last ?? "")
            let delegation = source.snapshot.records.first { $0.id == agent.activityRecordID }?.data["delegationID"].string
            let available = source.snapshot.events.isEmpty ? source.snapshot.records : source.snapshot.events
            let relevant = available.filter { event in
                ["tool", "agent", "state", "proposal", "checklist", "step"].contains(event.kind) &&
                    (agent.isMain ? event.parentID == nil || event.parentID == owner : event.nativeID == owner || event.parentID == owner || (delegation != nil && event.parentID == delegation))
            }
            // Preserve event order for untimestamped reports; explicit older events never win.
            var latest: SessionActivityRecord?
            for event in relevant {
                if let time = event.recordedAt, let previous = latest?.recordedAt, time < previous { continue }
                latest = event
            }
            let activity = agent.isMain ? (source.task?.attached == true ? source.task?.activity.last : source.observation?.activity.events.last) : nil
            let useActivity = activity != nil && (latest == nil || (activity?.recordedAt ?? .distantPast) >= (latest?.recordedAt ?? .distantPast))
            result[index].latestActivity = useActivity ? [activity?.label, activity?.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") : latest.map { [$0.title, $0.detail].filter { !$0.isEmpty }.joined(separator: " · ") } ?? agent.action
            result[index].latestActivity = String(result[index].latestActivity.prefix(500))
            // The kitchen shows the current turn's latest tool, also between calls (results,
            // plan steps and checklists name no tool).
            if useActivity {
                let stream = (source.task?.attached == true ? source.task?.activity : source.observation?.activity.events) ?? []
                var tool: ActivityEvent?, edits = false
                for event in stream.reversed() {
                    if event.kind == "started" || event.kind == "turnStarted" { break }
                    guard let name = event.tool, !name.isEmpty else { continue }
                    // Plan and checklist updates don't change what the chef is doing.
                    let planning = KitchenActivity.classify(tool: name, detail: event.detail ?? "") == .planning
                    if tool == nil || (tool?.tool).map({ KitchenActivity.classify(tool: $0) == .planning }) == true, !planning || tool == nil { tool = event }
                    if KitchenActivity.isEditing(tool: name, detail: event.detail ?? "") { edits = true; break }
                }
                result[index].latestTool = tool?.tool ?? ""
                result[index].latestToolDetail = String(KitchenActivity.withoutHeredocs(tool?.detail ?? "").prefix(500))
                result[index].turnHasEdits = edits
                result[index].turnWork = TurnWork.from(stream)
                result[index].feed = AgentActivityFeed.entries(from: stream)
                let turn = stream.lastIndex { $0.kind == "started" || $0.kind == "turnStarted" }.map { stream[($0 + 1)...] } ?? stream[...]
                result[index].lastCommentaryAt = turn.last { $0.kind == "commentary" }?.time
                result[index].lastToolAt = turn.last { $0.kind == "toolStarted" }?.time
                if agent.status != .working { result[index].turnWork.settle() }
            } else {
                let tools = relevant.filter { $0.kind == "tool" && (latest?.turnID == nil || $0.turnID == latest?.turnID) }
                // Plan and checklist updates don't change what the chef is doing.
                let working = tools.last { KitchenActivity.classify(tool: $0.title, detail: $0.data["command"].string ?? $0.detail) != .planning } ?? tools.last
                result[index].latestTool = working?.title ?? ""
                result[index].latestToolDetail = String(KitchenActivity.withoutHeredocs(working?.data["command"].string ?? working?.detail ?? "").prefix(500))
                result[index].turnHasEdits = tools.contains { KitchenActivity.isEditing(tool: $0.title, detail: $0.data["command"].string ?? $0.detail) }
                result[index].turnWork = TurnWork.from(tools)
                result[index].feed = AgentActivityFeed.entries(from: relevant)
                if agent.status != .working { result[index].turnWork.settle() }
            }
            result[index].meaningfulUpdatedAt = useActivity ? activity?.recordedAt : latest?.recordedAt
            result[index].meaningfulEventID = useActivity ? (activity.map(activityIdentity) ?? "") : latest.map { [$0.nativeID, $0.turnID ?? "", $0.kind, $0.status].joined(separator: ":") } ?? (source.task?.turnID ?? "")
            let record = source.snapshot.records.first { $0.id == agent.activityRecordID }
            let turn = agent.isMain ? (source.task?.turnID ?? source.task?.work.turnID ?? activity?.turnID ?? latest?.turnID) : record?.turnID
            if let turn, !turn.isEmpty {
                result[index].completionKey = source.provider.rawValue + ":" + source.sessionID + ":" + turn + (agent.isMain ? "" : ":agent:" + agent.id)
            }
            let reported = agent.isMain ? nil : record?.data["model"].string
            result[index].reportedModel = reported.flatMap { $0.isEmpty ? nil : $0 }
                ?? (agent.isMain ? source.snapshot.records.reversed().compactMap { $0.data["model"].string }.first : nil)

        }
        return result
    }

    static func activityIdentity(_ event: ActivityEvent) -> String {
        // Some history adapters assign a new UUID on every read. Use source evidence,
        // never that adapter UUID or observation time, to identify a meaningful report.
        [event.provider, event.sessionID, event.turnID ?? "", event.callID ?? "", event.kind,
         event.tool ?? "", event.state?.rawValue ?? "", event.detail ?? "",
         event.recordedAt.map { String($0.timeIntervalSince1970) } ?? ""].joined(separator: "\u{1F}")
    }
    private static func identity(_ record: SessionActivityRecord) -> String {
        [record.provider, record.sessionID, record.nativeID].joined(separator: "\u{1F}")
    }

    private static func action(_ record: SessionActivityRecord?) -> String? {
        guard let record else { return nil }
        switch record.title.lowercased() {
        case "filechange", "edit", "write", "multiedit": return "Editing files"
        case "websearch", "webfetch": return "Searching the web"
        case "read", "glob", "grep": return "Reading project files"
        case "commandexecution", "bash":
            return record.detail.isEmpty ? "Running a command" : record.detail
        default: return record.title.isEmpty ? nil : record.title
        }
    }
}

extension LibraryModel {
    func planSources(_ session: Session) -> [Session] {
        let segments = conversations.record(session.id)?.segments ?? [ConversationSegment(nativeID: session.sessionID, provider: session.provider, model: "")]
        var result = segments.flatMap { segment -> [Session] in
            guard let provider = Provider(rawValue: segment.provider) else { return [] }
            return portfolio.planSources(provider: provider, nativeID: segment.nativeID)
        }
        if !result.contains(where: { $0.url == session.url }) { result.append(session) }
        return result
    }
    func workspaceAgents(_ session: Session?) -> [WorkspaceAgent] {
        guard let session else { return [.ready] }
        let segments = conversations.record(session.id)?.segments
            ?? [ConversationSegment(nativeID: session.sessionID, provider: session.provider, model: "")]
        let sources = segments.compactMap { segment -> WorkspaceActivitySource? in
            guard let provider = Provider(rawValue: segment.provider) else { return nil }
            let task = execution.tasks[segment.nativeID]
            let selectedObservation = observations[provider.rawValue + ":" + segment.nativeID] ?? (segment.nativeID == session.sessionID ? observations[session.id] : nil)
            let background = portfolio.observation(for: provider, nativeID: segment.nativeID)
            let observation = [selectedObservation, background].compactMap { $0 }.max { $0.synchronizedAt < $1.synchronizedAt }
            var snapshot = execution.activitySnapshot(provider: provider, id: segment.nativeID)
            for child in portfolio.childRecords(provider: provider, nativeID: segment.nativeID) {
                if let index = snapshot.records.firstIndex(where: { $0.kind == "agent" && $0.nativeID == child.nativeID }) {
                    let previous = snapshot.records[index]
                    if (child.recordedAt ?? .distantPast) > (previous.recordedAt ?? .distantPast) {
                        var latest = child
                        latest.id = previous.id
                        if AgentDisplayNames.meaningful(previous.reportedAgentName) {
                            latest.data = .object(["agentNickname": .string(previous.reportedAgentName)])
                        }
                        snapshot.apply(latest)
                    }
                } else { snapshot.apply(child) }
            }
            return WorkspaceActivitySource(provider: provider, sessionID: segment.nativeID, snapshot: snapshot,
                task: task?.provider == provider ? task : nil, fallbackStatus: observation?.activity.state.rawValue ?? summary(session).state.rawValue,
                observation: observation, now: observationClock, paused: paused)
        }
        var agents = workspaceProjectionCache.agents(id: session.id, title: session.title, sources: sources)
        for index in agents.indices {
            let agent = agents[index]
            let parts = agent.id.components(separatedBy: "\u{1F}")
            guard let source = agent.isMain ? sources.last : sources.first(where: { parts.count == 3 && $0.provider.rawValue == parts[0] && $0.sessionID == parts[1] }) else { continue }
            let discovered = planSources(session).filter { $0.provider == source.provider }
            let native = parts.last ?? ""
            let child = agent.isMain ? nil : discovered.first { $0.classification == .subagent && ($0.provider == .claude ? $0.id == native : $0.sessionID == native) }
            let file = child ?? discovered.first { $0.classification != .subagent && $0.sessionID == source.sessionID }
            var snapshot = file.flatMap { planDiscovery.snapshots[AgentPlanDiscovery.key($0)] } ?? .init()
            // Merge current evidence by record identity; never let saved history overwrite newer events.
            let separateCodexChild = !agent.isMain && source.provider == .codex
            let live = separateCodexChild ? execution.activitySnapshot(provider: .codex, id: native) : source.snapshot
            if child?.provider != .claude { // Claude child files share their parent's native session ID.
                snapshot = AgentPlan.merging(snapshot, live)
            }
            let record = source.snapshot.records.first { $0.id == agent.activityRecordID }
            let owners = agent.isMain || child != nil || separateCodexChild ? Set<String>() : Set([record?.nativeID, record?.data["delegationID"].string].compactMap { $0 })
            if !agent.isMain && child == nil && !separateCodexChild && owners.isEmpty { continue }
            let plan = AgentPlan.reported(in: snapshot, provider: source.provider.rawValue,
                sessionID: child?.sessionID ?? (separateCodexChild ? native : source.sessionID), owners: owners, currentTurn: agent.isMain ? source.task?.turnID : nil)
            agents[index].plan = plan
            agents[index].planUnavailable = !source.hasLiveExecution && (file.map { planDiscovery.unavailable.contains(AgentPlanDiscovery.key($0)) } ?? false)
        }
        let metadataSources = planSources(session)
        let workspaces = projects.projects.flatMap(\.workspaces)
        for index in agents.indices {
            agents[index].name = agentDisplayName(session, agent: agents[index].id, reported: agents[index].name)
            let agent = agents[index], parts = agent.id.components(separatedBy: "\u{1F}")
            let child = agent.isMain ? nil : metadataSources.first { $0.classification == .subagent && ($0.provider == .claude ? $0.id == parts.last : $0.sessionID == parts.last) }
            let native = agent.isMain ? session.sessionID : (parts.last ?? "")
            let runtime = execution.tasks.values.first { $0.id == native && $0.provider.rawValue == agent.provider }
            let folder = runtime?.folder ?? (agent.isMain ? session.project : child?.project)
            if agent.isMain, (agent.provider == Provider.claude.rawValue || agent.completionKey == nil), [.done, .failed, .stopped].contains(agent.status),
               let completion = AgentCompletionViews.shared.latest[agent.provider + ":" + native] {
                agents[index].completionKey = completion.id
            }
            agents[index].worktree = folder.flatMap { $0.isEmpty ? nil : $0 }
            agents[index].branch = workspaces.first { !$0.cleaned && $0.folder == folder && !$0.branch.isEmpty }?.branch
        }
        let displayNames = Dictionary(agents.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for index in agents.indices where !agents[index].isMain {
            agents[index].parentName = agents[index].parentID.flatMap { displayNames[$0] } ?? displayNames["main"]
        }
        return agents
    }
}

/// Values that can change the agent projection. Freshness is a derived state, so its
/// boundary invalidates the cache without tying every entry to a wall-clock tick.
struct WorkspaceProjectionSource: Equatable {
    let provider: Provider
    let sessionID: String
    let snapshot: SessionActivitySnapshot
    let phase: String
    let attached: Bool
    let turnID: String?
    let prompt: String?
    let eventTime: Date?
    let lastActivity: ActivityEvent?
    let observationState: String?
    let observationTime: Date?
    let freshness: WorkspaceAgentFreshness
    let fallback: String
    let liveStartedAt: Date?
    let recentChildren: Set<String>
    init(_ source: WorkspaceActivitySource) {
        provider = source.provider; sessionID = source.sessionID; snapshot = source.snapshot
        phase = source.task?.phase.rawValue ?? source.fallbackStatus
        attached = source.hasLiveExecution; turnID = source.task?.turnID
        prompt = source.task?.transcript.entries.last(where: { $0.kind == "You" })?.text
        eventTime = source.task?.activity.last(where: { $0.state != nil })?.time
        lastActivity = source.task?.attached == true ? source.task?.activity.last : source.observation?.activity.events.last
        observationState = source.observation?.activity.state.rawValue
        observationTime = source.observation?.activity.latestState?.time
        freshness = source.externalFreshness
        fallback = source.fallbackStatus
        liveStartedAt = source.task?.liveStartedAt
        recentChildren = Set(source.snapshot.records.filter { record in
            record.kind == "agent" && !source.paused && source.observation != nil && source.observation?.error == nil
                && record.recordedAt.map { source.now.timeIntervalSince($0) >= -2 && source.now.timeIntervalSince($0) < 30 } == true
        }.map(\.id))
    }
}

final class WorkspaceProjectionCache {
    struct Entry {
        var title: String
        var sources: [WorkspaceProjectionSource]
        var agents: [WorkspaceAgent]
        var history: [String: [String]] = [:]
    }
    var entries: [String: Entry] = [:]
    private(set) var rebuilds = 0
    func agents(id: String, title: String, sources: [WorkspaceActivitySource]) -> [WorkspaceAgent] {
        let keys = sources.map(WorkspaceProjectionSource.init)
        if let cached = entries[id], cached.title == title, cached.sources == keys { return cached.agents }
        rebuilds += 1
        var agents = WorkspaceAgentPresentation.agents(title: title, sources: sources)
        var history = entries[id]?.history ?? [:]
        if let previous = entries[id] {
            for index in agents.indices {
                if let old = previous.agents.first(where: { $0.id == agents[index].id }) {
                    let key = agents[index].meaningfulUpdateID
                    let replay = key != old.meaningfulUpdateID && (history[old.id] ?? []).contains(key)
                    let older = agents[index].meaningfulUpdatedAt.map { time in old.meaningfulUpdatedAt.map { time < $0 } ?? false } ?? false
                    let runtimeChanged = agents[index].freshness == .live && (agents[index].status != old.status || agents[index].attentionReason != old.attentionReason)
                    if (replay || older) && !runtimeChanged { agents[index].retainMeaningfulState(from: old) }
                }
            }
        }
        // Bounded snapshots omit older subagent records. Keep their last known state
        // until the owning conversation leaves project membership/archive filtering.
        let present = Set(agents.map(\.id))
        for var old in entries[id]?.agents ?? [] where !present.contains(old.id) {
            old.freshness = .lastKnown
            agents.append(old)
        }
        for agent in agents where !(history[agent.id] ?? []).contains(agent.meaningfulUpdateID) {
            history[agent.id, default: []].append(agent.meaningfulUpdateID)
            if history[agent.id, default: []].count > 128 { history[agent.id]?.removeFirst() }
        }
        entries[id] = Entry(title: title, sources: keys, agents: agents, history: history)
        return agents
    }
}
