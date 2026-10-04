import Foundation
import CryptoKit

public struct InboxUpdate: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var outputs: [ClaudeOutput]
    public var date: Date
    public var received: Bool
    public var outcome: String
    public var runtimeOutcome: Bool? = nil
    public init(id: String, text: String, outputs: [ClaudeOutput] = [], date: Date, received: Bool = false, outcome: String = "completed") {
        self.id = id; self.text = text; self.outputs = outputs; self.date = date; self.received = received; self.outcome = outcome
    }
    public static func make(session: Session, turn: String, entries: [Entry], outcome: String, date: Date?) -> Self? {
        let relevant = entries.filter { $0.claude?.agentID == nil && ($0.turnID == nil || $0.turnID == turn) }
        // The handoff is the latest assistant response, not the progress commentary
        // leading up to it. All reported outputs from this turn remain attached.
        let text = relevant.last(where: { $0.kind == "Assistant" && !$0.text.isEmpty })?.text
            ?? relevant.last(where: { $0.kind == "Proposed plan" && !$0.text.isEmpty })?.text ?? ""
        var outputKeys = Set<String>()
        let outputs = relevant.flatMap { entry -> [ClaudeOutput] in
            guard entry.kind != "You", entry.claude?.status != "Failed", entry.claude?.status != "Running" else { return [] }
            return (entry.claude?.outputs ?? []) + (entry.tool?.outputs ?? [])
        }.filter { outputKeys.insert($0.location ?? $0.id).inserted }
        guard !text.isEmpty || !outputs.isEmpty else { return nil }
        return .init(id: session.provider.rawValue + ":" + session.sessionID + ":" + turn,
                     text: text, outputs: outputs, date: date ?? Date(), received: date == nil, outcome: outcome)
    }
}

public struct InboxThread: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var project: String
    public var conversation: String
    public var title: String
    public var agent = "Main agent"
    public var excerpt: String
    public var date: Date
    public var received: Bool
    public var outcome: String
    public var attachments: Int
    public var unread: Bool
    public var archived = false
    public var rejected = false
    public var updates: [Reference]
    public struct Reference: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var date: Date
        public var read: Bool
        var digest: String
    }
}

public enum InboxFilter: String, CaseIterable, Sendable { case inbox = "Inbox", archived = "Archived", rejected = "Not a delivery" }
public enum InboxAction: Sendable { case read, unread, archive, reject, restore }
public struct InboxPage: Sendable {
    public var rows: [InboxThread]
    public var next: String?
    public var unread: Int
}

/// Bodies live in separate files; list queries never decode message bodies or images.
/// All disk access and ordering run on this actor, not the UI executor.
public actor ProjectInboxStore {
    public static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diorama/ProjectInbox", isDirectory: true)
    private let directory: URL
    private var threads: [String: InboxThread] = [:]
    private var loaded = false
    private var seeds: [String: Date] = [:]
    private var dirty = Set<String>()
    private let encoder: JSONEncoder = { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value }()
    public init(directory: URL = defaultDirectory) { self.directory = directory }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func file(_ id: String) -> URL { directory.appendingPathComponent(Self.digest(Data(id.utf8)) + ".json") }
    private func load() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let seedFile = directory.appendingPathComponent("seeds.json")
        if FileManager.default.fileExists(atPath: seedFile.path) { seeds = try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: seedFile)) }
        var restored: [String: InboxThread] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.lastPathComponent.hasSuffix(".thread.json") {
            let thread = try JSONDecoder().decode(InboxThread.self, from: Data(contentsOf: url)); restored[thread.id] = thread
        }
        threads = restored; loaded = true
    }
    private func save() throws {
        for id in dirty {
            if let thread = threads[id] { try encoder.encode(thread).write(to: file(id).deletingPathExtension().appendingPathExtension("thread.json"), options: .atomic) }
        }
        dirty.removeAll()
    }
    @discardableResult public func ingest(project: String, conversation: String, title: String, updates: [InboxUpdate], agentName: String? = nil, historicalBefore: Date, sourceModified: Date? = nil) throws -> Bool {
        try load()
        if seeds[project] == nil {
            seeds[project] = historicalBefore
            do { try encoder.encode(seeds).write(to: directory.appendingPathComponent("seeds.json"), options: .atomic) }
            catch { seeds.removeValue(forKey: project); throw error }
        }
        let baseline = seeds[project] ?? historicalBefore
        let id = project + ":" + conversation
        var changed = false
        let original = threads[id]
        if threads[id] != nil && threads[id]?.title != title { threads[id]?.title = title; changed = true }
        if let agentName, threads[id] != nil, threads[id]?.agent != agentName { threads[id]?.agent = agentName; changed = true }
        for var update in updates {
            let existing = threads[id]?.updates.first { $0.id == update.id }
            // Missing provider timestamps must not reorder a replay on every observation.
            if update.received, let existing { update.date = existing.date }
            var data = try encoder.encode(update), digest = Self.digest(data)
            guard existing?.digest != digest else { continue }
            if existing != nil, update.runtimeOutcome != true,
               let known = try? JSONDecoder().decode(InboxUpdate.self, from: Data(contentsOf: file(update.id))), known.runtimeOutcome == true {
                update.outcome = known.outcome; update.runtimeOutcome = true
                data = try encoder.encode(update); digest = Self.digest(data)
                guard existing?.digest != digest else { continue }
            }
            try data.write(to: file(update.id), options: .atomic)
            let reference = InboxThread.Reference(id: update.id, date: update.date, read: existing?.read ?? ((update.received ? sourceModified ?? update.date : update.date) <= baseline), digest: digest)
            var thread = threads[id] ?? InboxThread(id: id, project: project, conversation: conversation, title: title,
                excerpt: "", date: update.date, received: update.received, outcome: update.outcome, attachments: 0, unread: false, updates: [])
            thread.title = title
            if let agentName { thread.agent = agentName }
            thread.updates.removeAll { $0.id == update.id }; thread.updates.append(reference)
            thread.updates.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            if thread.updates.last?.id == update.id {
                thread.date = update.date; thread.received = update.received; thread.outcome = update.outcome
                let preview = String(update.text.prefix(1024)).replacingOccurrences(of: "\n", with: " ")
                let plain = (try? AttributedString(markdown: preview, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))).map { String($0.characters) } ?? preview
                thread.excerpt = String(plain.prefix(180))
                if thread.excerpt.isEmpty { thread.excerpt = "Reported outputs" }
                thread.attachments = update.outputs.count
            }
            if existing == nil, !reference.read { thread.archived = false }
            thread.unread = thread.updates.contains { !$0.read }
            threads[id] = thread; changed = true
        }
        if changed {
            dirty.insert(id)
            do { try save() } catch { threads[id] = original; throw error }
        }
        return changed
    }
    @discardableResult public func merge(project: String, conversation: String, previous: [String]) throws -> Bool {
        try load()
        let targetID = project + ":" + conversation
        let oldIDs = previous.map { project + ":" + $0 }.filter { $0 != targetID && threads[$0] != nil }
        guard !oldIDs.isEmpty else { return false }
        let sources = ([threads[targetID]].compactMap { $0 } + oldIDs.compactMap { threads[$0] })
        guard var combined = sources.max(by: { $0.date < $1.date }) else { return false }
        combined.id = targetID; combined.conversation = conversation
        var references: [String: InboxThread.Reference] = [:]
        for source in sources {
            for var reference in source.updates {
                if let known = references[reference.id] { reference.read = reference.read && known.read }
                references[reference.id] = reference
            }
        }
        combined.updates = references.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        combined.unread = combined.updates.contains { !$0.read }
        combined.rejected = sources.contains { $0.rejected }
        combined.archived = sources.allSatisfy { $0.archived }
        threads[targetID] = combined; dirty.insert(targetID)
        try save()
        for id in oldIDs {
            try FileManager.default.removeItem(at: file(id).deletingPathExtension().appendingPathExtension("thread.json"))
            threads.removeValue(forKey: id)
        }
        return true
    }
    public func page(project: String, filter: InboxFilter = .inbox, after: String? = nil, limit: Int = 50, around: String? = nil) throws -> InboxPage {
        try load()
        let all = threads.values.filter { $0.project == project }
        let sorted = all.filter {
            switch filter { case .inbox: !$0.archived && !$0.rejected; case .archived: $0.archived && !$0.rejected; case .rejected: $0.rejected }
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        // Cursor carries the ordering key, not an offset that shifts on arrival.
        let cursor = after.flatMap { Data(base64Encoded: $0) }.flatMap { try? JSONDecoder().decode(Cursor.self, from: $0) }
        let eligible: [InboxThread]
        if cursor == nil, let around, let index = sorted.firstIndex(where: { $0.id == around }) {
            eligible = Array(sorted.dropFirst(max(0, index - 10)))
        } else { eligible = sorted.filter { row in cursor.map { row.date < $0.date || (row.date == $0.date && row.id > $0.id) } ?? true } }
        let page = eligible.prefix(max(1, min(limit, 50))).map { row in
            var summary = row
            // Only the newest identity is needed as the opening read watermark.
            summary.updates = Array(row.updates.suffix(1))
            return summary
        }
        let next = eligible.count > page.count ? page.last.flatMap { try? JSONEncoder().encode(Cursor(id: $0.id, date: $0.date)).base64EncodedString() } : nil
        return InboxPage(rows: page, next: next, unread: all.filter { $0.unread && !$0.archived && !$0.rejected }.count)
    }
    private struct Cursor: Codable { var id: String; var date: Date }
    public func summaries(_ ids: [String]) throws -> [String: InboxThread] {
        try load()
        return Dictionary(uniqueKeysWithValues: Set(ids.prefix(251)).compactMap { id in threads[id].map { (id, $0) } })
    }
    public func detail(_ id: String, before: String? = nil, limit: Int = 20, around: String? = nil) throws -> [InboxUpdate] {
        try load(); guard let thread = threads[id] else { return [] }
        let end = before.flatMap { key in thread.updates.firstIndex { $0.id == key } } ?? around.flatMap { key in thread.updates.firstIndex { $0.id == key }.map { min(thread.updates.count, $0 + 10) } } ?? thread.updates.count
        return try thread.updates[max(0, end - min(limit, 20))..<end].map { try JSONDecoder().decode(InboxUpdate.self, from: Data(contentsOf: file($0.id))) }
    }
    @discardableResult public func act(_ id: String, _ action: InboxAction, viewed: Set<String>? = nil, through: String? = nil) throws -> Bool {
        try load(); guard var thread = threads[id] else { return false }
        let previous = thread
        let boundary = through.flatMap { key in thread.updates.firstIndex { $0.id == key } } ?? (through == nil ? thread.updates.count : -1)
        switch action {
        case .read, .unread:
            for i in thread.updates.indices where (viewed == nil || viewed!.contains(thread.updates[i].id)) && i <= boundary { thread.updates[i].read = action == .read }
            thread.unread = thread.updates.contains { !$0.read }
        case .archive: thread.archived = true
        case .reject: thread.rejected = true
        case .restore: thread.rejected = false; thread.archived = false
        }
        guard thread != previous else { return false }
        threads[id] = thread; dirty.insert(id)
        do { try save() } catch { threads[id] = previous; throw error }
        return true
    }
}
