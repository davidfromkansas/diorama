import Foundation
import Darwin

/// Only discovery/history requests are available through this stage's transport.
public protocol AppServerReading: Sendable {
    func request(_ method: String, parameters: Data) async throws -> Data
}

public struct AppServerFailure: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

/// Serial, bounded pipe I/O is isolated from the UI actor. No sessions are loaded or resumed.
public actor AppServerConnection: AppServerReading {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var retryAfter = Date.distantPast
    private let executable: URL?
    private let timeout: TimeInterval
    public init(executable: URL? = nil, timeout: TimeInterval = 12) {
        self.executable = executable; self.timeout = timeout
    }
    deinit {
        try? input?.close(); try? output?.close()
        if let process, process.isRunning { process.terminate() }
    }
    public func request(_ method: String, parameters: Data) throws -> Data {
        guard ["thread/list", "thread/read", "thread/items/list"].contains(method) else { throw AppServerFailure("Unsupported read-only method: \(method)") }
        guard Date() >= retryAfter else { throw AppServerFailure("App Server reconnect pending; local fallback active") }
        do {
            if process?.isRunning != true { try connect() }
            let params = try JSONSerialization.jsonObject(with: parameters)
            return try exchange(method, params: params)
        } catch let error as ExecutionRPCRejection { throw error
        } catch {
            close(); retryAfter = Date().addingTimeInterval(15)
            throw error
        }
    }
    private func close() {
        try? input?.close(); try? output?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil; buffer.removeAll()
    }
    private func connect() throws {
        close()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent(".local/bin/codex"), URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex")]
        guard let binary = executable ?? candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw AppServerFailure("Codex CLI not found; local fallback active")
        }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = binary; child.arguments = ["app-server", "--stdio"]
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        child.currentDirectoryURL = home
        try child.run()
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        // Reading only after poll keeps initialization, EOF and hung servers bounded.
        let flags = fcntl(stdout.fileHandleForReading.fileDescriptor, F_GETFL)
        _ = fcntl(stdout.fileHandleForReading.fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        _ = try exchange("initialize", params: ["clientInfo": ["name": "diorama_history", "version": "0.2.0"], "capabilities": ["experimentalApi": true]])
        try send(["method": "initialized", "params": [:]])
    }
    private func send(_ value: [String: Any]) throws {
        guard let input else { throw AppServerFailure("App Server disconnected") }
        var data = try JSONSerialization.data(withJSONObject: value); data.append(10)
        try input.write(contentsOf: data)
    }
    private func exchange(_ method: String, params: Any) throws -> Data {
        nextID += 1; let id = nextID
        try send(["id": id, "method": method, "params": params])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer.prefix(upTo: end)); buffer.removeSubrange(...end)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if object["method"] != nil {
                    // A history-only client never executes a tool or grants an approval.
                    if let requestID = object["id"] {
                        try send(["id": requestID, "error": ["code": -32601, "message": "Diorama history connection cannot handle execution requests"]])
                    }
                    continue
                }
                guard (object["id"] as? Int) == id else { continue }
                if let error = object["error"] as? [String: Any] { throw ExecutionRPCRejection(error["message"] as? String ?? "App Server request failed") }
                guard let result = object["result"] else { throw AppServerFailure("Missing App Server result") }
                return try JSONSerialization.data(withJSONObject: result)
            }
            guard let output else { throw AppServerFailure("App Server disconnected") }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 && errno != EINTR { throw AppServerFailure("App Server pipe error") }
            if ready > 0 {
                var bytes = [UInt8](repeating: 0, count: 65536)
                let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
                if count == 0 { throw AppServerFailure("App Server exited") }
                if count > 0 { buffer.append(contentsOf: bytes.prefix(count)) }
                else if errno != EAGAIN && errno != EINTR { throw AppServerFailure("Cannot read App Server output") }
                guard buffer.count <= 64 * 1024 * 1024 else { throw AppServerFailure("App Server response exceeds 64 MiB; local fallback active") }
            }
        }
        throw AppServerFailure("App Server \(method) timed out; local fallback active")
    }
}

public enum AppServerHistory {
    public static let sourceKinds = ["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"]

    public static func session(_ thread: [String: Any], archived: Bool, fallback: Session? = nil) -> Session? {
        guard let id = thread["id"] as? String, !id.isEmpty else { return nil }
        let source = thread["source"] as? [String: Any]
        let sub = source?["subAgent"] ?? source?["subagent"]
        let spawn = (sub as? [String: Any])?["thread_spawn"] as? [String: Any]
        let parent = thread["parentThreadId"] as? String ?? spawn?["parent_thread_id"] as? String ?? fallback?.parentID
        let classification: SessionClassification
        let evidence: String
        if thread["threadSource"] as? String == "guardian_review" {
            classification = .internalReview; evidence = "App Server threadSource=guardian_review"
        } else if thread["threadSource"] as? String == nil, fallback?.classification == .internalReview {
            classification = .internalReview; evidence = "Local metadata supplement: " + (fallback?.classificationEvidence ?? "guardian_review")
        } else if sub != nil || parent != nil {
            classification = .subagent; evidence = "App Server explicit subagent/parent metadata"
        } else if thread["threadSource"] as? String == "user" {
            classification = .conversation; evidence = "App Server threadSource=user"
        } else {
            classification = fallback?.classification ?? .unknown
            evidence = fallback?.classificationEvidence ?? "App Server returned no recognized classification; kept visible"
        }
        let name = (thread["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = MessageContent.split(thread["preview"] as? String ?? "", provider: .codex).filter { !$0.context }.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = classification == .internalReview ? "Internal approval review" : !name.isEmpty ? name : !preview.isEmpty ? String(preview.prefix(100)) : fallback?.title ?? "Untitled conversation · \(id.prefix(8))"
        let path = thread["path"] as? String
        let url = fallback?.url ?? path.flatMap { path -> URL? in
            guard path.hasPrefix("/"), path.hasSuffix(".jsonl") else { return nil }
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let allowed = StorageRoot.defaults().filter { $0.provider == .codex }.contains {
                url.path.hasPrefix($0.url.resolvingSymlinksInPath().path + "/")
            }
            return allowed ? url : nil
        }
        return Session(id: Provider.codex.rawValue + ":" + id, provider: .codex, url: url, sessionID: id, title: title,
                       project: thread["cwd"] as? String ?? fallback?.project ?? "",
                       modified: (thread["updatedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? fallback?.modified ?? .distantPast,
                       bytes: fallback?.bytes ?? 0, archived: archived, parentID: parent,
                       classification: classification, classificationEvidence: evidence, historySource: "Codex App Server")
    }

    public static func transcript(_ thread: [String: Any], limit: Int) throws -> Transcript {
        guard let turns = thread["turns"] as? [[String: Any]] else { throw AppServerFailure("App Server omitted turns") }
        var result = Transcript(); result.source = "Codex App Server"
        for turn in turns {
            guard let items = turn["items"] as? [[String: Any]], !items.isEmpty else {
                throw AppServerFailure("App Server returned a turn without readable items")
            }
            let turnID = turn["id"] as? String ?? "turn"
            let timestamp = (turn["startedAt"] as? Double).map { "Turn started " + ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) }
            for (index, item) in items.enumerated() {
                let key = turnID + ":" + (item["id"] as? String ?? String(index))
                func append(_ kind: String, _ text: String, image: TranscriptImage? = nil) {
                    if !text.isEmpty { result.entries.append(Entry(id: key + ":\(result.entries.count)", kind: kind, text: text, timestamp: timestamp, image: image, tool: (try? JSONDecoder().decode(WireValue.self, from: JSONSerialization.data(withJSONObject: item))).flatMap(ToolResult.init), turnID: turnID, providerItemID: item["id"] as? String)) }
                }
                switch item["type"] as? String {
                case "userMessage":
                    let content = (item["content"] as? [[String: Any]] ?? []).compactMap { block -> String? in
                        if block["type"] as? String == "text" { return block["text"] as? String }
                        return "[\(block["type"] as? String ?? "attachment") attachment]"
                    }.joined(separator: "\n")
                    for part in MessageContent.split(content, provider: .codex) { append(part.context ? "System context" : "You", part.text) }
                case "agentMessage", "plan": append("Assistant", item["text"] as? String ?? "")
                case "hookPrompt": append("System context", formatted(item))
                case "imageView":
                    append("Tool activity", formatted(item), image: TranscriptImage(itemType: "imageView", path: item["path"] as? String))
                case "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "collabToolCall", "collabAgentToolCall", "subAgentActivity", "webSearch", "functionCallOutput", "sleep", "imageGeneration":
                    append("Tool activity", formatted(item))
                case "contextCompaction": append("Event", "Conversation compacted")
                case "enteredReviewMode", "exitedReviewMode": append("Event", item["type"] as? String ?? "Review")
                case "reasoning": break // Preserve the existing boundary: no reasoning records.
                default: throw AppServerFailure("App Server returned an unsupported history item")
                }
            }
            // Status here describes a persisted turn, never the independent server's runtime status.
            switch turn["status"] as? String {
            case "completed": result.state = "Last turn finished"
            case "interrupted": result.state = "Interrupted"
            case "inProgress": result.state = "Working"
            default: result.state = "Unknown"
            }
        }
        result.earlierContentOmitted = result.entries.count > limit
        result.entries = Array(result.entries.suffix(max(1, limit)))
        return result
    }
    private static func formatted(_ item: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: item, options: [.prettyPrinted, .sortedKeys]) else { return "Unavailable tool details" }
        let label = item["command"] as? String ?? item["tool"] as? String ?? item["type"] as? String ?? "Tool activity"
        return label + "\n\n```json\n" + String(decoding: data, as: UTF8.self) + "\n```"
    }
}

/// Combines provider history with the existing file adapter. Files remain the activity source.
public actor ImportedSessionLibrary {
    private let files: SessionLibrary
    private let server: any AppServerReading
    private var previousCodex: [String: Session] = [:]
    private var lastTranscript: (id: String, value: Transcript)?
    public init(files: SessionLibrary = SessionLibrary(), server: any AppServerReading = AppServerConnection()) {
        self.files = files; self.server = server
    }
    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: params)
        let reply = try await server.request(method, parameters: data)
        guard let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any] else { throw AppServerFailure("Invalid App Server response") }
        return object
    }
    public func scan() async -> LibrarySnapshot {
        let local = await files.scan()
        let lookup = Dictionary(uniqueKeysWithValues: local.sessions.map { ($0.id, $0) })
        var imported: [String: Session] = [:]
        var notices = local.notices
        do {
            for archived in [false, true] {
                var cursor: String?; var seen = Set<String>(); var pages = 0
                repeat {
                    try Task.checkCancellation()
                    var params: [String: Any] = ["limit": 100, "archived": archived, "sourceKinds": AppServerHistory.sourceKinds, "sortKey": "created_at", "useStateDbOnly": true]
                    if let cursor { params["cursor"] = cursor }
                    let page = try await request("thread/list", params)
                    guard let threads = page["data"] as? [[String: Any]] else { throw AppServerFailure("App Server omitted session list") }
                    for thread in threads {
                        let key = Provider.codex.rawValue + ":" + (thread["id"] as? String ?? "")
                        if let session = AppServerHistory.session(thread, archived: archived, fallback: lookup[key]) { imported[session.id] = session }
                    }
                    cursor = page["nextCursor"] as? String; pages += 1
                    if let cursor, !seen.insert(cursor).inserted { throw AppServerFailure("App Server repeated pagination cursor") }
                    if pages >= 1000, cursor != nil { throw AppServerFailure("App Server discovery limit reached") }
                } while cursor != nil
            }
            previousCodex = imported
            notices.insert("Codex history: App Server connected · read-only · activity from hooks/local records", at: 0)
        } catch {
            imported = previousCodex.filter { lookup[$0.key] == nil }.mapValues { session in
                var cached = session; cached.historySource = "Cached App Server metadata"; return cached
            }
            notices.insert("Codex history: local fallback · \(error.localizedDescription)", at: 0)
        }
        // DB-only discovery intentionally does not repair provider metadata. Keep file-only records visible.
        let missing = local.sessions.filter { $0.provider == .codex && imported[$0.id] == nil }.count
        if missing > 0 { notices.append("\(missing) Codex records discovered through local-file fallback") }
        var combined = lookup
        for (id, session) in imported { combined[id] = session }
        return LibrarySnapshot(sessions: combined.values.sorted { $0.modified > $1.modified }, notices: notices)
    }
    private func paginatedTranscript(_ session: Session, limit: Int) async throws -> Transcript {
        var rows: [[String: Any]] = []; var cursor: String?; var seen = Set<String>()
        repeat {
            var params: [String: Any] = ["threadId": session.sessionID, "limit": min(100, max(1, limit - rows.count)), "sortDirection": "desc"]
            if let cursor { params["cursor"] = cursor }
            let response = try await request("thread/items/list", params)
            guard let data = response["data"] as? [[String: Any]] else { throw AppServerFailure("Paginated items unavailable") }
            rows += data; cursor = response["nextCursor"] as? String
            if let cursor, !seen.insert(cursor).inserted { throw AppServerFailure("History cursor repeated") }
        } while cursor != nil && rows.count < limit
        var turns: [[String: Any]] = []
        for row in rows.reversed() {
            guard let turnID = row["turnId"] as? String, let item = row["item"] as? [String: Any] else { throw AppServerFailure("Invalid paginated history item") }
            if turns.last?["id"] as? String == turnID {
                var items = turns[turns.count - 1]["items"] as? [[String: Any]] ?? []; items.append(item); turns[turns.count - 1]["items"] = items
            } else { turns.append(["id": turnID, "items": [item]]) }
        }
        var result = try AppServerHistory.transcript(["turns": turns], limit: limit)
        result.earlierContentOmitted = result.earlierContentOmitted || cursor != nil
        result.source = "Codex App Server · paginated history"
        return result
    }
    public func transcript(for session: Session, limit: Int = 300) async -> Transcript {
        guard session.provider == .codex else { return await files.transcript(for: session, limit: limit) }
        let local = await files.transcript(for: session, limit: limit)
        var result: Transcript
        do {
            do {
                result = try await paginatedTranscript(session, limit: limit)
            } catch {
                let response = try await request("thread/read", ["threadId": session.sessionID, "includeTurns": true])
                guard let thread = response["thread"] as? [String: Any], thread["id"] as? String == session.sessionID else { throw AppServerFailure("App Server returned a different conversation") }
                result = try AppServerHistory.transcript(thread, limit: limit)
                result.notice = "Paginated history unavailable; using legacy history: " + error.localizedDescription
            }
            if result.entries.isEmpty && !local.entries.isEmpty { throw AppServerFailure("App Server returned empty history; local records exist") }
            if let latest = local.entries.last(where: { $0.kind == "Assistant" }),
               !result.entries.contains(where: { $0.kind == "Assistant" && $0.text.contains(latest.text) }) {
                throw AppServerFailure("Latest recorded assistant reply is missing from App Server history")
            }
        } catch {
            result = local
            result.source = "Local transcript fallback"
            result.notice = error.localizedDescription
            if (result.error != nil || result.entries.isEmpty), let previous = lastTranscript, previous.id == session.id, !previous.value.entries.isEmpty {
                result = previous.value
                result.notice = "Showing last successfully read history · \(error.localizedDescription)"
            }
        }
        if result.error == nil { lastTranscript = (session.id, result) }
        return result
    }
}
