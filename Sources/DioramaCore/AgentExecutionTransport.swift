import Foundation

/// Provider routing is internal. Existing Codex wire behavior remains unchanged.
public actor AgentExecutionTransport: ExecutionTransport {
    public nonisolated let events: AsyncStream<WireValue>
    private let sink: AsyncStream<WireValue>.Continuation
    private let codex: any ExecutionTransport
    private let claudeProbe: (@Sendable () async throws -> [WireValue])?
    private var claude: [String: ClaudeExecutionTransport] = [:]
    private var readers: [Task<Void, Never>] = []
    private var requestOwners: [String: String] = [:]
    private var codexConnected = false
    private var codexError: String?
    private var codexCatalog: [WireValue] = []
    private var checkingCodex = false
    private var checkingClaude = false
    private var catalog: [WireValue] = []
    private var claudeError: String?
    public init(codex: any ExecutionTransport = CodexExecutionTransport(), claudeProbe: (@Sendable () async throws -> [WireValue])? = nil) {
        self.claudeProbe = claudeProbe
        self.codex = codex; (events, sink) = AsyncStream.makeStream(of: WireValue.self)
    }
    deinit { for reader in readers { reader.cancel() }; sink.finish() }
    public func connect() async throws {
        if readers.isEmpty {
            readers.append(Task { [weak self, codex] in
                for await e in codex.events { await self?.forward(e, owner: nil) }
            })
        }
        async let c: Void = refreshCodex()
        async let a: Void = refreshClaude()
        _ = await (c, a)
    }
    private func refreshCodex() async {
        checkingCodex = true; defer { checkingCodex = false }
        do {
            try await codex.connect()
            let account = try await codex.request("account/read", .object(["refreshToken": .bool(false)]))
            guard account["account"] != .null else { codexConnected = false; codexCatalog = []; codexError = nil; return }
            var rows: [WireValue] = []; var cursor: WireValue = .null; var seen = Set<String>()
            repeat {
                let reply = try await codex.request("model/list", .object(["limit": .number(100), "cursor": cursor]))
                rows += reply["data"].array; cursor = reply["nextCursor"]
                if let value = cursor.string, !seen.insert(value).inserted { throw AppServerFailure("Model pagination repeated") }
            } while cursor.string != nil
            codexCatalog = rows; codexConnected = true; codexError = nil
        } catch { codexConnected = false; codexCatalog = []; codexError = error.localizedDescription }
    }
    private func refreshClaude() async {
        checkingClaude = true; defer { checkingClaude = false }
        if let claudeProbe {
            do { catalog = try await claudeProbe(); claudeError = nil }
            catch { catalog = []; claudeError = error.localizedDescription }
            return
        }
        guard ClaudeExecutionTransport.binary() != nil else { catalog = []; claudeError = "Install Claude Code to connect your subscription."; return }
        let probe = ClaudeExecutionTransport(folder: FileManager.default.homeDirectoryForCurrentUser.path)
        do {
            try await probe.connect()
            catalog = try await probe.request("model/list", .object([:]))["data"].array; claudeError = nil
        } catch { catalog = []; claudeError = error.localizedDescription }
        await probe.shutdown()
    }
    private func forward(_ value: WireValue, owner: String?) {
        var e = value.object
        if let owner, value["method"].string == "diorama/sessionDisconnected" { claude.removeValue(forKey: owner) }
        if let owner, value["id"] != .null {
            let external = WireValue.string("claude:" + owner + ":" + (value["id"].string ?? ""))
            requestOwners[external.key] = owner; e["id"] = external
        }
        if let owner, value["method"].string == "serverRequest/resolved" {
            var p = value["params"].object
            p["requestId"] = .string("claude:" + owner + ":" + (p["requestId"]?.string ?? "")); e["params"] = .object(p)
        }
        if owner == nil, value["method"].string == "diorama/disconnected" {
            codexConnected = false
            e["method"] = .string("diorama/providerDisconnected")
            var p = value["params"].object; p["provider"] = .string(Provider.codex.rawValue); e["params"] = .object(p)
        }
        sink.yield(.object(e))
    }
    public func request(_ method: String, _ params: WireValue) async throws -> WireValue {
        var p = params.object
        if method == "diorama/connections" {
            return .object(["codex": .bool(codexConnected), "claude": .bool(!catalog.isEmpty), "claudeError": claudeError.map(WireValue.string) ?? .null, "codexError": codexError.map(WireValue.string) ?? .null, "codexChecking": .bool(checkingCodex), "claudeChecking": .bool(checkingClaude)])
        }
        if method == "model/list" {
            return .object(["data": .array((codexConnected ? codexCatalog : []) + catalog)])
        }
        if method == "collaborationMode/list", !codexConnected { return .object(["data": .array([.object(["mode": .string("default")]), .object(["mode": .string("plan")])])]) }
        let id = params["threadId"].string ?? ""
        if method == "thread/start", params["model"].string?.hasPrefix("claude/") == true {
            guard !catalog.isEmpty else { throw ExecutionRPCRejection(claudeError ?? "Connect Claude in Settings") }
            let newID = UUID().uuidString.lowercased()
            let transport = ClaudeExecutionTransport(folder: params["cwd"].string ?? "", sessionID: newID, context: params["developerInstructions"].string)
            try await transport.connect(); attach(transport, id: newID)
            var reply = try await transport.request(method, params).object; reply["model"] = params["model"]; reply["provider"] = .string(Provider.claude.rawValue)
            return .object(reply)
        }
        if method == "thread/read", params["dioramaProvider"].string == Provider.claude.rawValue {
            return .object(["thread": .object(["id": .string(id), "cwd": params["cwd"], "turns": .array([])])])
        }
        if method == "thread/resume", params["dioramaProvider"].string == Provider.claude.rawValue {
            if claude[id] == nil {
                let transport = ClaudeExecutionTransport(folder: params["cwd"].string ?? "", sessionID: id, resume: true)
                try await transport.connect(); attach(transport, id: id)
            }
        }
        if method.hasPrefix("thread/queue/"), params["dioramaProvider"].string == Provider.claude.rawValue, claude[id] == nil {
            guard let folder = params["cwd"].string else { throw AppServerFailure("Original Claude working folder unavailable") }
            let transport = ClaudeExecutionTransport(folder: folder, sessionID: id, resume: true)
            try await transport.connect(); attach(transport, id: id)
        }
        if let transport = claude[id] { return try await transport.request(method, params) }
        if method == "thread/goal/get", params["dioramaProvider"].string == Provider.claude.rawValue { return .object(["goal": .null]) }
        p.removeValue(forKey: "dioramaProvider")
        if method == "thread/read" || method == "thread/goal/get" || method.hasPrefix("thread/queue/") { p.removeValue(forKey: "cwd") }
        if method == "thread/goal/get" || method == "thread/resume" { p.removeValue(forKey: "includeTurns") }
        guard codexConnected else { throw ExecutionRPCRejection("Connect OpenAI in Settings before using this model.") }
        return try await codex.request(method, .object(p))
    }
    private func attach(_ transport: ClaudeExecutionTransport, id: String) {
        claude[id] = transport
        readers.append(Task { [weak self] in for await e in transport.events { await self?.forward(e, owner: id) } })
    }
    public func respond(id: WireValue, result: WireValue) async throws {
        if let owner = requestOwners[id.key], let transport = claude[owner], let key = id.string {
            try await transport.respond(id: .string(String(key.dropFirst(("claude:" + owner + ":").count))), result: result)
            requestOwners.removeValue(forKey: id.key)
        } else { try await codex.respond(id: id, result: result) }
    }
    public func reject(id: WireValue, message: String) async throws {
        if let owner = requestOwners[id.key], let transport = claude[owner], let key = id.string {
            try await transport.reject(id: .string(String(key.dropFirst(("claude:" + owner + ":").count))), message: message)
            requestOwners.removeValue(forKey: id.key)
        } else { try await codex.reject(id: id, message: message) }
    }
    public func shutdown() async { for t in claude.values { await t.shutdown() }; await codex.shutdown() }
}
