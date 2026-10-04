import Foundation

/// Published provider evidence, independent of execution status. Completed plans remain inspectable.
public struct AgentPlan: Equatable, Sendable {
    public var checklist: [SessionActivityRecord]
    public var proposal: SessionActivityRecord?
    public var taskUpdatedAt: Date?
    public var proposalUpdatedAt: Date?
    public var tasksPreviousTurn: Bool
    public var proposalPreviousTurn: Bool
    public var updatedAt: Date?
    public var previousTurn: Bool
    public var truncated: Bool
    public var hasTasks: Bool { !checklist.isEmpty }
    public var hasProposal: Bool { proposal?.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    public var completedTaskCount: Int { checklist.filter { $0.status == "completed" }.count }
    public var taskProgress: String { "\(completedTaskCount)/\(checklist.count)" }
    public var hasContent: Bool { hasTasks || hasProposal }

    public static func reported(in snapshot: SessionActivitySnapshot, provider: String, sessionID: String,
                                owners: Set<String> = [], currentTurn: String? = nil) -> Self {
        let records = snapshot.records.filter {
            $0.provider == provider && $0.sessionID == sessionID &&
                (owners.isEmpty ? ($0.parentID == nil || $0.parentID == sessionID) : $0.parentID.map(owners.contains) == true)
        }
        let steps = records.filter { $0.kind == "step" && $0.status != "deleted" }
        let proposal = records.filter { $0.kind == "proposal" }.max {
            ($0.recordedAt ?? $0.observedAt) < ($1.recordedAt ?? $1.observedAt)
        }
        let evidence = steps + [proposal].compactMap { $0 }
        let turn = currentTurn ?? snapshot.currentPlanTurnID ?? snapshot.codexTurn ?? records.last(where: { $0.kind == "turn" })?.nativeID
        func previous(_ items: [SessionActivityRecord]) -> Bool {
            turn.map { current in !items.isEmpty && items.allSatisfy { $0.turnID != nil && $0.turnID != current } } ?? false
        }
        let taskEvidence = records.filter { ["step", "checklist"].contains($0.kind) }
        return Self(checklist: steps, proposal: proposal,
                    taskUpdatedAt: taskEvidence.compactMap(\.recordedAt).max(), proposalUpdatedAt: proposal?.recordedAt,
                    tasksPreviousTurn: previous(steps), proposalPreviousTurn: previous([proposal].compactMap { $0 }), updatedAt: evidence.compactMap(\.recordedAt).max(),
                    previousTurn: turn.map { current in !evidence.isEmpty && evidence.allSatisfy { $0.turnID != nil && $0.turnID != current } } ?? false,
                    truncated: snapshot.truncated)
    }
}

/// Cached bounded history reads run off the main actor. A missing source retains known evidence.
public actor AgentPlanHistory {
    private struct Entry {
        var modified: Date
        var size: Int
        var snapshot: SessionActivitySnapshot
    }
    private var entries: [String: Entry] = [:]
    public struct Result: Sendable {
        public var snapshot: SessionActivitySnapshot
        public var unavailable: Bool
    }
    public init() {}
    public func read(_ session: Session) async -> Result {
        let key = session.url?.path ?? session.id
        guard let url = session.url,
              let values = try? FileManager.default.attributesOfItem(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path),
              let modified = values[.modificationDate] as? Date, let size = values[.size] as? Int else {
            return Result(snapshot: entries[key]?.snapshot ?? .init(), unavailable: true)
        }
        if let entry = entries[key], entry.modified == modified, entry.size == size {
            return Result(snapshot: entry.snapshot, unavailable: false)
        }
        var snapshot = await SessionActivityHistory.read(session)
        snapshot.records.removeAll { !["step", "checklist", "proposal", "turn"].contains($0.kind) }
        snapshot.events = []; snapshot.seenEventIDs = []
        if let old = entries[key] {
            // Rotation/truncation is not an explicit provider request to clear a plan.
            if size < old.size { snapshot.truncated = true }
            snapshot = AgentPlan.merging(old.snapshot, snapshot)
            if snapshot.records.count > 2000 {
                snapshot.records.removeFirst(snapshot.records.count - 2000); snapshot.truncated = true
            }
        }
        guard !Task.isCancelled else { return Result(snapshot: entries[key]?.snapshot ?? .init(), unavailable: true) }
        entries[key] = Entry(modified: modified, size: size, snapshot: snapshot)
        return Result(snapshot: snapshot, unavailable: false)
    }
}

extension AgentPlan {
    /// Checklist replacements are authoritative for their owner, including an empty revision.
    /// Other plan records merge by identity so selected and background observations can coexist.
    public static func merging(_ saved: SessionActivitySnapshot, _ observed: SessionActivitySnapshot) -> SessionActivitySnapshot {
        var result = saved
        var staleOwners = Set<String>()
        func owner(_ record: SessionActivityRecord) -> String { [record.provider, record.sessionID, record.parentID ?? ""].map { String($0.utf8.count) + ":" + $0 }.joined() }
        let checklists = Dictionary(grouping: observed.records.filter { $0.kind == "checklist" }, by: owner).values.compactMap { revisions in
            revisions.max { ($0.recordedAt ?? $0.observedAt) < ($1.recordedAt ?? $1.observedAt) }
        }
        for checklist in checklists {
            let previous = saved.records.filter { $0.kind == "checklist" && $0.provider == checklist.provider && $0.sessionID == checklist.sessionID && $0.parentID == checklist.parentID }
                .max { ($0.recordedAt ?? $0.observedAt) < ($1.recordedAt ?? $1.observedAt) }
            if previous == nil || (checklist.recordedAt ?? checklist.observedAt) >= (previous!.recordedAt ?? previous!.observedAt) {
                result.records.removeAll { $0.kind == "step" && $0.provider == checklist.provider && $0.sessionID == checklist.sessionID && $0.parentID == checklist.parentID }
            } else { staleOwners.insert(owner(checklist)) }
        }
        for record in observed.records where ["step", "checklist", "proposal", "turn"].contains(record.kind) {
            if ["step", "checklist"].contains(record.kind), staleOwners.contains(owner(record)) { continue }
            if let index = result.records.firstIndex(where: { $0.id == record.id }) {
                let previous = result.records[index]
                if (record.recordedAt ?? record.observedAt) >= (previous.recordedAt ?? previous.observedAt) { result.records[index] = record }
            } else { result.records.append(record) }
        }
        result.currentPlanTurnID = observed.currentPlanTurnID ?? saved.currentPlanTurnID
        result.codexTurn = observed.codexTurn ?? saved.codexTurn
        result.truncated = saved.truncated || observed.truncated
        return result
    }
}
