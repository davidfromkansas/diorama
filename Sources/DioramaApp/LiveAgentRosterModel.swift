import Foundation
import Observation
import DioramaCore

struct AgentRosterRow: Identifiable, Equatable {
    var agent: SpatialAgent
    var updated: Date
    var revision = 0
    var changedAt: Date?
    var id: String { agent.id }
    var taskTitle: String { TaskTitle.compact(agent.value.task) }
    var sidebarStatus: AgentSidebarStatus = .unknown
    var recent: Bool { [.done, .stopped, .failed].contains(agent.value.status) }
    var destination: SpatialFocus { OfficeOccupant(agent: agent, assignment: agent.value.task).destination }
}

struct AgentRosterRecency: Codable, Equatable {
    var updated: Date
    var eventID: String
    var seen: [String]
}

/// Receipt times are assigned once. Replays and observation freshness never advance recency.
struct AgentRosterReducer {
    private(set) var rows: [String: AgentRosterRow] = [:]
    private var seen: [String: [String]] = [:]
    private var initialTimes: [String: Date] = [:]
    private var restored: [String: AgentRosterRecency] = [:]
    init(initialTimes: [String: Date] = [:], restored: [String: AgentRosterRecency] = [:]) {
        self.initialTimes = initialTimes; self.restored = restored
        seen = restored.mapValues(\.seen)
    }
    mutating func updateStatuses(_ viewed: (WorkspaceAgent) -> Bool) {
        for id in rows.keys {
            guard let agent = rows[id]?.agent.value else { continue }
            rows[id]?.sidebarStatus = AgentSidebarStatus.resolve(agent, viewed: viewed(agent))
        }
    }
    var checkpoints: [String: AgentRosterRecency] {
        var result = restored
        for (id,row) in rows { result[id] = .init(updated:row.updated,eventID:row.agent.value.meaningfulUpdateID,seen:seen[id] ?? []) }
        return result
    }
    var activityTimes: [String: Date] { initialTimes.merging(rows.mapValues(\.updated)) { _, new in new } }
    mutating func ingest(_ agents: [SpatialAgent], received: Date) {
        let alive = Set(agents.map(\.id))
        rows = rows.filter { alive.contains($0.key) }
        seen = seen.filter { alive.contains($0.key) }
        initialTimes = initialTimes.filter { alive.contains($0.key) }
        restored = restored.filter { alive.contains($0.key) }
        for agent in agents {
            let key = agent.value.meaningfulUpdateID
            if var old = rows[agent.id] {
                let runtimeChanged = agent.value.freshness == .live && (agent.value.status != old.agent.value.status || agent.value.attentionReason != old.agent.value.attentionReason)
                let isNew = key != old.agent.value.meaningfulUpdateID && (runtimeChanged || !(seen[agent.id] ?? []).contains(key))
                let isOlder = agent.value.meaningfulUpdatedAt.map { time in old.agent.value.meaningfulUpdatedAt.map { time < $0 } ?? false } ?? false
                let ignoreOldEvidence = isOlder && !runtimeChanged
                if isNew && !ignoreOldEvidence {
                    old.updated = runtimeChanged && isOlder ? received : agent.value.meaningfulUpdatedAt ?? received
                    old.revision += 1
                    old.changedAt = received
                }
                // The normalized projection rejects old evidence too; retain newest activity
                // here defensively for callers using a bounded or replayed fixture snapshot.
                var next = agent
                if ignoreOldEvidence || (!isNew && key != old.agent.value.meaningfulUpdateID) {
                    next.value.retainMeaningfulState(from: old.agent.value)
                }
                old.agent = next
                rows[agent.id] = old
            } else {
                let previousTime = initialTimes.removeValue(forKey: agent.id)
                let checkpoint = restored.removeValue(forKey: agent.id)
                let newEvent = checkpoint.map { $0.eventID != key && !$0.seen.contains(key) } ?? false
                let knownTime = checkpoint?.updated ?? previousTime
                let reported = agent.value.meaningfulUpdatedAt
                let updated: Date
                if newEvent { updated = max(knownTime ?? .distantPast, reported ?? received) }
                else { updated = max(knownTime ?? .distantPast, reported ?? knownTime ?? received) }
                rows[agent.id] = AgentRosterRow(agent: agent, updated: updated)
            }
            if !(seen[agent.id] ?? []).contains(key) {
                seen[agent.id, default: []].append(key)
                if seen[agent.id, default: []].count > 128 { seen[agent.id]?.removeFirst() }
            }
        }
    }
    var ordered: [AgentRosterRow] {
        rows.values.sorted {
            if $0.sidebarStatus != $1.sidebarStatus { return $0.sidebarStatus.rawValue < $1.sidebarStatus.rawValue }
            return $0.updated == $1.updated ? $0.id < $1.id : $0.updated > $1.updated
        }
    }
}

struct AgentRosterAnchor: Equatable {
    var id: String
    var offset: Double
}

@Observable final class LiveAgentRosterModel {
    var collapsed = false
    var recentExpanded = false
    private(set) var rows: [AgentRosterRow] = []
    var newActivity = false
    var jumpRevision = 0
    @ObservationIgnored var anchor: AgentRosterAnchor?
    @ObservationIgnored private var reducer = AgentRosterReducer()
    @ObservationIgnored private var publication: Task<Void, Never>?
    @ObservationIgnored private var lastPublication = -Double.infinity
    @ObservationIgnored private var pressed = false
    @ObservationIgnored private var active = true
    @ObservationIgnored private var pending = false
    @ObservationIgnored private(set) var publicationCount = 0

    func ingest(_ agents: [SpatialAgent], now: Date = Date()) {
        reducer.ingest(agents, received: now)
        pending = true
        schedule()
    }
    func setActive(_ value: Bool) {
        active = value
        if value { schedule() } else { publication?.cancel(); publication = nil }
    }
    func setPressed(_ value: Bool) {
        pressed = value
        if !value { schedule() }
    }
    private func schedule() {
        guard active, !pressed, pending, publication == nil else { return }
        let delay = max(0, 0.25 - (ProcessInfo.processInfo.systemUptime - lastPublication))
        publication = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.publication = nil
            guard self.active, !self.pressed else { return }
            self.publish()
        }
    }
    private func publish() {
        reducer.updateStatuses { AgentCompletionViews.shared.isViewed($0) }
        let next = reducer.ordered
        pending = false
        lastPublication = ProcessInfo.processInfo.systemUptime
        if next != rows { rows = next; publicationCount += 1 }
    }
    /// Used by deterministic fixtures, with the same reducer and publication path.
    func flushForTesting() { publication?.cancel(); publication = nil; if !pressed { publish() } }
}
