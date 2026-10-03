import Foundation

public enum Provider: String, CaseIterable, Sendable {
    case codex = "Codex"
    case claude = "Claude Code"
}

public struct Session: Identifiable, Hashable, Sendable {
    public let id: String
    public let provider: Provider
    public let url: URL?
    public let sessionID: String
    public let title: String
    public var titleSource: TaskTitleSource = .prompt
    public let project: String
    public let modified: Date
    public let bytes: Int
    public let archived: Bool
    public let parentID: String?
    public var classification: SessionClassification = .unknown
    public var classificationEvidence: String = "No recognized session metadata"
    public var historySource = "Local transcript"
    public var origin: SessionOrigin = .unknown
    public var desktopSessionID: String? = nil
    public var lastObservedHook: Date? = nil
    public func retainingDiscoveryMetadata(from known: Session) -> Session {
        var updated = Session(id: id, provider: provider, url: url, sessionID: sessionID,
            title: retainingTitle(from: known).title, project: project,
            modified: modified, bytes: bytes, archived: known.archived, parentID: parentID ?? known.parentID,
            classification: known.classification == .unknown ? classification : known.classification,
            classificationEvidence: known.classification == .unknown ? classificationEvidence : known.classificationEvidence)
        updated.titleSource = retainingTitle(from: known).titleSource
        updated.desktopSessionID = known.desktopSessionID
        updated.lastObservedHook = lastObservedHook ?? known.lastObservedHook
        updated.origin = known.origin
        updated.historySource = known.historySource
        return updated
    }

    public var observationOnly: Bool { origin == .claudeDesktop }
    public var sourceLabel: String { provider == .claude ? origin.label : provider.rawValue }
    public var projectName: String { project.isEmpty ? "Unknown project" : URL(fileURLWithPath: project).lastPathComponent }
}

public struct Entry: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let kind: String
    public var text: String
    public let timestamp: String?
    public var image: TranscriptImage? = nil
    public var tool: ToolResult? = nil
    public var turnID: String? = nil
    public var providerItemID: String? = nil
    public var completionMessageID: String? = nil
    public var claude: ClaudePresentation? = nil
    public var codex: CodexPresentation? = nil
    public var sourceRecords: [TranscriptSource]? = nil
}

public struct WorkingFolder: Identifiable, Sendable {
    public init(id: String, path: String?, sessions: [Session]) { self.id = id; self.path = path; self.sessions = sessions }
    public let id: String
    public let path: String?
    public let sessions: [Session]
    public var name: String {
        guard let path else { return "Unknown working folder" }
        return path == "/" ? "/" : URL(fileURLWithPath: path).lastPathComponent
    }

    public static func group(_ sessions: [Session]) -> [WorkingFolder] {
        let grouped = Dictionary(grouping: sessions) { session in
            // Do not merge unrelated folders by basename or infer a repository root.
            session.project.hasPrefix("/") ? URL(fileURLWithPath: session.project).standardizedFileURL.path : ""
        }
        return grouped.map { path, sessions in
            WorkingFolder(id: path, path: path.isEmpty ? nil : path,
                          sessions: sessions.sorted { $0.modified == $1.modified ? $0.id < $1.id : $0.modified > $1.modified })
        }.sorted {
            let left = $0.sessions.first?.modified ?? .distantPast
            let right = $1.sessions.first?.modified ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
    }
}

public struct Transcript: Equatable, Sendable {
    public var entries: [Entry] = []
    public var state = "Unknown"
    public var malformed = 0
    public var earlierContentOmitted = false
    public var error: String?
    public var source = "Local transcript"
    public var notice: String?
    public var unrecognizedTypes: [String: Int] = [:]
    public init() {}
}

public struct LibrarySnapshot: Sendable {
    public let sessions: [Session]
    public let notices: [String]
}

public struct StorageRoot: Sendable {
    public let url: URL
    public let provider: Provider
    public let archived: Bool
    public init(url: URL, provider: Provider, archived: Bool = false) {
        self.url = url; self.provider = provider; self.archived = archived
    }
    public static func defaults(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [StorageRoot] {
        let environment = ProcessInfo.processInfo.environment
        let codex = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let claude = environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        return [StorageRoot(url: codex.appendingPathComponent("sessions"), provider: .codex),
                StorageRoot(url: codex.appendingPathComponent("archived_sessions"), provider: .codex, archived: true),
                StorageRoot(url: claude.appendingPathComponent("projects"), provider: .claude)]
    }
}

// File I/O and parsing run on this serial actor, not the UI thread. Cache only metadata;
// conversation bodies are read on selection and never persisted by the app.
public actor SessionLibrary {
    private let roots: [StorageRoot]
    private struct Cached {
        let modified: Date
        let size: Int
        let session: Session?
    }
    private var cache: [URL: Cached] = [:]
    private var titleIndexes: [URL: (Date, Int, [String: SavedTaskTitle])] = [:]
    private let desktop: ClaudeDesktopHistory?
    public init(roots: [StorageRoot]? = nil, desktop: ClaudeDesktopHistory? = nil) {
        self.roots = roots ?? StorageRoot.defaults()
        self.desktop = desktop ?? (roots == nil ? ClaudeDesktopHistory() : nil)
    }

    public func scan() -> LibrarySnapshot {
        let fm = FileManager.default
        var sessions: [String: Session] = [:]
        var notices: [String] = []
        var visited: Set<URL> = []
        var unrecognized = 0
        var indexedTitles: [String: SavedTaskTitle] = [:]
        for root in roots {
            if Task.isCancelled { break }
            guard fm.fileExists(atPath: root.url.path) else {
                notices.append("Not found: \(root.url.path)")
                continue
            }
            guard fm.isReadableFile(atPath: root.url.path) else {
                notices.append("Cannot read: \(root.url.path)")
                continue
            }
            var enumerationFailed = false
            guard let files = fm.enumerator(at: root.url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in
                enumerationFailed = true
                return true
            }) else {
                notices.append("Cannot enumerate: \(root.url.path)")
                continue
            }
            for case let file as URL in files {
                if Task.isCancelled { break }
                if root.provider == .claude && file.lastPathComponent == "sessions-index.json" {
                    if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]), attrs.isSymbolicLink != true, let size = attrs.fileSize, size <= 4 * 1024 * 1024 {
                        let date = attrs.contentModificationDate ?? .distantPast
                        if titleIndexes[file]?.0 != date || titleIndexes[file]?.1 != size {
                            if let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let entries = object["entries"] as? [[String: Any]] {
                                var values: [String: SavedTaskTitle] = [:]
                                for entry in entries {
                                    guard let id = entry["sessionId"] as? String else { continue }
                                    if let title = entry["customTitle"] as? String, !title.isEmpty { values[id] = SavedTaskTitle(text: title, source: .explicit) }
                                    else if let title = entry["summary"] as? String, !title.isEmpty { values[id] = SavedTaskTitle(text: title, source: .summary) }
                                }
                                titleIndexes[file] = (date, size, values)
                            }
                        }
                        for (id, title) in titleIndexes[file]?.2 ?? [:] { indexedTitles[id] = title }
                    }
                    continue
                }
                guard file.pathExtension == "jsonl" else { continue }
                do {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    visited.insert(file)
                    let date = values.contentModificationDate ?? .distantPast
                    let size = values.fileSize ?? 0
                    let session: Session?
                    if let old = cache[file], old.modified == date, old.size == size {
                        session = old.session
                    } else {
                        let handle = try FileHandle(forReadingFrom: file)
                        defer { try? handle.close() }
                        let data = try Self.metadataWindow(handle, includeTail: root.provider == .claude)
                        session = Self.metadata(data: data, url: file, root: root, modified: date, size: size).map { fresh in
                            cache[file]?.session.map { fresh.retainingTitle(from: $0) } ?? fresh
                        }
                        cache[file] = Cached(modified: date, size: size, session: session)
                    }
                    if let session {
                        if let previous = sessions[session.id], previous.modified >= session.modified { continue }
                        sessions[session.id] = session
                    } else { unrecognized += 1 }
                } catch {
                    notices.append("Could not read \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if enumerationFailed { notices.append("Some folders could not be read under \(root.url.path)") }
        }
        cache = cache.filter { visited.contains($0.key) }
        for (id, var session) in sessions where session.provider == .claude && session.classification != .subagent {
            if let title = indexedTitles[session.sessionID], title.source.priority > session.titleSource.priority {
                session = session.updated(title: title.text); session.titleSource = title.source; sessions[id] = session
            }
        }
        if unrecognized > 0 { notices.append("\(unrecognized) files have no recognized session metadata in their first 512 KiB.") }
        if let desktop {
            let merged = desktop.merging(Array(sessions.values))
            return LibrarySnapshot(sessions: merged.sessions, notices: notices + merged.notices)
        }
        return LibrarySnapshot(sessions: sessions.values.sorted { $0.modified > $1.modified }, notices: notices)
    }

    public func transcript(for session: Session, limit: Int = 300) -> Transcript {
        guard let url = session.url else {
            var result = Transcript(); result.source = session.historySource
            result.error = session.observationOnly ? "Desktop session discovered, but its local transcript is unavailable. Resume it in Claude Desktop and refresh Diorama." : "No local transcript available"
            return result
        }
        var transcript = Self.readTranscript(url: url, provider: session.provider, limit: limit)
        if session.observationOnly { transcript.source = session.historySource }
        return transcript
    }

    public static func readTranscript(url: URL, provider: Provider, limit: Int = 300) -> Transcript {
        var result = Transcript()
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            // Bound memory. Larger histories can be opened in their source client.
            var start = size > 16 * 1024 * 1024 ? size - 16 * 1024 * 1024 : 0
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: 16 * 1024 * 1024) ?? Data()
            if start > 0, let newline = data.firstIndex(of: 10) {
                start += UInt64(newline + 1)
                data = Data(data.suffix(from: data.index(after: newline)))
            }
            return parseTranscript(data: data, provider: provider, limit: limit, start: start, scope: url.path)
        } catch { result.error = error.localizedDescription }
        return result
    }

    static func parseTranscript(data: Data, provider: Provider, limit: Int, start: UInt64 = 0, scope: String = "", sourcePath: String? = nil) -> Transcript {
        switch provider {
        case .claude: ClaudeNormalizer.parse(data, scope: scope, start: start, limit: limit, sourcePath: sourcePath)
        case .codex: CodexTranscriptNormalizer.parse(data, scope: scope, start: start, limit: limit, sourcePath: sourcePath)
        }
    }

    /// Targeted metadata inspection for file notifications, independent of a full scan.
    @concurrent public static func changedSessions(paths: [String]) async -> [Session] {
        var found: [Session] = []
        for path in paths.prefix(256) where path.hasSuffix(".jsonl") {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard let root = StorageRoot.defaults().first(where: { url.path.hasPrefix($0.url.resolvingSymlinksInPath().path + "/") }),
                  let attributes = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  attributes.isRegularFile == true,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            if let data = try? metadataWindow(handle, includeTail: root.provider == .claude),
               let session = metadata(data: data, url: url, root: root,
                  modified: attributes.contentModificationDate ?? .distantPast, size: attributes.fileSize ?? 0) {
                found.append(session)
            }
        }
        return found
    }

    // Read the head for identity and the tail for appended provider titles. Never
    // scan an unbounded transcript just to discover its name.
    static func metadataWindow(_ handle: FileHandle, includeTail: Bool = true) throws -> Data {
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: 512 * 1024) ?? Data()
        guard includeTail, size > 512 * 1024 else { return head }
        try handle.seek(toOffset: max(512 * 1024, size - min(size, 512 * 1024)))
        let tail = try handle.read(upToCount: 512 * 1024) ?? Data()
        var result = Data()
        if let last = head.lastIndex(of: 10) { result.append(head.prefix(through: last)) }
        if let first = tail.firstIndex(of: 10) { result.append(tail.suffix(from: tail.index(after: first))) }
        return result
    }

    static func metadata(data: Data, url: URL, root: StorageRoot, modified: Date, size: Int) -> Session? {
        var sid: String?
        var project = ""
        var preview = ""
        var reportedTitle: String?
        var titleSource: TaskTitleSource = .prompt
        var parent: String?
        var classification: SessionClassification = .unknown
        var evidence = "No recognized session metadata"
        for line in completeLines(data) {
            guard let record = object(line) else { continue }
            if root.provider == .codex {
                let p = record["payload"] as? [String: Any] ?? [:]
                if record["type"] as? String == "session_meta" {
                    sid = p["id"] as? String ?? p["session_id"] as? String
                    project = p["cwd"] as? String ?? ""
                    let source = p["source"] as? [String: Any]
                    let sub = source?["subagent"] as? [String: Any]
                    let spawn = sub?["thread_spawn"] as? [String: Any]
                    parent = spawn?["parent_thread_id"] as? String
                    let threadSource = p["thread_source"] as? String
                    if threadSource == "guardian_review" {
                        classification = .internalReview; evidence = "thread_source=guardian_review"
                    } else if sub != nil {
                        classification = .subagent; evidence = "source.subagent present"
                    } else if threadSource == "user" {
                        classification = .conversation; evidence = "thread_source=user"
                    }
                }
                if record["type"] as? String == "response_item", p["type"] as? String == "message", p["role"] as? String == "user", preview.isEmpty {
                    preview = titlePreview(MessageContent.split(content(p["content"]), provider: .codex).filter { !$0.context }.map(\.text).joined(separator: "\n"))
                }
            } else {
                let type = record["type"] as? String
                if type == "custom-title", let name = record["customTitle"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reportedTitle = name; titleSource = .explicit
                } else if type == "summary", titleSource != .explicit, let name = record["summary"] as? String, !name.isEmpty {
                    reportedTitle = name; titleSource = .summary
                }
                if sid == nil { sid = record["sessionId"] as? String }
                if record["isSidechain"] as? Bool == true {
                    classification = .subagent; evidence = "isSidechain=true"
                } else if classification == .unknown, record["isSidechain"] as? Bool == false {
                    classification = .conversation; evidence = "isSidechain=false"
                }
                if project.isEmpty { project = record["cwd"] as? String ?? "" }
                if record["type"] as? String == "user", record["isMeta"] as? Bool != true, preview.isEmpty, let msg = record["message"] as? [String: Any] {
                    preview = titlePreview(content(msg["content"]))
                }
            }
            if root.provider == .codex && sid != nil && !preview.isEmpty && !project.isEmpty { break }
        }
        guard let sessionID = sid else { return nil }
        var key = sessionID
        if root.provider == .claude && url.deletingLastPathComponent().lastPathComponent == "subagents" {
            classification = .subagent; evidence = "Claude session/subagents file layout"
            parent = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            key = parent! + "/" + url.deletingPathExtension().lastPathComponent
        }
        var result = Session(id: root.provider.rawValue + ":" + key, provider: root.provider, url: url, sessionID: sessionID,
                       title: classification == .internalReview ? "Internal approval review" : (reportedTitle ?? (preview.isEmpty ? "Untitled conversation · \(sessionID.prefix(8))" : preview)),
                       project: project, modified: modified, bytes: size, archived: root.archived, parentID: parent, classification: classification, classificationEvidence: evidence)
        result.titleSource = titleSource
        return result
    }

    private static func titlePreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Injected environment/instruction messages are not user-authored titles.
        return String(trimmed.replacingOccurrences(of: "\n", with: " ").prefix(100))
    }

    static func completeLines(_ data: Data) -> [Data.SubSequence] {
        guard let last = data.lastIndex(of: 10) else { return [] }
        return data.prefix(through: last).split(separator: 10, omittingEmptySubsequences: true)
    }

    private static func object(_ data: Data.SubSequence) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(data))) as? [String: Any]
    }

    private static func content(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let blocks = value as? [[String: Any]] {
            return blocks.filter { ["text", "input_text", "output_text"].contains($0["type"] as? String ?? "") }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

public extension Transcript {
    /// Merge only explicit provider identities; repeated text is legitimate conversation.
    func mergingLive(_ live: Transcript) -> Transcript {
        guard !live.entries.isEmpty else { return self }
        var result = self
        func key(_ entry: Entry) -> String? {
            guard let turn = entry.turnID, let item = entry.providerItemID else { return nil }
            return turn + ":" + item
        }
        let replacements = Dictionary(grouping: live.entries.compactMap { entry in key(entry).map { ($0, entry) } }, by: { $0.0 })
        var emitted = Set<String>()
        result.entries = entries.flatMap { entry -> [Entry] in
            guard let identity = key(entry), let matching = replacements[identity] else { return [entry] }
            guard emitted.insert(identity).inserted else { return [] }
            return matching.map { $0.1 }
        }
        for entry in live.entries {
            let additions: [Entry]
            if let identity = key(entry) {
                guard emitted.insert(identity).inserted else { continue }
                additions = replacements[identity]?.map { $0.1 } ?? [entry]
            } else {
                guard !result.entries.contains(where: { $0.id == entry.id }) else { continue }
                additions = [entry]
            }
            if let turn = entry.turnID, let last = result.entries.lastIndex(where: { $0.turnID == turn }) {
                result.entries.insert(contentsOf: additions, at: last + 1)
            } else { result.entries.append(contentsOf: additions) }
        }
        result.state = live.state
        if error != nil { result.notice = "Saved history unavailable: " + (error ?? ""); result.error = nil }
        return result
    }
}
