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
    public let project: String
    public let modified: Date
    public let bytes: Int
    public let archived: Bool
    public let parentID: String?
    public var classification: SessionClassification = .unknown
    public var classificationEvidence: String = "No recognized session metadata"
    public var historySource = "Local transcript"
    public var projectName: String { project.isEmpty ? "Unknown project" : URL(fileURLWithPath: project).lastPathComponent }
}

public struct Entry: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let kind: String
    public let text: String
    public let timestamp: String?
    public var image: TranscriptImage? = nil
    public var tool: ToolResult? = nil
    public var turnID: String? = nil
    public var providerItemID: String? = nil
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
    public init(roots: [StorageRoot] = StorageRoot.defaults()) { self.roots = roots }

    public func scan() -> LibrarySnapshot {
        let fm = FileManager.default
        var sessions: [String: Session] = [:]
        var notices: [String] = []
        var visited: Set<URL> = []
        var unrecognized = 0
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
                        let data = try handle.read(upToCount: 512 * 1024) ?? Data()
                        session = Self.metadata(data: data, url: file, root: root, modified: date, size: size)
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
        if unrecognized > 0 { notices.append("\(unrecognized) files have no recognized session metadata in their first 512 KiB.") }
        return LibrarySnapshot(sessions: sessions.values.sorted { $0.modified > $1.modified }, notices: notices)
    }

    public func transcript(for session: Session, limit: Int = 300) -> Transcript {
        guard let url = session.url else { var result = Transcript(); result.error = "No local transcript available"; return result }
        return Self.readTranscript(url: url, provider: session.provider, limit: limit)
    }

    public static func readTranscript(url: URL, provider: Provider, limit: Int = 300) -> Transcript {
        var result = Transcript()
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            // Bound memory. Larger histories can be opened in their source client.
            let start = size > 16 * 1024 * 1024 ? size - 16 * 1024 * 1024 : 0
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: 16 * 1024 * 1024) ?? Data()
            if start > 0, let newline = data.firstIndex(of: 10) { data = Data(data.suffix(from: data.index(after: newline))) }
            result.earlierContentOmitted = start > 0
            var entries: [Entry] = []
            var uuids: Set<String> = []
            for (index, line) in completeLines(data).enumerated() {
                if Task.isCancelled { break }
                guard let record = object(line) else { result.malformed += 1; continue }
                if provider == .claude, let uuid = record["uuid"] as? String {
                    if !uuids.insert(uuid).inserted { continue }
                }
                let timestamp = record["timestamp"] as? String
                func append(_ kind: String, _ body: String) {
                    guard !body.isEmpty else { return }
                    entries.append(Entry(id: "\(start)-\(index)-\(entries.count)", kind: kind, text: body, timestamp: timestamp))
                }
                if provider == .codex {
                    guard let payload = record["payload"] as? [String: Any] else { continue }
                    let type = payload["type"] as? String ?? ""
                    if record["type"] as? String == "event_msg" {
                        let states = ["task_started": "Working", "task_complete": "Last turn finished", "turn_aborted": "Interrupted"]
                        if let state = states[type] { result.state = state; append("Event", state) }
                    } else if record["type"] as? String == "response_item" {
                        switch type {
                        case "message":
                            let role = payload["role"] as? String ?? ""
                            if role == "user" {
                                for part in MessageContent.split(content(payload["content"]), provider: .codex) { append(part.context ? "System context" : "You", part.text) }
                            } else if role == "assistant" { append("Assistant", content(payload["content"])) }
                            else if role == "system" || role == "developer" { append("System context", content(payload["content"])) }
                        case "function_call", "custom_tool_call":
                            append("Tool call", (payload["name"] as? String ?? "Tool") + "\n" + content(payload["arguments"] ?? payload["input"]))
                        case "function_call_output", "custom_tool_call_output": append("Tool result", content(payload["output"]))
                        default: break // Do not surface reasoning/encrypted records.
                        }
                    }
                } else {
                    guard let role = record["type"] as? String, ["user", "assistant"].contains(role), let message = record["message"] as? [String: Any] else { continue }
                    let kind = record["isMeta"] as? Bool == true ? "System context" : (role == "user" ? "You" : "Assistant")
                    if let text = message["content"] as? String {
                        for part in MessageContent.split(kind == "Assistant" ? text.replacingOccurrences(of: #"(?m)^DIORAMA_GOAL_[A-Fa-f0-9-]{36}:(?:COMPLETE|CONTINUE|BLOCKED)[ \t]*$"#, with: "", options: .regularExpression) : text, provider: .claude) { append(part.context ? "System context" : kind, part.text) }
                    }
                    for block in message["content"] as? [[String: Any]] ?? [] {
                        switch block["type"] as? String {
                        case "text":
                            let text = block["text"] as? String ?? ""
                            for part in MessageContent.split(kind == "Assistant" ? text.replacingOccurrences(of: #"(?m)^DIORAMA_GOAL_[A-Fa-f0-9-]{36}:(?:COMPLETE|CONTINUE|BLOCKED)[ \t]*$"#, with: "", options: .regularExpression) : text, provider: .claude) { append(part.context ? "System context" : kind, part.text) }
                        case "tool_use": append("Tool call", (block["name"] as? String ?? "Tool") + "\n" + content(block["input"]))
                        case "tool_result": append("Tool result", content(block["content"]))
                        default: break
                        }
                    }
                }
            }
            if entries.count > limit { result.earlierContentOmitted = true }
            result.entries = Array(entries.suffix(max(1, limit)))
        } catch { result.error = error.localizedDescription }
        return result
    }

    private static func metadata(data: Data, url: URL, root: StorageRoot, modified: Date, size: Int) -> Session? {
        var sid: String?
        var project = ""
        var preview = ""
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
            if sid != nil && !preview.isEmpty && !project.isEmpty { break }
        }
        guard let sessionID = sid else { return nil }
        var key = sessionID
        if root.provider == .claude && url.deletingLastPathComponent().lastPathComponent == "subagents" {
            classification = .subagent; evidence = "Claude session/subagents file layout"
            parent = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            key = parent! + "/" + url.deletingPathExtension().lastPathComponent
        }
        return Session(id: root.provider.rawValue + ":" + key, provider: root.provider, url: url, sessionID: sessionID,
                       title: classification == .internalReview ? "Internal approval review" : (preview.isEmpty ? "Untitled conversation · \(sessionID.prefix(8))" : preview),
                       project: project, modified: modified, bytes: size, archived: root.archived, parentID: parent, classification: classification, classificationEvidence: evidence)
    }

    private static func titlePreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Injected environment/instruction messages are not user-authored titles.
        return String(trimmed.replacingOccurrences(of: "\n", with: " ").prefix(100))
    }

    private static func completeLines(_ data: Data) -> [Data.SubSequence] {
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
