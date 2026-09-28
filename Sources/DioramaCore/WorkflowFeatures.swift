import Foundation

public struct CapabilityInput: Identifiable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let kind: String
    public var id: String { kind + ":" + path }
    public var wire: WireValue { .object(["type": .string(kind), "name": .string(name), "path": .string(path)]) }
    public init(name: String, path: String, kind: String) { self.name = name; self.path = path; self.kind = kind }
}
public struct WorkflowState: Sendable {
    public var goal: WireValue = .null
    public var usage: WireValue = .null
    public var queue: [WireValue] = []
    public var mode = "default"
    public var queueUncertain = false
    public var steeredQueueIDs: Set<String> = []
    public init() {}
}
public struct ConversationSearchPage: Sendable {
    public let rows: [WireValue]
    public let nextCursor: String?
}
public extension WireValue {
    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var scalarText: String { string ?? number.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "Unknown" }
}

extension ExecutionController {
    func ensureConnection() async throws {
        if !connected { await connect() }
        guard connected else { throw AppServerFailure(error ?? "Codex connection unavailable") }
    }
    func requireIdle(_ id: String, allowProviderSwitch: Bool = false) throws {
        try requireControllable(id)
        guard (allowProviderSwitch || !providerSwitches.contains(id)), !retiredProviderSessions.contains(id), let task = tasks[id], task.attached, task.parentID == nil, !task.phase.active, !task.steering, !task.steeringUncertain,
              !requests.values.contains(where: { $0.threadID == id && $0.isBlocking }) else { throw AppServerFailure("Wait for this task to be idle and resolve required requests first") }
    }
    public func loadWorkflow(id: String) async {
        guard connected, tasks[id]?.attached == true else { return }
        do {
            // Finish the suspension before opening a mutable dictionary access.
            // A nested assignment across await writes an old task snapshot back
            // over events received while the provider request is in flight.
            let reply = try await transport.request("thread/goal/get", .object(["threadId": .string(id)]))
            tasks[id]?.workflow.goal = reply["goal"]
            featureErrors["goals"] = nil
        }
        catch { featureErrors["goals"] = error.localizedDescription }
        await refreshQueue(id: id)
    }
    public func loadModes() async {
        if !collaborationModes.isEmpty { return }
        do {
            try await ensureConnection()
            collaborationModes = try await transport.request("collaborationMode/list", .object([:]))["data"].array
            featureErrors["modes"] = nil
        } catch { featureErrors["modes"] = "Plan mode unavailable: " + error.localizedDescription }
    }
    public func loadUsage() async {
        do {
            try await ensureConnection()
            rateLimits = try await transport.request("account/rateLimits/read", .object([:]))
            featureErrors["usage"] = nil
        } catch { featureErrors["usage"] = error.localizedDescription }
    }
    /// Activation may continue work automatically. Only called by explicit goal controls.
    public func setGoal(id: String, objective: String? = nil, status: String, tokenBudget: Int? = nil, activateSubmittedGoal: Bool = false, prepareSubmission: Bool = false) async throws {
        guard (!retiredProviderSessions.contains(id) && !providerSwitches.contains(id)) || status == "paused" else { throw AppServerFailure("Resume the goal in the current Diorama conversation") }
        guard connected, !workflowBusy.contains(id), tasks[id]?.attached == true else { throw AppServerFailure("Connect this task before changing its goal") }
        guard ["active", "paused"].contains(status) else { throw AppServerFailure("Choose active or paused") }
        if let objective, objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw AppServerFailure("Enter a goal") }
        if let tokenBudget, tokenBudget <= 0 { throw AppServerFailure("Token budget must be positive") }
        workflowBusy.insert(id); defer { workflowBusy.remove(id) }
        var p: [String: WireValue] = ["threadId": .string(id), "status": .string(status)]
        if let objective { p["objective"] = .string(objective) }
        if let tokenBudget { p["tokenBudget"] = .number(Double(tokenBudget)) }
        if prepareSubmission, tasks[id]?.provider == .claude { p["prepareSubmission"] = .bool(true) }
        if activateSubmittedGoal, tasks[id]?.provider == .claude { p["activateSubmittedGoal"] = .bool(true) }
        let reply = try await transport.request("thread/goal/set", .object(p))
        guard reply["goal"] != .null else { throw AppServerFailure("Goal update outcome unknown; refresh before retrying") }
        tasks[id]?.workflow.goal = reply["goal"]
    }
    public func clearGoal(id: String) async throws {
        guard connected, tasks[id]?.attached == true, !workflowBusy.contains(id) else { throw AppServerFailure("Task unavailable") }
        workflowBusy.insert(id); defer { workflowBusy.remove(id) }
        let reply = try await transport.request("thread/goal/clear", .object(["threadId": .string(id)]))
        guard reply["cleared"].bool else { throw AppServerFailure("Goal was not cleared; refresh its state") }
        tasks[id]?.workflow.goal = .null
    }
    public func compact(id: String) async throws {
        try requireIdle(id)
        _ = try await transport.request("thread/compact/start", .object(["threadId": .string(id)]))
    }
    /// Explicit recovery action: pause the persisted goal before reacquiring its conversation.
    public func pauseGoalAndResume(session: Session) async throws {
        guard session.provider == .codex, !session.archived, session.parentID == nil else { throw AppServerFailure("Choose a main Codex conversation") }
        try await ensureConnection()
        let reply = try await transport.request("thread/goal/set", .object(["threadId": .string(session.sessionID), "status": .string("paused")]))
        guard reply["goal"]["status"].string == "paused" else { throw AppServerFailure("Goal pause was not confirmed; conversation was not resumed") }
        try await resumeImported(session)
    }
    public func rename(session: Session, name: String) async throws {
        guard session.provider == .codex, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppServerFailure("Enter a Codex conversation name") }
        try await ensureConnection()
        _ = try await transport.request("thread/name/set", .object(["threadId": .string(session.sessionID), "name": .string(name)]))
        tasks[session.sessionID]?.title = name
        persist()
    }
    public func setArchived(session: Session, archived: Bool) async throws {
        guard session.provider == .codex, !workflowBusy.contains(session.sessionID) else { throw AppServerFailure("Conversation unavailable") }
        if let task = tasks[session.sessionID], task.phase.active || task.workflow.goal["status"].string == "active" { throw AppServerFailure("Stop work and pause the goal before archiving") }
        try await ensureConnection()
        workflowBusy.insert(session.sessionID); defer { workflowBusy.remove(session.sessionID) }
        _ = try await transport.request(archived ? "thread/archive" : "thread/unarchive", .object(["threadId": .string(session.sessionID)]))
        if archived { tasks.removeValue(forKey: session.sessionID); persist() }
    }
    public func fork(session: Session, through turnID: String? = nil, folder: String? = nil, projectContext: String? = nil) async throws -> String {
        guard session.provider == .codex, session.classification != .internalReview, session.parentID == nil,
              !workflowBusy.contains(session.sessionID), tasks[session.sessionID]?.phase.active != true else { throw AppServerFailure("Fork an idle main conversation") }
        try await ensureConnection()
        workflowBusy.insert(session.sessionID); defer { workflowBusy.remove(session.sessionID) }
        var p: [String: WireValue] = ["threadId": .string(session.sessionID), "deferGoalContinuation": .bool(true), "excludeTurns": .bool(true)]
        if let folder { p["cwd"] = .string(folder) }
        if let projectContext { p["developerInstructions"] = .string(projectContext) }
        if let turnID { p["lastTurnId"] = .string(turnID) }
        let reply = try await transport.request("thread/fork", .object(p))
        guard let id = reply["thread"]["id"].string, id != session.sessionID else { throw AppServerFailure("Fork outcome unknown. Check history before retrying") }
        var task = ExecutedTask(id: id, title: "Fork · " + session.title, folder: folder ?? session.project, attached: true)
        applySettings(reply, to: &task)
        tasks[id] = task; persist()
        if let folder, URL(fileURLWithPath: task.folder).resolvingSymlinksInPath() != URL(fileURLWithPath: folder).resolvingSymlinksInPath() {
            throw AppServerFailure("Fork \(id) did not use the requested worktree. No message was sent; inspect it in Imported activity.")
        }
        await loadWorkflow(id: id)
        return id
    }
    public func review(id: String, baseBranch: String? = nil) async throws {
        try requireIdle(id)
        guard !workflowBusy.contains(id) else { throw AppServerFailure("An operation is already pending") }
        workflowBusy.insert(id); defer { workflowBusy.remove(id) }
        var target: [String: WireValue] = ["type": .string("uncommittedChanges")]
        if let baseBranch, !baseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { target = ["type": .string("baseBranch"), "branch": .string(baseBranch)] }
        tasks[id]?.phase = .submitting; tasks[id]?.requiresReconciliation = true
        tasks[id]?.work = ExecutionWork()
        do {
            let reply = try await transport.request("review/start", .object(["threadId": .string(id), "delivery": .string("inline"), "target": .object(target)]))
            guard reply["reviewThreadId"].string == id, let turn = reply["turn"]["id"].string else { throw AppServerFailure("Review outcome unknown") }
            if tasks[id]?.terminalTurns.contains(turn) != true { tasks[id]?.turnID = turn; tasks[id]?.phase = .working; tasks[id]?.work.turnID = turn }
        } catch let e as ExecutionRPCRejection { tasks[id]?.phase = .ready; tasks[id]?.requiresReconciliation = false; throw e }
        catch { tasks[id]?.phase = .disconnected; throw error }
    }
    public func refreshQueue(id: String) async {
        do {
            var rows: [WireValue] = []; var cursor: String?; var seen = Set<String>()
            repeat {
                var p: [String: WireValue] = ["threadId": .string(id), "limit": .number(100)]
                if let cursor { p["cursor"] = .string(cursor) }
                let reply = try await transport.request("thread/queue/list", .object(p))
                if reply["deliveryUncertain"].bool { tasks[id]?.workflow.queueUncertain = true }
                guard case .array = reply["data"] else { throw AppServerFailure("Queue state unavailable") }
                rows += reply["data"].array; cursor = reply["nextCursor"].string
                if let cursor, !seen.insert(cursor).inserted { throw AppServerFailure("Queue cursor repeated") }
            } while cursor != nil
            tasks[id]?.workflow.queue = rows; featureErrors["queue:" + id] = nil
        } catch { featureErrors["queue:" + id] = "Queue unavailable: " + error.localizedDescription }
    }
    public func enqueue(id: String, prompt: String, attachments: [ConversationAttachment] = [], capabilities: [CapabilityInput] = []) async throws {
        guard !providerSwitches.contains(id), !retiredProviderSessions.contains(id), connected, tasks[id]?.attached == true, tasks[id]?.parentID == nil, tasks[id]?.workflow.queueUncertain != true, !workflowBusy.contains(id) else { throw AppServerFailure("Queue unavailable or a previous delivery needs reconciliation") }
        workflowBusy.insert(id); defer { workflowBusy.remove(id); scheduleNextQueued(id) }
        var input = try ConversationAttachment.input(prompt: prompt, attachments: attachments)
        for capability in capabilities {
            let valid = capability.kind == "skill" ? skills.contains { $0["path"].string == capability.path && $0["name"].string == capability.name && $0["enabled"].bool } : capability.kind == "mention" && apps.contains { "app://" + ($0["id"].string ?? "") == capability.path && $0["isAccessible"].bool && $0["isEnabled"] != .bool(false) }
            guard valid else { throw AppServerFailure("Selected queued capability is unavailable") }
            input.append(capability.wire)
        }
        let clientID = UUID().uuidString
        do {
            let reply = try await transport.request("thread/queue/add", .object(["threadId": .string(id), "clientUserMessageId": .string(clientID), "input": .array(input)]))
            guard reply["queuedSubmission"]["clientUserMessageId"].string == clientID else { throw AppServerFailure("Queue acknowledgement missing") }
            queueAutoStart.insert(id)
            await refreshQueue(id: id)
        } catch let e as ExecutionRPCRejection { throw e }
        catch { tasks[id]?.workflow.queueUncertain = true; throw AppServerFailure("Queued message delivery is uncertain. Refresh and inspect pending messages before retrying. " + error.localizedDescription) }
    }
    func scheduleNextQueued(_ id: String) {
        guard !retiredProviderSessions.contains(id), queueAutoStart.contains(id), tasks[id]?.attached == true, tasks[id]?.phase == .finished,
              tasks[id]?.workflow.goal["status"].string != "active", !workflowBusy.contains(id), tasks[id]?.workflow.queueUncertain != true, tasks[id]?.steeringUncertain != true else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshQueue(id: id)
            guard self.queueAutoStart.contains(id), self.tasks[id]?.phase == .finished, self.featureErrors["queue:" + id] == nil else { return }
            guard self.tasks[id]?.workflow.queue.isEmpty == false else { self.queueAutoStart.remove(id); return }
            do { try await self.startQueued(id: id) } catch { self.featureErrors["queue:" + id] = error.localizedDescription; self.queueAutoStart.remove(id) }
        }
    }
    public func acknowledgeQueueInspection(id: String) async throws {
        await refreshQueue(id: id)
        guard featureErrors["queue:" + id] == nil else { throw AppServerFailure("Queue could not be refreshed") }
        guard tasks[id]?.steeringUncertain != true, tasks[id]?.workflow.steeredQueueIDs.isEmpty == true else { throw AppServerFailure("Resolve steering delivery and remove its queued copy before resuming the queue") }
        if tasks[id]?.provider == .claude {
            let reply = try await transport.request("thread/queue/list", .object(["threadId": .string(id)]))
            guard !reply["deliveryUncertain"].bool else { throw AppServerFailure("Inspect history, then remove the uncertain queued copy with × before continuing.") }
        }
        tasks[id]?.workflow.queueUncertain = false
    }
    public func removeQueued(id: String, submissionID: String) async throws {
        guard connected, tasks[id]?.workflow.queue.contains(where: { $0["id"].string == submissionID }) == true else { throw AppServerFailure("Queued message no longer present") }
        let reply = try await transport.request("thread/queue/delete", .object(["threadId": .string(id), "queuedSubmissionId": .string(submissionID)]))
        guard reply["deleted"].bool else { throw AppServerFailure("Queue removal not confirmed") }
        tasks[id]?.workflow.steeredQueueIDs.remove(submissionID)
        persist()
        await refreshQueue(id: id)
    }
    /// Keep the provider queue intact until steering is acknowledged. Never auto-deliver
    /// a row that may already have been consumed by the active turn.
    public func steerQueued(id: String, submissionID: String) async throws {
        guard canSteer(id: id), !workflowBusy.contains(id),
              tasks[id]?.workflow.queueUncertain != true,
              let turn = tasks[id]?.turnID,
              let row = tasks[id]?.workflow.queue.first(where: { $0["id"].string == submissionID }) else {
            throw AppServerFailure("This queued message cannot steer the current turn")
        }
        workflowBusy.insert(id)
        queueAutoStart.remove(id)
        defer { workflowBusy.remove(id); scheduleNextQueued(id) }
        tasks[id]?.workflow.steeredQueueIDs.insert(submissionID)
        tasks[id]?.workflow.queueUncertain = true
        persist()
        tasks[id]?.steering = true
        defer { tasks[id]?.steering = false }
        do {
            let reply = try await transport.request("turn/steer", .object([
                "threadId": .string(id), "expectedTurnId": .string(turn),
                "clientUserMessageId": row["clientUserMessageId"], "input": row["input"]
            ]))
            guard reply["turnId"].string == turn else { throw AppServerFailure("Steering acknowledgement missing") }
        } catch let error as ExecutionRPCRejection {
            tasks[id]?.workflow.steeredQueueIDs.remove(submissionID)
            tasks[id]?.workflow.queueUncertain = false
            persist()
            throw error
        }
        catch {
            tasks[id]?.workflow.queueUncertain = true
            tasks[id]?.steeringUncertain = true
            tasks[id]?.requiresReconciliation = true
            throw AppServerFailure("Steering delivery is uncertain. Queue paused; inspect history before retrying.")
        }
        tasks[id]?.workflow.steeredQueueIDs.insert(submissionID)
        tasks[id]?.workflow.queueUncertain = true
        let reply = try await transport.request("thread/queue/delete", .object(["threadId": .string(id), "queuedSubmissionId": .string(submissionID)]))
        guard reply["deleted"].bool else { throw AppServerFailure("Message steered, but queue removal is unconfirmed. Queue remains paused.") }
        await refreshQueue(id: id)
        guard featureErrors["queue:" + id] == nil else { throw AppServerFailure("Message steered. Refresh the queue before continuing.") }
        tasks[id]?.workflow.steeredQueueIDs.remove(submissionID)
        tasks[id]?.workflow.queueUncertain = false
        persist()
        queueAutoStart.insert(id)
    }

    public func sendWithGoal(id: String, prompt: String, model: String = "", effort: String = "", attachments: [ConversationAttachment] = [], approvalReview: ApprovalReviewChoice = .inherit, mode: String = "default", capabilities: [CapabilityInput] = [], goal: Bool) async throws {
        try requireIdle(id)
        if goal {
            guard mode != "plan" else { throw AppServerFailure("Choose Plan or Goal, not both") }
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 4000 else { throw AppServerFailure("Enter a goal of 1–4,000 characters") }
            try await setGoal(id: id, objective: prompt, status: "paused", prepareSubmission: true)
        } else if tasks[id]?.workflow.goal["status"].string == "active" {
            try await setGoal(id: id, status: "paused")
        }
        try await send(id: id, prompt: prompt, model: model, effort: effort, attachments: attachments, approvalReview: approvalReview, mode: mode, capabilities: capabilities)
        if goal {
            do { try await setGoal(id: id, status: "active", activateSubmittedGoal: true) }
            catch { tasks[id]?.error = "Message sent, but the goal could not be activated: " + error.localizedDescription }
        }
    }

    public func startQueued(id: String) async throws {
        try requireIdle(id)
        guard !workflowBusy.contains(id), tasks[id]?.workflow.queueUncertain != true, let next = tasks[id]?.workflow.queue.first?["id"].string else { throw AppServerFailure("No confirmed pending message") }
        workflowBusy.insert(id); defer { workflowBusy.remove(id) }
        tasks[id]?.phase = .submitting; tasks[id]?.requiresReconciliation = true
        tasks[id]?.work = ExecutionWork()
        do {
            let reply = try await transport.request("thread/queue/start", .object(["threadId": .string(id), "queuedSubmissionId": .string(next)]))
            guard let turn = reply["turn"]["id"].string else { throw AppServerFailure("Queue start outcome unknown") }
            if tasks[id]?.terminalTurns.contains(turn) != true { tasks[id]?.turnID = turn; tasks[id]?.phase = .working; tasks[id]?.work.turnID = turn }
            await refreshQueue(id: id)
        } catch let e as ExecutionRPCRejection { tasks[id]?.phase = .ready; tasks[id]?.requiresReconciliation = false; throw e }
        catch { tasks[id]?.phase = .disconnected; throw error }
    }
    /// Reopening the same picker reuses recent results. Refresh explicitly bypasses the cache.
    public func loadIntegrations(folder: String, threadID: String?, forceRefresh: Bool = false) async {
        let context = [folder, threadID ?? ""]
        if integrationContext == context {
            guard !integrationsLoading else { return }
            if !forceRefresh, let date = integrationsLoadedAt, Date().timeIntervalSince(date) < 60 { return }
        } else {
            skills = []; apps = []; connectors = []; skillErrors = []
        }
        integrationContext = context
        let generation = UUID(); integrationGeneration = generation
        integrationsLoadedAt = nil
        appDirectoryLoading = false; appDirectoryLoaded = false; appDirectoryCursor = nil; appDirectoryCursors = []
        for key in ["skills", "app/installed", "app/list", "mcpServerStatus/list"] { featureErrors[key] = nil }
        integrationsLoading = true
        integrationSectionsLoading = ["skills", "app/installed", "mcpServerStatus/list"]
        defer {
            if integrationGeneration == generation {
                integrationsLoading = false; integrationSectionsLoading = []
                if ["skills", "app/installed", "mcpServerStatus/list"].allSatisfy({ featureErrors[$0] == nil }) {
                    integrationsLoadedAt = Date()
                }
            }
        }
        do { try await ensureConnection() }
        catch {
            guard integrationGeneration == generation else { return }
            for key in integrationSectionsLoading { featureErrors[key] = error.localizedDescription }
            return
        }
        guard integrationGeneration == generation else { return }
        async let skillLoad: Void = loadIntegrationSection("skills", folder: folder, threadID: threadID, forceRefresh: forceRefresh, generation: generation)
        async let appLoad: Void = loadIntegrationSection("app/installed", folder: folder, threadID: threadID, forceRefresh: forceRefresh, generation: generation)
        async let mcpLoad: Void = loadIntegrationSection("mcpServerStatus/list", folder: folder, threadID: threadID, forceRefresh: forceRefresh, generation: generation)
        _ = await (skillLoad, appLoad, mcpLoad)
    }

    private func loadIntegrationSection(_ section: String, folder: String, threadID: String?, forceRefresh: Bool, generation: UUID) async {
        defer { if integrationGeneration == generation { integrationSectionsLoading.remove(section) } }
        do {
            var p: [String: WireValue] = [:]
            if let threadID, tasks[threadID]?.attached == true { p["threadId"] = .string(threadID) }
            switch section {
            case "skills":
                let reply = try await transport.request("skills/list", .object(["cwds": .array([.string(folder)]), "forceReload": .bool(forceRefresh)]))
                guard integrationGeneration == generation else { return }
                skills = reply["data"].array.flatMap { $0["skills"].array }
                skillErrors = reply["data"].array.flatMap { $0["errors"].array }
            case "app/installed":
                p["forceRefresh"] = .bool(forceRefresh)
                let reply = try await transport.request(section, .object(p))
                guard integrationGeneration == generation else { return }
                apps = reply["apps"].array.map { app in .object(["id": app["id"], "name": app["runtimeName"].string == nil ? app["id"] : app["runtimeName"], "isAccessible": app["callable"], "isEnabled": app["enabled"]]) }
            default:
                var rows: [WireValue] = []; var cursor: String?; var seen = Set<String>()
                repeat {
                    p["limit"] = .number(100)
                    if let cursor { p["cursor"] = .string(cursor) }
                    let reply = try await transport.request(section, .object(p))
                    guard integrationGeneration == generation else { return }
                    rows += reply["data"].array; connectors = rows
                    cursor = reply["nextCursor"].string
                    if let cursor, !seen.insert(cursor).inserted { throw AppServerFailure("Integration cursor repeated") }
                } while cursor != nil
            }
            guard integrationGeneration == generation else { return }
            featureErrors[section] = nil
        } catch {
            guard integrationGeneration == generation else { return }
            featureErrors[section] = error.localizedDescription
        }
    }

    /// The remote directory can contain thousands of apps; fetch one page per user action.
    public func loadMoreApps(threadID: String?) async {
        guard !integrationSectionsLoading.contains("app/installed"), !appDirectoryLoading,
              !appDirectoryLoaded || appDirectoryCursor != nil else { return }
        let generation = integrationGeneration
        appDirectoryLoading = true
        defer { if integrationGeneration == generation { appDirectoryLoading = false } }
        do {
            var p: [String: WireValue] = ["limit": .number(100)]
            if let threadID, tasks[threadID]?.attached == true { p["threadId"] = .string(threadID) }
            if let cursor = appDirectoryCursor { p["cursor"] = .string(cursor) }
            let reply = try await transport.request("app/list", .object(p))
            guard integrationGeneration == generation else { return }
            let next = reply["nextCursor"].string
            if let next, appDirectoryCursors.contains(next) { throw AppServerFailure("App directory cursor repeated") }
            for app in reply["data"].array {
                if let i = apps.firstIndex(where: { $0["id"] == app["id"] }) { apps[i] = app }
                else { apps.append(app) }
            }
            if let next { appDirectoryCursors.insert(next) }
            appDirectoryCursor = next; appDirectoryLoaded = true
            featureErrors["app/list"] = nil
        } catch {
            guard integrationGeneration == generation else { return }
            featureErrors["app/list"] = "App directory unavailable; showing installed and previously loaded apps. " + error.localizedDescription
        }
    }
    public func connectorLogin(name: String, threadID: String?) async throws -> URL {
        guard connectors.contains(where: { $0["name"].string == name }) else { throw AppServerFailure("Unknown connector") }
        var p: [String: WireValue] = ["name": .string(name)]
        if let threadID, tasks[threadID]?.attached == true { p["threadId"] = .string(threadID) }
        let reply = try await transport.request("mcpServer/oauth/login", .object(p))
        guard let s = reply["authorizationUrl"].string, let url = URL(string: s), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw AppServerFailure("Connector did not provide a browser sign-in URL") }
        return url
    }
    public func reloadConnectors() async throws { _ = try await transport.request("config/mcpServer/reload", .object([:])) }
    public func setSkill(path: String, enabled: Bool) async throws {
        guard skills.contains(where: { $0["path"].string == path }) else { throw AppServerFailure("Unknown skill") }
        _ = try await transport.request("skills/config/write", .object(["path": .string(path), "enabled": .bool(enabled)]))
        if let i = skills.firstIndex(where: { $0["path"].string == path }) { var o = skills[i].object; o["enabled"] = .bool(enabled); skills[i] = .object(o) }
    }
    public func searchMessages(query: String, threadID: String?, archived: Bool = false, cursor: String? = nil) async throws -> ConversationSearchPage {
        try await ensureConnection()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .init(rows: [], nextCursor: nil) }
        var p: [String: WireValue] = ["searchTerm": .string(query), "limit": .number(50)]
        if let cursor { p["cursor"] = .string(cursor) }
        if let threadID { p["threadId"] = .string(threadID) } else { p["archived"] = .bool(archived) }
        let reply = try await transport.request(threadID == nil ? "thread/search" : "thread/searchOccurrences", .object(p))
        guard case .array = reply["data"] else { throw AppServerFailure("Message search is unavailable on this runtime") }
        return .init(rows: reply["data"].array, nextCursor: reply["nextCursor"].string)
    }
    public func searchTurn(threadID: String, turnID: String) async throws -> Transcript {
        var items: [[String: Any]] = []; var cursor: String?; var seen = Set<String>()
        repeat {
            var p: [String: WireValue] = ["threadId": .string(threadID), "turnId": .string(turnID), "limit": .number(100), "sortDirection": .string("asc")]
            if let cursor { p["cursor"] = .string(cursor) }
            let reply = try await transport.request("thread/items/list", .object(p))
            for entry in reply["data"].array { if let item = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry["item"])) as? [String: Any] { items.append(item) } }
            cursor = reply["nextCursor"].string
            if let cursor, !seen.insert(cursor).inserted { throw AppServerFailure("Item cursor repeated") }
        } while cursor != nil && items.count < 1000
        return try AppServerHistory.transcript(["turns": [["id": turnID, "items": items]]], limit: 1000)
    }
}

public extension Session {
    func updated(title: String? = nil, archived: Bool? = nil) -> Self {
        var value = Self(id: id, provider: provider, url: url, sessionID: sessionID, title: title ?? self.title, project: project, modified: modified, bytes: bytes, archived: archived ?? self.archived, parentID: parentID)
        value.classification = classification; value.classificationEvidence = classificationEvidence; value.historySource = historySource
        return value
    }
}
