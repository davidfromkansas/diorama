import Foundation

/// Provider routing is internal. Existing Codex wire behavior remains unchanged.
public actor AgentExecutionTransport: ExecutionTransport {
    public nonisolated let events: AsyncStream<WireValue>
    private let sink: AsyncStream<WireValue>.Continuation
    private let codex: any ExecutionTransport
    private let claudeProbe: (@Sendable () async throws -> [WireValue])?
    private var claude: [String: ClaudeExecutionTransport] = [:]
    /// Devin conversations: `devin acp` sessions, and cloud sessions through Devin's API.
    private var devin: [String: any ExecutionTransport] = [:]
    private let devinProbe: (@Sendable () async throws -> [WireValue])?
    /// The saved API key, checked against Devin's API. Nil when none is saved.
    private let devinCloudProbe: (@Sendable () async throws -> DevinCloudAPI?)?
    private var devinCloud: DevinCloudAPI?
    private var devinCloudError: String?
    private var checkingDevinCloud = false
    private var devinCatalog: [WireValue] = []
    private var devinError: String?
    private var checkingDevin = false
    /// The appended system prompt each Claude conversation was started or resumed with, so a
    /// process spawned again for it (resume, queued work) keeps the same instructions.
    private var contexts: [String: String] = [:]
    private var readers: [Task<Void, Never>] = []
    /// Which provider session asked each forwarded request, and its own id for it.
    private var requestOwners: [String: (provider: Provider, owner: String)] = [:]
    private var codexConnected = false
    private var codexError: String?
    private var codexCatalog: [WireValue] = []
    private var checkingCodex = false
    private var checkingClaude = false
    private var catalog: [WireValue] = []
    private var claudeError: String?
    public init(codex: any ExecutionTransport = CodexExecutionTransport(), claudeProbe: (@Sendable () async throws -> [WireValue])? = nil, devinProbe: (@Sendable () async throws -> [WireValue])? = nil, devinCloudProbe: (@Sendable () async throws -> DevinCloudAPI?)? = nil) {
        self.claudeProbe = claudeProbe; self.devinProbe = devinProbe; self.devinCloudProbe = devinCloudProbe
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
        async let d: Void = refreshDevin()
        async let api: Void = refreshDevinCloud()
        _ = await (c, a, d, api)
    }
    private func refreshDevin() async {
        checkingDevin = true; defer { checkingDevin = false }
        do {
            if let devinProbe { devinCatalog = try await devinProbe() } else { devinCatalog = try await DevinCatalog.probe() }
            devinError = nil
        }
        catch { devinCatalog = []; devinError = error.localizedDescription }
    }
    private func refreshDevinCloud() async {
        checkingDevinCloud = true; defer { checkingDevinCloud = false }
        do {
            if let devinCloudProbe { devinCloud = try await devinCloudProbe() }
            else if let saved = DevinCloudCredentials.load() {
                let api = DevinCloudAPI(credentials: saved)
                try await api.verify()
                devinCloud = api
            } else { devinCloud = nil }
            devinCloudError = nil
        } catch { devinCloud = nil; devinCloudError = error.localizedDescription }
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
    private func forward(_ value: WireValue, owner: String?, provider: Provider = .claude) {
        var e = value.object
        let tag = provider.key + ":"
        if let owner, value["method"].string == "diorama/sessionDisconnected" {
            if provider == .devin { devin.removeValue(forKey: owner) } else { claude.removeValue(forKey: owner) }
        }
        if let owner, value["id"] != .null {
            let external = WireValue.string(tag + owner + ":" + (value["id"].string ?? ""))
            requestOwners[external.key] = (provider, owner); e["id"] = external
        }
        if let owner, value["method"].string == "serverRequest/resolved" {
            var p = value["params"].object
            p["requestId"] = .string(tag + owner + ":" + (p["requestId"]?.string ?? "")); e["params"] = .object(p)
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
            return .object(["codex": .bool(codexConnected), "claude": .bool(!catalog.isEmpty), "claudeError": claudeError.map(WireValue.string) ?? .null, "codexError": codexError.map(WireValue.string) ?? .null, "codexChecking": .bool(checkingCodex), "claudeChecking": .bool(checkingClaude),
                            // "devin" is either way in: the CLI (subscription) or the API (usage billing).
                            "devin": .bool(!devinCatalog.isEmpty || devinCloud != nil),
                            "devinError": (devinCloud == nil ? devinError.map(WireValue.string) : nil) ?? .null,
                            "devinChecking": .bool(devinCatalog.isEmpty && devinCloud == nil && (checkingDevin || checkingDevinCloud)),
                            "devinCLI": .bool(!devinCatalog.isEmpty), "devinCLIError": devinError.map(WireValue.string) ?? .null, "devinCLIChecking": .bool(checkingDevin),
                            "devinAPI": .bool(devinCloud != nil), "devinAPIError": devinCloudError.map(WireValue.string) ?? .null, "devinAPIChecking": .bool(checkingDevinCloud)])
        }
        if method == "model/list" {
            return .object(["data": .array((codexConnected ? codexCatalog : []) + catalog + devinCatalog + (devinCloud == nil ? [] : [DevinCloudAPI.catalogRow]))])
        }
        if method == "collaborationMode/list", !codexConnected { return .object(["data": .array([.object(["mode": .string("default")]), .object(["mode": .string("plan")])])]) }
        let id = params["threadId"].string ?? ""
        if method == "diorama/capabilities" {
            guard params["dioramaProvider"].string == Provider.claude.rawValue, let transport = claude[id] else {
                return .object([:]) // Local metadata only. Never attach or resume to browse.
            }
            return try await transport.request(method, params)
        }
        if method == "thread/start", params["model"].string?.hasPrefix("claude/") == true {
            guard !catalog.isEmpty else { throw ExecutionRPCRejection(claudeError ?? "Connect Claude in Settings") }
            let newID = UUID().uuidString.lowercased()
            contexts[newID] = params["developerInstructions"].string
            let transport = ClaudeExecutionTransport(folder: params["cwd"].string ?? "", sessionID: newID, context: params["developerInstructions"].string, initialPermission: params["permissionMode"].string, initialModel: params["model"].string.map { String($0.dropFirst(7)) })
            try await transport.connect(); attach(transport, id: newID)
            var reply = try await transport.request(method, params).object; reply["model"] = params["model"]; reply["provider"] = .string(Provider.claude.rawValue)
            return .object(reply)
        }
        if let reply = try await routeDevin(method, params) { return reply }
        if method == "thread/read", params["dioramaProvider"].string == Provider.claude.rawValue {
            return .object(["thread": .object(["id": .string(id), "cwd": params["cwd"], "turns": .array([])])])
        }
        if method == "thread/resume", params["dioramaProvider"].string == Provider.claude.rawValue {
            if let instructions = params["developerInstructions"].string { contexts[id] = instructions }
            if claude[id] == nil {
                // A resumed process gets the same appended system prompt a new one would.
                let transport = ClaudeExecutionTransport(folder: params["cwd"].string ?? "", sessionID: id, resume: true, context: contexts[id] ?? AgentInstructions.compose(nil))
                try await transport.connect(); attach(transport, id: id)
            }
        }
        if method.hasPrefix("thread/queue/"), params["dioramaProvider"].string == Provider.claude.rawValue, claude[id] == nil {
            guard let folder = params["cwd"].string else { throw AppServerFailure("Original Claude working folder unavailable") }
            let transport = ClaudeExecutionTransport(folder: folder, sessionID: id, resume: true, context: contexts[id] ?? AgentInstructions.compose(nil))
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
    /// Devin conversations: started from a `devin/` model, or continued by their provider.
    private func routeDevin(_ method: String, _ params: WireValue) async throws -> WireValue? {
        let id = params["threadId"].string ?? ""
        let named = params["dioramaProvider"].string == Provider.devin.rawValue
        if method == "thread/start", params["model"].string == DevinCloudAPI.modelID {
            guard let api = devinCloud else { throw ExecutionRPCRejection(devinCloudError ?? "Add a Devin API key in Settings") }
            let transport = DevinCloudTransport(api: api, folder: params["cwd"].string ?? "", context: params["developerInstructions"].string)
            attach(transport, id: transport.threadID)
            var reply = try await transport.request(method, params).object; reply["provider"] = .string(Provider.devin.rawValue)
            return .object(reply)
        }
        if (method == "thread/resume" || method.hasPrefix("thread/queue/")) && named, devin[id] == nil, id.hasPrefix(DevinCloudAPI.threadPrefix) {
            guard let api = devinCloud else { throw ExecutionRPCRejection(devinCloudError ?? "Add a Devin API key in Settings to continue this cloud conversation") }
            attach(DevinCloudTransport(api: api, folder: params["cwd"].string ?? "", threadID: id), id: id)
        }
        if method == "thread/start", params["model"].string?.hasPrefix("devin/") == true {
            guard !devinCatalog.isEmpty else { throw ExecutionRPCRejection(devinError ?? "Connect Devin in Settings") }
            let transport = DevinExecutionTransport(folder: params["cwd"].string ?? "", context: params["developerInstructions"].string,
                                                    model: params["model"].string, permissionMode: params["permissionMode"].string)
            try await transport.connect()
            let newID = await transport.id
            contexts[newID] = params["developerInstructions"].string
            attach(transport, id: newID)
            var reply = try await transport.request(method, params).object; reply["provider"] = .string(Provider.devin.rawValue)
            return .object(reply)
        }
        if (method == "thread/resume" || method.hasPrefix("thread/queue/")) && named, devin[id] == nil {
            guard let folder = params["cwd"].string, !folder.isEmpty else { throw AppServerFailure("Original Devin working folder unavailable") }
            if let instructions = params["developerInstructions"].string { contexts[id] = instructions }
            let transport = DevinExecutionTransport(folder: folder, sessionID: id, context: contexts[id] ?? AgentInstructions.compose(nil))
            try await transport.connect(); attach(transport, id: id)
        }
        if let transport = devin[id] { return try await transport.request(method, params) }
        if named {
            switch method {
            case "thread/read": return .object(["thread": .object(["id": .string(id), "cwd": params["cwd"], "turns": .array([])])])
            case "thread/goal/get": return .object(["goal": .null])
            case "diorama/capabilities": return .object([:])
            default: throw ExecutionRPCRejection("Reconnect this Devin conversation before " + method)
            }
        }
        return nil
    }
    private func attach(_ transport: ClaudeExecutionTransport, id: String) {
        claude[id] = transport
        readers.append(Task { [weak self] in for await e in transport.events { await self?.forward(e, owner: id) } })
    }
    private func attach(_ transport: any ExecutionTransport, id: String) {
        devin[id] = transport
        readers.append(Task { [weak self] in for await e in transport.events { await self?.forward(e, owner: id, provider: .devin) } })
    }
    /// The forwarded request's owner and that session's own id for it, if a Claude or Devin session asked.
    private func owner(of id: WireValue) -> (provider: Provider, owner: String, local: WireValue)? {
        guard let entry = requestOwners[id.key], let key = id.string else { return nil }
        return (entry.provider, entry.owner, .string(String(key.dropFirst((entry.provider.key + ":" + entry.owner + ":").count))))
    }
    public func respond(id: WireValue, result: WireValue) async throws {
        if let found = owner(of: id) {
            if found.provider == .devin, let transport = devin[found.owner] { try await transport.respond(id: found.local, result: result) }
            else if let transport = claude[found.owner] { try await transport.respond(id: found.local, result: result) }
            else { throw ExecutionRPCRejection("This request is no longer pending") }
            requestOwners.removeValue(forKey: id.key)
        } else { try await codex.respond(id: id, result: result) }
    }
    public func reject(id: WireValue, message: String) async throws {
        if let found = owner(of: id) {
            if found.provider == .devin, let transport = devin[found.owner] { try await transport.reject(id: found.local, message: message) }
            else if let transport = claude[found.owner] { try await transport.reject(id: found.local, message: message) }
            requestOwners.removeValue(forKey: id.key)
        } else { try await codex.reject(id: id, message: message) }
    }
    public func shutdown() async {
        for t in claude.values { await t.shutdown() }
        for t in devin.values { await t.shutdown() }
        await codex.shutdown()
    }
}
