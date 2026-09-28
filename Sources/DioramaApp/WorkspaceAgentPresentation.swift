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
    var attentionReason: WorkspaceAttentionReason = .other
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
        let task = current.task
        // Active turns also set requiresReconciliation; only disconnection is uncertain.
        let uncertain = task?.phase == .disconnected
        let phase = task?.phase.rawValue ?? current.fallbackStatus
        let latestPrompt = task?.transcript.entries.last(where: { $0.kind == "You" })?.text
        let mainAction = current.snapshot.records.last {
            $0.kind == "tool" && ($0.parentID == nil || $0.parentID == current.sessionID)
                && WorkspaceAgentStatus(reported: $0.status) == .working
                && (task?.turnID == nil || $0.turnID == task?.turnID)
        }
        let mainStatus = uncertain ? WorkspaceAgentStatus.unknown : WorkspaceAgentStatus(reported: phase)
        var result = [WorkspaceAgent(id: "main", name: "Main agent", provider: current.provider.rawValue,
            task: latestPrompt ?? title,
            action: mainStatus == .working ? action(mainAction) ?? "Working on the conversation" : phase,
            status: mainStatus, reportedStatus: phase,
            freshness: uncertain ? .unverified : current.hasLiveExecution ? .live : current.externalFreshness,
            attentionReason: WorkspaceAttentionReason(reported: phase))]
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
                    name: record.title.isEmpty ? "Subagent" : record.title, provider: record.provider,
                    task: record.detail.isEmpty ? record.title : record.detail,
                    action: reportedAction ?? (record.title.isEmpty ? status.rawValue : record.title),
                    status: status, reportedStatus: record.status,
                    freshness: verified ? .live : (!source.paused && source.observation?.error == nil && source.observation != nil && record.recordedAt.map { source.now.timeIntervalSince($0) >= -2 && source.now.timeIntervalSince($0) < 30 } == true ? .recentlyObserved : .lastKnown),
                    parentID: parent.map(identity),
                    parentName: parent?.title ?? (record.parentID == nil || record.parentID == source.sessionID ? "Main agent" : "Unresolved parent"),
                    activityRecordID: record.id, observedAt: record.recordedAt ?? record.observedAt,
                    attentionReason: WorkspaceAttentionReason(reported: record.status)))
            }
        }
        return result
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
    func workspaceAgents(_ session: Session?) -> [WorkspaceAgent] {
        guard let session else { return [.ready] }
        let segments = conversations.record(session.id)?.segments
            ?? [ConversationSegment(nativeID: session.sessionID, provider: session.provider, model: "")]
        let sources = segments.compactMap { segment -> WorkspaceActivitySource? in
            guard let provider = Provider(rawValue: segment.provider) else { return nil }
            let task = execution.tasks[segment.nativeID]
            return WorkspaceActivitySource(provider: provider, sessionID: segment.nativeID,
                snapshot: execution.activitySnapshot(provider: provider, id: segment.nativeID),
                task: task?.provider == provider ? task : nil, fallbackStatus: summary(session).state.rawValue,
                observation: observations[provider.rawValue + ":" + segment.nativeID] ?? (segment.nativeID == session.sessionID ? observations[session.id] : nil),
                now: observationClock, paused: paused)
        }
        return WorkspaceAgentPresentation.agents(title: session.title, sources: sources)
    }
}
