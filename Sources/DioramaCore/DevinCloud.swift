import Foundation
import Security

/// The Devin API key and organization, kept in the login Keychain. Diorama sends them only to
/// `api.devin.ai`. API use is billed to that organization, separately from a Devin CLI sign-in.
public struct DevinCloudCredentials: Codable, Sendable, Equatable {
    public var apiKey: String
    public var organization: String
    public init(apiKey: String, organization: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.organization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static let service = "local.diorama.devin.api"
    private static let account = "api.devin.ai"

    /// Never shows a Keychain prompt: a key Diorama can't read reads as not set up.
    public static func load() -> DevinCloudCredentials? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                                          kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    public func save() throws {
        let data = try JSONEncoder().encode(self)
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account] as CFDictionary
        let update = SecItemUpdate(query, [kSecValueData: data] as CFDictionary)
        if update == errSecItemNotFound {
            let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account,
                                     kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppServerFailure("Could not save the Devin API key in Keychain.") }
        } else if update != errSecSuccess { throw AppServerFailure("Could not update the Devin API key in Keychain.") }
    }
    public static func remove() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppServerFailure("Could not remove the Devin API key from Keychain.") }
    }
}

/// Devin's REST API (v3): sessions run on Devin's own cloud machine, not in a folder on this Mac.
public struct DevinCloudAPI: Sendable {
    public static let base = URL(string: "https://api.devin.ai/v3/")!
    /// The one catalog row for cloud sessions: picking it starts a session through the API.
    public static let modelID = "devin/@api"
    public static let threadPrefix = "devin-cloud:"
    public static var catalogRow: WireValue {
        .object(["model": .string(modelID), "displayName": .string("Devin · Cloud (API)"), "isDefault": .bool(false), "supportedReasoningEfforts": .array([])])
    }
    public let credentials: DevinCloudCredentials
    let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public init(credentials: DevinCloudCredentials, send: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil) {
        self.credentials = credentials
        self.send = send ?? { try await URLSession.shared.data(for: $0) }
    }
    private var organizationPath: String {
        "organizations/" + (credentials.organization.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.organization)
    }
    func call(_ path: String, method: String = "GET", body: WireValue? = nil, query: [URLQueryItem] = []) async throws -> WireValue {
        var components = URLComponents(url: Self.base.appendingPathComponent(organizationPath + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer " + credentials.apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let value = (try? JSONDecoder().decode(WireValue.self, from: data)) ?? .null
        guard (200..<300).contains(status) else {
            let detail = value["detail"].string ?? value["message"].string ?? value["error"].string ?? ""
            switch status {
            case 401: throw ExecutionRPCRejection("Devin rejected the API key. Check it in Settings. " + detail)
            case 403: throw ExecutionRPCRejection("This Devin API key can't use sessions in that organization. " + detail)
            case 404: throw ExecutionRPCRejection("Devin couldn't find that organization or session. " + detail)
            case 429: throw AppServerFailure("Devin's API is rate-limiting requests. Try again shortly.")
            default: throw AppServerFailure("Devin API error \(status). " + detail)
            }
        }
        return value
    }
    /// Checks the key and organization without starting anything.
    public func verify() async throws { _ = try await call("/sessions", query: [URLQueryItem(name: "first", value: "1")]) }
    public func createSession(prompt: String, title: String?) async throws -> WireValue {
        var body: [String: WireValue] = ["prompt": .string(prompt)]
        if let title, !title.isEmpty { body["title"] = .string(String(title.prefix(100))) }
        return try await call("/sessions", method: "POST", body: .object(body))
    }
    public func session(_ devinID: String) async throws -> WireValue { try await call("/sessions/" + devinID) }
    public func message(_ devinID: String, _ text: String) async throws -> WireValue {
        try await call("/sessions/" + devinID + "/messages", method: "POST", body: .object(["message": .string(text)]))
    }
    /// Every message after `cursor`, following the pages.
    public func messages(_ devinID: String, after cursor: String?) async throws -> (items: [WireValue], cursor: String?) {
        var items: [WireValue] = [], next = cursor, pages = 0
        repeat {
            var query = [URLQueryItem(name: "first", value: "200")]
            if let next { query.append(URLQueryItem(name: "after", value: next)) }
            let page = try await call("/sessions/" + devinID + "/messages", query: query)
            items += page["items"].array
            if let end = page["end_cursor"].string { next = end }
            pages += 1
            guard page["has_next_page"].bool, pages < 20 else { break }
        } while true
        return (items, next)
    }
    /// The id the session routes take: `devin-` plus the session id.
    public static func devinID(_ sessionID: String) -> String { sessionID.hasPrefix("devin-") ? sessionID : "devin-" + sessionID }
}

/// A Devin cloud conversation, translated into the events Diorama reads from local agents.
/// The Diorama thread id is local (`devin-cloud:<uuid>`); Devin's session is created with the
/// first message, and the link between them is saved so the chat can continue after a relaunch.
public actor DevinCloudTransport: ExecutionTransport {
    public nonisolated let events: AsyncStream<WireValue>
    private let sink: AsyncStream<WireValue>.Continuation
    public let threadID: String
    private let folder: String
    private let api: DevinCloudAPI
    private var context: String?
    private var record: Record
    private var turn: String?
    private var poller: Task<Void, Never>?
    private var interval: Duration

    struct Record: Codable {
        var sessionID: String?
        var url: String?
        var cursor: String?
        var title: String?
    }

    public init(api: DevinCloudAPI, folder: String, threadID: String? = nil, context: String? = nil, pollInterval: Duration = .seconds(4)) {
        self.api = api; self.folder = folder; self.context = context; self.interval = pollInterval
        self.threadID = threadID ?? DevinCloudAPI.threadPrefix + UUID().uuidString.lowercased()
        record = (try? JSONDecoder().decode(Record.self, from: Data(contentsOf: Self.file(self.threadID)))) ?? Record()
        (events, sink) = AsyncStream.makeStream(of: WireValue.self)
    }
    deinit { poller?.cancel(); sink.finish() }

    static func file(_ thread: String) -> URL {
        let safe = thread.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/DevinCloud/" + safe + ".json")
    }
    private func save() {
        let file = Self.file(threadID)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? JSONEncoder().encode(record).write(to: file, options: .atomic)
    }
    private func emit(_ method: String, _ values: [String: WireValue] = [:]) {
        var p = values; p["threadId"] = .string(threadID)
        if let turn { p["turnId"] = .string(turn) }
        sink.yield(.object(["method": .string(method), "params": .object(p)]))
    }

    public func connect() async throws {}
    public func respond(id: WireValue, result: WireValue) throws { throw ExecutionRPCRejection("Devin cloud sessions ask for approval in the Devin app.") }
    public func reject(id: WireValue, message: String) throws {}
    public func shutdown() { poller?.cancel(); poller = nil }

    private var settings: WireValue {
        .object(["thread": .object(["id": .string(threadID)]), "cwd": .string(folder), "model": .string(DevinCloudAPI.modelID), "approvalPolicy": .null])
    }
    public func request(_ method: String, _ p: WireValue) async throws -> WireValue {
        switch method {
        case "thread/start", "thread/resume": return settings
        case "thread/read": return .object(["thread": .object(["id": .string(threadID), "cwd": .string(folder), "turns": .array([])])])
        case "thread/goal/get": return .object(["goal": .null])
        case "collaborationMode/list": return .object(["data": .array([.object(["mode": .string("default")])])])
        case "diorama/capabilities": return .object([:])
        case "thread/queue/list", "thread/backgroundTerminals/list": return .object(["data": .array([])])
        case "diorama/permissions/set": throw ExecutionRPCRejection("Devin cloud sessions use your organization's Devin settings.")
        case "turn/start":
            guard turn == nil else { throw ExecutionRPCRejection("Wait for Devin to reply or stop watching first.") }
            let parts = p["input"].array
            guard !parts.contains(where: { $0["type"].string == "localImage" }) else { throw ExecutionRPCRejection("Devin's cloud can't see files on this Mac. Describe the image or put it in the repository.") }
            let text = parts.compactMap { $0["text"].string }.joined(separator: "\n")
            let id = UUID().uuidString
            turn = id
            emit("turn/started", ["turn": .object(["id": .string(id)])])
            emit("item/completed", ["item": .object(["id": .string(UUID().uuidString), "type": .string("userMessage"), "content": p["input"]])])
            do {
                if let session = record.sessionID {
                    _ = try await api.message(DevinCloudAPI.devinID(session), text)
                } else {
                    let reply = try await api.createSession(prompt: await firstPrompt(text), title: String(text.prefix(80)))
                    guard let session = reply["session_id"].string else { throw AppServerFailure("Devin didn't return a session.") }
                    record.sessionID = session; record.url = reply["url"].string; save()
                    let link = record.url.map { "Devin is working on this in the cloud. Follow along: " + $0 } ?? "Devin is working on this in the cloud."
                    emit("item/completed", ["item": .object(["id": .string(session + ":link"), "type": .string("agentMessage"), "text": .string(link)])])
                }
            } catch {
                emit("turn/completed", ["turn": .object(["id": .string(id), "status": .string("failed")])])
                turn = nil
                throw ExecutionRPCRejection(error.localizedDescription)
            }
            context = nil
            watch(id)
            return .object(["turn": .object(["id": .string(id)])])
        case "turn/interrupt":
            guard let id = turn else { throw ExecutionRPCRejection("No active Devin turn") }
            // The API has no pause: Diorama stops waiting, and Devin's session keeps its state.
            poller?.cancel(); poller = nil
            emit("item/completed", ["item": .object(["id": .string(id + ":stopped"), "type": .string("agentMessage"),
                 "text": .string("Stopped waiting here. Devin may keep working in the cloud" + (record.url.map { ": " + $0 } ?? "."))])])
            emit("turn/completed", ["turn": .object(["id": .string(id), "status": .string("interrupted")])])
            turn = nil
            return .object([:])
        default: throw ExecutionRPCRejection("This action isn't available for Devin cloud sessions: " + method)
        }
    }

    /// The first message carries Diorama's context and which repository the person means,
    /// since Devin's machine can't see this Mac's folder.
    private func firstPrompt(_ text: String) async -> String {
        var parts: [String] = []
        if let repo = await Self.repository(folder) { parts.append("Work in the GitHub repository \(repo.name)" + (repo.branch.map { " (the person's current branch is \($0))" } ?? "") + ". Open a pull request for changes.") }
        if let context, !context.isEmpty { parts.append("<diorama_context>\n" + context + "\n</diorama_context>") }
        parts.append(text)
        return parts.joined(separator: "\n\n")
    }
    static func repository(_ folder: String) async -> (name: String, branch: String?)? {
        guard let remote = try? await ProjectCommand.run("/usr/bin/git", ["-C", folder, "remote", "get-url", "origin"]) else { return nil }
        guard let name = githubName(remote) else { return nil }
        let branch = try? await ProjectCommand.run("/usr/bin/git", ["-C", folder, "rev-parse", "--abbrev-ref", "HEAD"])
        return (name, branch.flatMap { $0.isEmpty || $0 == "HEAD" ? nil : $0 })
    }
    /// "owner/repo" from an https or ssh GitHub remote.
    static func githubName(_ remote: String) -> String? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:", "ssh://git@github.com/"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            if value.hasSuffix(".git") { value.removeLast(4) }
            let parts = value.split(separator: "/")
            return parts.count == 2 ? parts.joined(separator: "/") : nil
        }
        return nil
    }

    /// Reads Devin's new messages until it's waiting on the person or done.
    private func watch(_ id: String) {
        poller?.cancel()
        poller = Task { [weak self] in
            let started = Date()
            var picked = false
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let (fresh, state, detail) = try await self.poll()
                    if fresh || ["working", "waiting_for_approval"].contains(detail) || state == "running" { picked = true }
                    // Until Devin has taken up the message, an earlier "waiting" isn't an answer.
                    let settled = picked || Date().timeIntervalSince(started) > 90
                    if let outcome = Self.outcome(status: state, detail: detail), settled {
                        await self.finish(id, outcome.status, notice: outcome.notice); return
                    }
                } catch {
                    await self.notice(id, "Couldn't check on Devin: " + error.localizedDescription)
                }
                try? await Task.sleep(for: await self.interval)
            }
        }
    }
    private var approvalNoted = false
    /// New messages since the last read, and the session's state.
    private func poll() async throws -> (Bool, String?, String?) {
        guard let session = record.sessionID else { return (false, nil, nil) }
        let devinID = DevinCloudAPI.devinID(session)
        let page = try await api.messages(devinID, after: record.cursor)
        var fresh = false
        for item in page.items where item["source"].string == "devin" {
            guard let text = item["message"].string, !text.isEmpty else { continue }
            fresh = true
            emit("item/completed", ["item": .object(["id": .string(item["event_id"].string ?? UUID().uuidString), "type": .string("agentMessage"), "text": .string(text)])])
        }
        if page.cursor != record.cursor { record.cursor = page.cursor; save() }
        let state = try await api.session(devinID)
        let detail = state["status_detail"].string
        if detail == "waiting_for_approval", !approvalNoted, let id = turn {
            approvalNoted = true
            notice(id, "Devin is waiting for an approval in the Devin app" + (record.url.map { ": " + $0 } ?? "."))
        } else if detail != "waiting_for_approval" { approvalNoted = false }
        return (fresh, state["status"].string, detail)
    }
    static func outcome(status: String?, detail: String?) -> (status: String, notice: String?)? {
        switch detail {
        case "waiting_for_user", "finished": return ("completed", nil)
        case "usage_limit_exceeded", "out_of_credits", "out_of_quota", "no_quota_allocation", "payment_declined",
             "org_usage_limit_exceeded", "user_usage_limit_exceeded", "total_session_limit_exceeded", "contract_expired":
            return ("failed", "Devin stopped: " + (detail ?? "").replacingOccurrences(of: "_", with: " ") + ".")
        case "error": return ("failed", "Devin reported an error in the cloud session.")
        default: break
        }
        switch status {
        case "exit": return ("completed", nil)
        case "error": return ("failed", "Devin reported an error in the cloud session.")
        case "suspended": return ("completed", "Devin paused the session. Send a message to wake it.")
        default: return nil
        }
    }
    private func notice(_ id: String, _ text: String) {
        guard turn == id else { return }
        emit("item/completed", ["item": .object(["id": .string(id + ":notice:" + String(text.hashValue)), "type": .string("agentMessage"), "text": .string(text)])])
    }
    private func finish(_ id: String, _ status: String, notice text: String?) {
        guard turn == id else { return }
        if let text { emit("error", ["error": .object(["message": .string(text)])]) }
        emit("turn/completed", ["turn": .object(["id": .string(id), "status": .string(status)])])
        turn = nil; poller = nil
    }
}
