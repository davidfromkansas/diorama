import Foundation

/// Published provider evidence, independent of execution status. Completed plans remain inspectable.
public struct AgentPlan: Equatable, Sendable {
    /// The current list: steps touched this turn plus earlier steps still open. Without any step
    /// touched this turn, the whole last list (flagged `tasksPreviousTurn`).
    public var checklist: [SessionActivityRecord]
    /// Steps finished in earlier turns, kept for the plan's history but out of this turn's count
    /// (Claude's task list lasts the whole session).
    public var earlier: [SessionActivityRecord] = []
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

    /// What a progress indicator can honestly show.
    public enum Progress: Equatable, Sendable {
        /// A list kept this turn: a real fraction.
        case steps(done: Int, total: Int)
        /// A new turn began (feedback, a follow-up) and the agent hasn't revised its earlier
        /// list yet: show that list dimmed as being updated.
        case revising(done: Int, total: Int)
        /// Working without a list: activity, not a fraction.
        case working
        case none
        public var fraction: Double? {
            switch self {
            case .steps(let done, let total), .revising(let done, let total): total > 0 ? Double(done) / Double(total) : nil
            default: nil
            }
        }
    }
    /// - Parameters:
    ///   - working: the agent's turn is running.
    ///   - actedThisTurn: it has already done real (non-planning) work this turn, so an earlier
    ///     list that it didn't revise no longer describes what it's doing.
    public func progress(working: Bool, actedThisTurn: Bool) -> Progress {
        if hasTasks, !tasksPreviousTurn { return .steps(done: completedTaskCount, total: checklist.count) }
        if working, hasTasks, !actedThisTurn { return .revising(done: completedTaskCount, total: checklist.count) }
        return working ? .working : .none
    }

    public static func reported(in snapshot: SessionActivitySnapshot, provider: String, sessionID: String,
                                owners: Set<String> = [], currentTurn: String? = nil) -> Self {
        let records = snapshot.records.filter {
            $0.provider == provider && $0.sessionID == sessionID &&
                (owners.isEmpty ? ($0.parentID == nil || $0.parentID == sessionID) : $0.parentID.map(owners.contains) == true)
        }
        var steps = records.filter { $0.kind == "step" && $0.status != "deleted" }
        let proposal = records.filter { $0.kind == "proposal" }.max {
            ($0.recordedAt ?? $0.observedAt) < ($1.recordedAt ?? $1.observedAt)
        }
        let evidence = steps + [proposal].compactMap { $0 }
        let turn = currentTurn ?? snapshot.currentPlanTurnID ?? snapshot.codexTurn ?? records.last(where: { $0.kind == "turn" })?.nativeID
        func previous(_ items: [SessionActivityRecord]) -> Bool {
            turn.map { current in !items.isEmpty && items.allSatisfy { $0.turnID != nil && $0.turnID != current } } ?? false
        }
        let taskEvidence = records.filter { ["step", "checklist"].contains($0.kind) }
        var earlier: [SessionActivityRecord] = []
        if let turn, steps.contains(where: { $0.turnID == turn }) {
            earlier = steps.filter { $0.turnID != turn && $0.status == "completed" }
            steps.removeAll { $0.turnID != turn && $0.status == "completed" }
        }
        return Self(checklist: steps, earlier: earlier, proposal: proposal,
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
