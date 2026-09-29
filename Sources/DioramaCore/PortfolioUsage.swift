import Foundation

public enum PortfolioUsageCoverage: String, Codable, Sendable {
    case loading, reported, partial, unavailable
}

public struct PortfolioUsageSummary: Equatable, Sendable {
    public var tokens: Int64?
    public var coverage: PortfolioUsageCoverage
    public var observedAt: Date?
    public var sources: Set<String>
    public init(tokens: Int64? = nil, coverage: PortfolioUsageCoverage = .loading, observedAt: Date? = nil, sources: Set<String> = []) {
        self.tokens = tokens; self.coverage = coverage; self.observedAt = observedAt; self.sources = sources
    }
}

/// A ledger for one native provider session. Alternative reporting scopes are never added together.
public struct PortfolioUsageLedger: Codable, Equatable, Sendable {
    public var cumulative: Int64?
    public var responses: [String: Int64] = [:]
    public var results: [String: Int64] = [:]
    public var observedAt: Date?
    public var incomplete = false
    public init() {}
    public var total: Int64? {
        if let cumulative { return cumulative }
        let responseTotal = responses.values.reduce(0, Self.add)
        let resultTotal = results.values.reduce(0, Self.add)
        if responses.isEmpty && results.isEmpty { return nil }
        // Claude SDK result aggregates can overlap saved assistant-message usage.
        // Without an explicit coverage boundary, retain the larger known lower bound.
        return max(responseTotal, resultTotal)
    }
    public var partial: Bool { incomplete || (cumulative == nil && !results.isEmpty && !responses.isEmpty) }
    private static func add(_ a: Int64, _ b: Int64) -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int64.max : value
    }
    public static func count(_ usage: WireValue, provider: Provider) -> Int64? {
        func number(_ keys: [String]) -> Int64? {
            for key in keys {
                if let n = usage[key].number, n.isFinite, n >= 0, n < Double(Int64.max) { return Int64(n) }
            }
            return nil
        }
        if let total = number(["total_tokens", "totalTokens"]) { return total }
        guard let input = number(["input_tokens", "inputTokens"]), let output = number(["output_tokens", "outputTokens"]) else { return nil }
        var total = add(input, output)
        if provider == .claude {
            // Anthropic reports these separately from input_tokens. Nested cache breakdowns are subsets.
            total = add(total, number(["cache_read_input_tokens"]) ?? 0)
            total = add(total, number(["cache_creation_input_tokens"]) ?? 0)
        }
        return total
    }
    public mutating func ingestCumulative(_ usage: WireValue, provider: Provider, at time: Date?) {
        guard let count = Self.count(usage, provider: provider) else { return }
        // Replayed or lagging saved snapshots cannot lower an already observed lifetime counter.
        cumulative = max(cumulative ?? 0, count)
        if let time { observedAt = max(observedAt ?? .distantPast, time) }
    }
    public mutating func ingestResponse(_ usage: WireValue, id: String?, provider: Provider, result: Bool = false, at time: Date?) {
        guard let count = Self.count(usage, provider: provider) else { return }
        guard let id, !id.isEmpty else { incomplete = true; return }
        if result { results[id] = max(results[id] ?? 0, count) }
        else { responses[id] = max(responses[id] ?? 0, count) }
        if let time { observedAt = max(observedAt ?? .distantPast, time) }
    }
    public mutating func ingest(_ row: WireValue, provider: Provider) {
        let time = ActivityParser.date(row["timestamp"].string)
        if provider == .codex {
            let payload = row["payload"]
            if payload["type"].string == "token_count" {
                ingestCumulative(payload["info"]["total_token_usage"], provider: provider, at: time)
            } else if row["type"].string == "token_usage_record" {
                let usage = payload["usage"] == .null ? payload["info"]["usage"] : payload["usage"]
                ingestResponse(usage, id: payload["response_id"].string ?? payload["id"].string ?? row["id"].string, provider: provider, at: time)
            }
        } else {
            let message = row["message"]
            if message["usage"] != .null {
                // Block snapshots repeat the same message; revisions replace that message's usage.
                ingestResponse(message["usage"], id: message["id"].string, provider: provider, at: time)
            }
            if row["type"].string == "result" {
                ingestResponse(row["usage"], id: row["uuid"].string ?? row["turn_id"].string, provider: provider, result: true, at: time)
            }
        }
    }
}

public struct PortfolioUsageSource: Codable, Equatable, Sendable {
    public var ledger = PortfolioUsageLedger()
    public var missing = false
    public var loading = false
    public init() {}
    public var summary: PortfolioUsageSummary {
        .init(tokens: ledger.total, coverage: loading ? .loading : ledger.total == nil ? .unavailable : missing || ledger.partial ? .partial : .reported,
              observedAt: ledger.observedAt)
    }
}

/// Incremental, full-history usage indexing. Never loads transcript UI or attaches to a provider.
/// Only usage numbers and byte cursors are persisted; source files remain authoritative.
public actor PortfolioUsageIndex {
    private struct SourceIdentity: Codable {
        var id: String
        var provider: String
        var nativeID: String
        var folder: String
        var archived: Bool
        var parentID: String?
        var child: Bool
        init(_ session: Session) {
            id = session.id; provider = session.provider.rawValue; nativeID = session.sessionID
            folder = session.project; archived = session.archived; parentID = session.parentID
            child = session.classification == .subagent
        }
    }
    private struct Cursor: Codable {
        var identity: SourceIdentity
        var skippingLongLine = false
        var path: String
        var inode: UInt64
        var modified: Date
        var offset: UInt64 = 0
        var source = PortfolioUsageSource()
    }
    private var cursors: [String: Cursor] = [:]
    private let cache: URL?
    public init(cache: URL? = nil) {
        self.cache = cache
        if let cache, let data = try? Data(contentsOf: cache), let decoded = try? JSONDecoder().decode([String: Cursor].self, from: data) { cursors = decoded }
    }
    public func cachedSessions() -> [Session] {
        cursors.values.compactMap { cursor in
            guard let provider = Provider(rawValue: cursor.identity.provider) else { return nil }
            let value = cursor.identity
            return Session(id: value.id, provider: provider, url: URL(fileURLWithPath: cursor.path), sessionID: value.nativeID,
                title: "", project: value.folder, modified: cursor.modified, bytes: Int(clamping: cursor.offset), archived: value.archived,
                parentID: value.parentID, classification: value.child ? .subagent : .conversation)
        }
    }
    public static func unavailableSession(provider: Provider, nativeID: String, project: String) -> Session {
        Session(id: provider.rawValue + ":" + nativeID, provider: provider, url: nil, sessionID: nativeID,
            title: "", project: project, modified: .distantPast, bytes: 0, archived: false, parentID: nil)
    }
    public static func identity(_ session: Session) -> String {
        // Claude children can share the parent's native session id.
        let scope = session.classification == .subagent ? session.id : session.sessionID
        return [session.provider.rawValue, scope].map { "\($0.utf8.count):\($0)" }.joined()
    }
    public func read(_ sessions: [Session]) -> [String: PortfolioUsageSource] {
        var output: [String: PortfolioUsageSource] = [:]
        var dirty = false
        var budget: UInt64 = 32 * 1024 * 1024
        for session in sessions.sorted(by: { $0.modified > $1.modified }) {
            if Task.isCancelled { break }
            let key = Self.identity(session)
            guard let url = session.url else {
                var retained = cursors[key]?.source ?? PortfolioUsageSource(); retained.missing = true
                output[key] = retained; continue
            }
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                let date = attrs[.modificationDate] as? Date ?? .distantPast
                let previous = cursors[key]
                var cursor = previous ?? Cursor(identity: SourceIdentity(session), path: url.path, inode: inode, modified: date)
                if cursor.path != url.path || cursor.inode != inode || size < cursor.offset || (size == cursor.offset && date != cursor.modified) {
                    // Keep acknowledged totals across replacement/truncation, but disclose the uncertainty.
                    cursor.offset = 0; cursor.skippingLongLine = false; cursor.source.ledger.incomplete = previous?.source.ledger.total != nil
                }
                cursor.identity = SourceIdentity(session)
                cursor.path = url.path; cursor.inode = inode
                cursor.source.missing = false
                if size != cursor.offset || date != cursor.modified || previous == nil {
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    try file.seek(toOffset: cursor.offset)
                    var pending = Data()
                    // A bounded slice per pass prevents one enormous history from starving other projects.
                    let end = min(size, cursor.offset + min(budget, 8 * 1024 * 1024))
                    var readThrough = cursor.offset
                    while readThrough < end && !Task.isCancelled {
                        let chunk = try file.read(upToCount: Int(min(256 * 1024, end - readThrough))) ?? Data()
                        if chunk.isEmpty { break }
                        readThrough += UInt64(chunk.count); budget -= UInt64(chunk.count); pending.append(chunk)
                        if cursor.skippingLongLine {
                            if let newline = pending.firstIndex(of: 10) {
                                let length = pending.distance(from: pending.startIndex, to: newline) + 1
                                cursor.offset += UInt64(length); pending.removeFirst(length); cursor.skippingLongLine = false
                            } else { cursor.offset += UInt64(pending.count); pending.removeAll(); continue }
                        }
                        while let newline = pending.firstIndex(of: 10) {
                            let line = pending.prefix(upTo: newline)
                            if !line.isEmpty {
                                if let row = try? JSONDecoder().decode(WireValue.self, from: Data(line)) { cursor.source.ledger.ingest(row, provider: session.provider) }
                                else { cursor.source.ledger.incomplete = true }
                            }
                            let length = pending.distance(from: pending.startIndex, to: newline) + 1
                            cursor.offset += UInt64(length); pending.removeFirst(length)
                        }
                        if pending.count > 1024 * 1024 {
                            cursor.source.ledger.incomplete = true; cursor.skippingLongLine = true
                            cursor.offset += UInt64(pending.count); pending.removeAll()
                        }
                    }
                    cursor.modified = date; dirty = true
                    // A trailing uncommitted JSON line is retried on the next append.
                    cursor.source.loading = cursor.offset < size && readThrough < size
                }
                cursors[key] = cursor; output[key] = cursor.source
            } catch {
                var retained = cursors[key]?.source ?? PortfolioUsageSource(); retained.missing = true
                output[key] = retained
            }
        }
        if dirty, let cache, let encoded = try? JSONEncoder().encode(cursors) {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoded.write(to: cache, options: .atomic)
        }
        return output
    }
}
