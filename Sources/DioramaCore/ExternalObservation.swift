import Foundation

/// Evidence from an external writer. Reading it never attaches to execution.
public struct ExternalObservationSnapshot: Sendable {
    public let sessionID: String
    public var transcript: Transcript
    public var activity: ActivitySummary
    public var structured: SessionActivitySnapshot
    public var sourceModifiedAt: Date?
    public var synchronizedAt: Date
    public var error: String?
    public var lastSuccessfulSynchronization: Date? = nil

    public init(sessionID: String, transcript: Transcript, activity: ActivitySummary, structured: SessionActivitySnapshot,
                sourceModifiedAt: Date?, synchronizedAt: Date, error: String?, lastSuccessfulSynchronization: Date? = nil) {
        self.sessionID = sessionID; self.transcript = transcript; self.activity = activity; self.structured = structured
        self.sourceModifiedAt = sourceModifiedAt; self.synchronizedAt = synchronizedAt; self.error = error
        self.lastSuccessfulSynchronization = lastSuccessfulSynchronization
    }

    public func agentRecord(_ child: Session, parent: Session) -> SessionActivityRecord {
        let last = activity.latestState
        return SessionActivityRecord(id: parent.id + ":observed-agent:" + child.id,
            provider: child.provider.rawValue, sessionID: parent.sessionID, turnID: last?.turnID,
            nativeID: child.provider == .claude ? child.id : child.sessionID, parentID: child.parentID,
            kind: "agent", title: child.title, status: error == nil ? activity.state.rawValue : "unknown",
            detail: activity.current ?? "", source: "External transcript",
            recordedAt: activity.events.compactMap { $0.recordedAt ?? ($0.source.hasPrefix("Hook") ? $0.observedAt : nil) }.max(),
            observedAt: synchronizedAt, data: .null)
    }

    public func isRecent(at now: Date) -> Bool {
        guard error == nil, let time = activity.events.compactMap({ $0.recordedAt ?? ($0.source.hasPrefix("Hook") ? $0.observedAt : nil) }).max(),
              now.timeIntervalSince(time) >= -2 else { return false }
        return now.timeIntervalSince(time) < 30
    }
}

/// A bounded, append-only file reader isolated from full-history discovery and App Server I/O.
public actor ExternalSessionObserver {
    private struct Cursor {
        var inode: UInt64
        var offset: UInt64
        var modified: Date
        var data: Data
        var start: UInt64
        var limit: Int
        var transcript: Transcript
        var structured: SessionActivitySnapshot
        var parsedThrough: UInt64
    }
    private var cursors: [String: Cursor] = [:]
    private var successfulReads: [String: Date] = [:]
    private let activity = ActivityLibrary()
    private let maximum = 16 * 1024 * 1024
    public init() {}

    public func readChildren(_ sessions: [Session], hookDirectory: URL?) async -> [String: ExternalObservationSnapshot] {
        var snapshots: [String: ExternalObservationSnapshot] = [:]
        let summaries = await activity.scan(Array(sessions.prefix(20)), hookDirectory: hookDirectory, retainingOtherCursors: true)
        for session in sessions.prefix(20) {
            guard !Task.isCancelled else { break }
            snapshots[session.id] = await readEvidence(session, limit: 20, hookDirectory: hookDirectory, summary: summaries[session.id])
        }
        return snapshots
    }

    public func read(_ session: Session, limit: Int = 300, now: Date = Date(), hookDirectory: URL? = HookStore.directory) async -> ExternalObservationSnapshot {
        await readEvidence(session, limit: limit, hookDirectory: hookDirectory, summary: nil)
    }

    private func readEvidence(_ session: Session, limit: Int, hookDirectory: URL?, summary suppliedSummary: ActivitySummary?) async -> ExternalObservationSnapshot {
        var transcript = cursors[session.id]?.transcript ?? Transcript()
        var modified: Date?
        var error: String?
        do {
            guard let url = session.url else { throw AppServerFailure("Local transcript unavailable") }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let date = attributes[.modificationDate] as? Date ?? .distantPast
            modified = date
            var cursor = cursors[session.id]
            if cursor?.inode != inode || size < (cursor?.offset ?? 0) ||
                (size == cursor?.offset && date != cursor?.modified) {
                cursor = nil
            }
            if cursor == nil || cursor?.offset != size || cursor?.limit != limit {
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                var start = cursor?.start ?? (size > maximum ? size - UInt64(maximum) : 0)
                var data = cursor?.data ?? Data()
                let offset = cursor?.offset ?? start
                try file.seek(toOffset: offset)
                data.append(try file.read(upToCount: maximum) ?? Data())
                let end = offset + UInt64(data.count - (cursor?.data.count ?? 0))
                if data.count > maximum {
                    let removed = data.count - maximum
                    data.removeFirst(removed); start += UInt64(removed)
                    if let newline = data.firstIndex(of: 10) {
                        let count = data.distance(from: data.startIndex, to: newline) + 1
                        data.removeFirst(count); start += UInt64(count)
                    }
                } else if cursor == nil && start > 0, let newline = data.firstIndex(of: 10) {
                    let count = data.distance(from: data.startIndex, to: newline) + 1
                    data.removeFirst(count); start += UInt64(count)
                }
                var structured = cursor?.structured ?? SessionActivitySnapshot()
                let parsedThrough = max(start, cursor?.parsedThrough ?? start)
                let unparsed = Data(data.dropFirst(Int(parsedThrough - start)))
                var parsedEnd = parsedThrough
                if let newline = unparsed.lastIndex(of: 10) {
                    let complete = Data(unparsed.prefix(through: newline))
                    SessionActivityHistory.append(complete, session: session, into: &structured)
                    parsedEnd += UInt64(complete.count)
                }
                transcript = SessionLibrary.parseTranscript(data: data, provider: session.provider, limit: limit, start: start, scope: "\(session.id):\(inode)", sourcePath: url.path)
                cursors[session.id] = Cursor(inode: inode, offset: end, modified: date, data: data, start: start, limit: limit, transcript: transcript, structured: structured, parsedThrough: parsedEnd)
                // Only selected sessions are retained. Bound memory when navigating many tasks.
                while cursors.count > 24 || cursors.values.reduce(0, { $0 + $1.data.count }) > 64 * 1024 * 1024 {
                    guard let key = cursors.keys.first(where: { $0 != session.id }) else { break }
                    cursors.removeValue(forKey: key)
                }
            }
        } catch let failure { error = failure.localizedDescription }
        let summary: ActivitySummary
        if let suppliedSummary { summary = suppliedSummary }
        else { summary = await activity.scan([session], hookDirectory: hookDirectory, retainingOtherCursors: true)[session.id] ?? ActivitySummary() }
        let structured = cursors[session.id]?.structured ?? SessionActivitySnapshot()
        let completed = Date()
        if error == nil && summary.error == nil { successfulReads[session.id] = completed }
        successfulReads = successfulReads.filter { cursors[$0.key] != nil }
        return ExternalObservationSnapshot(sessionID: session.id, transcript: transcript, activity: summary,
            structured: structured, sourceModifiedAt: modified, synchronizedAt: completed, error: error ?? summary.error,
            lastSuccessfulSynchronization: successfulReads[session.id])
    }
}
