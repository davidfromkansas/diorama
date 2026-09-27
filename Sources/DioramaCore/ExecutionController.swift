import Foundation
import Observation

public struct ExecutionModel: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let efforts: [String]
    public let defaultEffort: String
    public let isDefault: Bool
}
public enum ApprovalReviewChoice: String, CaseIterable, Sendable {
    case inherit, user, autoReview = "auto_review", fullAccess
    public var title: String {
        switch self {
        case .inherit: "Use current Codex settings"
        case .user: "Ask for approval"
        case .autoReview: "Approve for me"
        case .fullAccess: "Full access"
        }
    }
    public func overrides(folder: String) -> [String: WireValue] {
        guard self != .inherit else { return [:] }
        let sandbox: WireValue = self == .fullAccess
            ? .object(["type": .string("dangerFullAccess")])
            : .object(["type": .string("workspaceWrite"), "writableRoots": .array([.string(folder)]), "networkAccess": .bool(false)])
        return ["approvalsReviewer": .string(self == .autoReview ? "auto_review" : "user"),
                "approvalPolicy": .string(self == .fullAccess ? "never" : "on-request"), "sandboxPolicy": sandbox]
    }
    public static func reported(reviewer: String?, policy: WireValue, sandbox: WireValue) -> Self? {
        if sandbox["type"].string == "dangerFullAccess", policy.string == "never" { return .fullAccess }
        guard sandbox["type"].string == "workspaceWrite", !sandbox["networkAccess"].bool, policy.string == "on-request" else { return nil }
        if reviewer == "user" { return .user }
        if reviewer == "auto_review" { return .autoReview }
        return nil
    }

}
public enum ExecutionPhase: String, Sendable {
    case ready = "Ready", submitting = "Submitting", working = "Working", approval = "Awaiting approval", input = "Waiting for input"
    case finished = "Last turn finished", interrupted = "Interrupted", failed = "Last turn failed", disconnected = "Outcome unverified"
    public var active: Bool { [.submitting, .working, .approval, .input, .disconnected].contains(self) }
}
public struct ExecutedTask: Identifiable, Sendable {
    public let id: String
    public var provider: Provider = .codex
    public var title: String
    public var folder: String
    public var parentID: String?
    public var phase: ExecutionPhase = .ready
    public var turnID: String?
    public var attached = false
    public var requiresReconciliation = false
    public var settings = ""
    public var approvalReviewer: String?
    public var approvalPolicy: WireValue = .null
    public var sandbox: WireValue = .null
    public var model = ""
    public var effort = ""
    public var liveStartedAt: Date?
    public var transcript = Transcript()
    public var activity: [ActivityEvent] = []
    public var structuredActivity = SessionActivitySnapshot()
    public var error: String?
    public var canvasNotice: String?
    public var terminalTurns: Set<String> = []
    public var work = ExecutionWork()
    public var steering = false
    public var steeringUncertain = false
    public var reviewNotice: String?
    public var workflow = WorkflowState()
    public var toolProgress: [String: String] = [:]
}
public struct ExecutionRequest: Identifiable, Sendable {
    public let wireID: WireValue
    public let method: String
    public let params: WireValue
    public let receivedAt: Date
    public var responding = false
    public init(wireID: WireValue, method: String, params: WireValue, receivedAt: Date = Date()) {
        self.wireID = wireID; self.method = method; self.params = params; self.receivedAt = receivedAt
    }
    public var id: String { wireID.key }
    public var threadID: String { params["threadId"].string ?? "" }
    public var isInput: Bool { method == "item/tool/requestUserInput" }
    public var decisions: [String] { approvalDecisions.compactMap { $0.value.string } }
}
private struct TaskBookmark: Codable {
    let id: String; let folder: String; let title: String; let parentID: String?
    var pendingQueueSteers: Set<String>? = nil
    var provider: String? = nil
    var model: String? = nil
}

@Observable @MainActor
public final class ExecutionController {
    public internal(set) var tasks: [String: ExecutedTask] = [:]
    public private(set) var recordedActivity: [String: SessionActivitySnapshot] = [:]
    private var activityMembership: [String: [ActivitySessionIdentity]] = [:]
    public func registerActivityConversation(_ members: [ActivitySessionIdentity]) {
        for member in members {
            activityMembership[member.key] = members
            if tasks[member.id]?.provider != member.provider, let activityDirectory, recordedActivity[member.key] == nil {
                recordedActivity[member.key] = SessionActivityStore.read(directory: activityDirectory, provider: member.provider, id: member.id)
            }
        }
    }
    private var agentRefreshes: Set<String> = []
    private var childFilterAvailable: Bool?
    public private(set) var requests: [String: ExecutionRequest] = [:]
    public internal(set) var collaborationModes: [WireValue] = []
    public internal(set) var rateLimits: WireValue = .null
    public internal(set) var integrationsLoading = false
    public internal(set) var integrationSectionsLoading: Set<String> = []
    public internal(set) var appDirectoryLoading = false
    public internal(set) var appDirectoryLoaded = false
    public internal(set) var appDirectoryCursor: String?
    var integrationContext: [String] = []
    var integrationGeneration = UUID()
    var integrationsLoadedAt: Date?
    var appDirectoryCursors: Set<String> = []
    public internal(set) var skills: [WireValue] = []
    public internal(set) var apps: [WireValue] = []
    public internal(set) var connectors: [WireValue] = []
    public internal(set) var skillErrors: [WireValue] = []
    public internal(set) var featureErrors: [String: String] = [:]
    public internal(set) var workflowBusy: Set<String> = []
    var queueAutoStart: Set<String> = []
    var providerSwitches: Set<String> = []
    public var retiredProviderSessions: Set<String> = []
    public var conversationCanvasIdentity: [String: (Provider, String)] = [:]
    public private(set) var models: [ExecutionModel] = []
    public private(set) var connected = false
    public private(set) var connecting = false
    public var error: String?
    public private(set) var creating = false
    public private(set) var stopping = false
    public private(set) var resuming: Set<String> = []
    public private(set) var resumeErrors: [String: String] = [:]
    public static let handoffExplanation = "Continue this same conversation through Codex’s official resume API. Another client may still own it. Diorama never removes locks, archives, or forks to acquire it."
    let transport: any ExecutionTransport
    private let journal: URL?
    private let activityDirectory: URL?
    private let activityStore: SessionActivityStore?
    private var activityWrites: [String: Task<Void, Never>] = [:]
    private let canvas: ConversationCanvas?
    private var eventTask: Task<Void, Never>?
    private var sequence = 0
    public static var defaultJournal: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/owned-tasks.json")
    }
    public init(transport: any ExecutionTransport = CodexExecutionTransport(), journal: URL? = nil, canvas: ConversationCanvas? = nil) {
        self.transport = transport; self.journal = journal; self.canvas = canvas
        activityDirectory = journal?.deletingLastPathComponent().appendingPathComponent("SessionActivity")
        activityStore = activityDirectory.map { SessionActivityStore(directory: $0) }
        if let journal, let data = try? Data(contentsOf: journal), let saved = try? JSONDecoder().decode([TaskBookmark].self, from: data) {
            for item in saved { tasks[item.id] = ExecutedTask(id: item.id, title: item.title, folder: item.folder, parentID: item.parentID, phase: .disconnected, error: "Previous run: read saved history and explicitly reconnect before sending. No work has been restarted.")
                tasks[item.id]?.model = item.model ?? ""
                tasks[item.id]?.provider = Provider(rawValue: item.provider ?? "") ?? .codex
                if let activityDirectory {
                    let provider = tasks[item.id]!.provider
                    let snapshot = SessionActivityStore.read(directory: activityDirectory, provider: provider, id: item.id)
                    tasks[item.id]?.structuredActivity = snapshot
                }
                tasks[item.id]?.workflow.steeredQueueIDs = item.pendingQueueSteers ?? []
                tasks[item.id]?.workflow.queueUncertain = !(item.pendingQueueSteers ?? []).isEmpty
            }
        }
    }
    isolated deinit { eventTask?.cancel() }
    public var hasActiveWork: Bool { creating || stopping || !resuming.isEmpty || tasks.values.contains { $0.attached && ($0.phase.active || $0.steering || $0.workflow.goal["status"].string == "active") } || !requests.isEmpty }
    public var hasUncertainWork: Bool { tasks.values.contains { $0.phase == .disconnected && $0.requiresReconciliation } }
    public func connect() async {
        guard !connected, !connecting else { return }
        connecting = true; defer { connecting = false }
        if eventTask == nil {
            let events = transport.events
            eventTask = Task { [weak self] in
                for await event in events { guard let self else { break }; await self.receive(event) }
            }
        }
        do {
            try await transport.connect(); connected = true
            var fetched: [ExecutionModel] = []; var cursor: String?; var seen = Set<String>()
            repeat {
                var params: [String: WireValue] = ["limit": .number(100)]
                if let cursor { params["cursor"] = .string(cursor) }
                let response = try await transport.request("model/list", .object(params))
                for m in response["data"].array {
                    guard let id = m["model"].string else { continue }
                    fetched.append(.init(id: id, name: m["displayName"].string ?? id, efforts: m["supportedReasoningEfforts"].array.compactMap { $0["reasoningEffort"].string }, defaultEffort: m["defaultReasoningEffort"].string ?? "", isDefault: m["isDefault"].bool))
                }
                cursor = response["nextCursor"].string
                if let cursor, !seen.insert(cursor).inserted { throw AppServerFailure("Model pagination repeated") }
            } while cursor != nil
            models = fetched; error = nil
        } catch { self.error = error.localizedDescription }
    }
    public func refreshModels() async {
        connected = false
        await connect()
    }
    /// Read the router's cached catalog while independent provider checks complete.
    public func onboardingSnapshot() async -> WireValue {
        let info = await connectionInfo()
        guard info["codex"].bool || info["claude"].bool else { return info }
        if let reply = try? await transport.request("model/list", .object([:])) {
            models = reply["data"].array.compactMap { m in
                guard let id = m["model"].string else { return nil }
                return ExecutionModel(id: id, name: m["displayName"].string ?? id, efforts: m["supportedReasoningEfforts"].array.compactMap { $0["reasoningEffort"].string }, defaultEffort: m["defaultReasoningEffort"].string ?? "", isDefault: m["isDefault"].bool)
            }
        }
        return info
    }
    public func connectionInfo() async -> WireValue {
        (try? await transport.request("diorama/connections", .object([:]))) ?? .null
    }
    public func prepare(folder: String, title: String, model: String, projectContext: String? = nil) async throws -> String {
        guard connected, !creating, !stopping else { throw AppServerFailure("Connect an account before creating a task") }
        var isDirectory: ObjCBool = false
        guard folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else { throw AppServerFailure("Choose an existing working folder") }
        if !model.isEmpty, !models.contains(where: { $0.id == model }) { throw AppServerFailure("Choose a model from the provider catalog") }
        creating = true; defer { creating = false }
        var params: [String: WireValue] = ["cwd": .string(folder), "threadSource": .string("user")]
        if !model.isEmpty { params["model"] = .string(model) }
        if let projectContext { params["developerInstructions"] = .string(projectContext) }
        let reply = try await transport.request("thread/start", .object(params))
        guard let id = reply["thread"]["id"].string else { throw AppServerFailure("Task creation outcome unknown; inspect imported history before trying again") }
        var task = ExecutedTask(id: id, title: String(title.prefix(100)), folder: folder, attached: true)
        task.provider = model.hasPrefix("claude/") ? .claude : .codex
        applySettings(reply, to: &task)
        tasks[id] = task; persist()
        if projectContext != nil, URL(fileURLWithPath: task.folder).resolvingSymlinksInPath() != URL(fileURLWithPath: folder).resolvingSymlinksInPath() {
            throw AppServerFailure("Codex created task \(id) in a different working folder. No message was sent; inspect the prepared conversation.")
        }
        return id
    }
    func applySettings(_ reply: WireValue, to task: inout ExecutedTask) {
        task.folder = reply["cwd"].string ?? task.folder
        task.model = reply["model"].string ?? task.model
        task.effort = reply["reasoningEffort"].string ?? task.effort
        task.approvalReviewer = reply["approvalsReviewer"].string
        task.approvalPolicy = reply["approvalPolicy"]
        task.sandbox = reply["sandbox"]
        task.settings = "Model: \(task.model)\nWorking folder: \(task.folder)\nApproval policy: \(reply["approvalPolicy"].pretty)\nReviewer: \(reply["approvalsReviewer"].pretty)\nPermissions: \(reply["activePermissionProfile"].pretty)\nSandbox: \(reply["sandbox"].pretty)"
    }
    public private(set) var observedDesktopSessionIDs: Set<String> = []
    public func observeDesktopSessions(_ sessions: [Session]) {
        observedDesktopSessionIDs.formUnion(sessions.filter(\.observationOnly).map(\.sessionID))
    }
    func requireControllable(_ id: String) throws {
        guard !observedDesktopSessionIDs.contains(id) else {
            throw AppServerFailure("View-only Claude Code Desktop conversation. Continue it in Claude Desktop.")
        }
    }
    /// A user Send may acquire a released conversation, but never replay uncertain work.
    public func send(in session: Session, prompt: String, model: String = "", effort: String = "", attachments: [ConversationAttachment] = [], approvalReview: ApprovalReviewChoice = .inherit, mode: String? = nil, capabilities: [CapabilityInput] = []) async throws {
        if session.observationOnly { throw AppServerFailure(Self.resumeUnavailableReason(session)!) }
        _ = try ConversationAttachment.input(prompt: prompt, attachments: attachments)
        if let task = tasks[session.sessionID], task.phase == .disconnected, task.requiresReconciliation {
            throw AppServerFailure("Delivery is uncertain. Check conversation history and reconnect before sending again.")
        }
        if tasks[session.sessionID]?.attached != true || tasks[session.sessionID]?.phase == .disconnected {
            try await resumeImported(session)
        }
        try await send(id: session.sessionID, prompt: prompt, model: model, effort: effort, attachments: attachments, approvalReview: approvalReview, mode: mode, capabilities: capabilities)
    }

    public func send(id: String, prompt: String, model: String = "", effort: String = "", attachments: [ConversationAttachment] = [], approvalReview: ApprovalReviewChoice = .inherit, mode: String? = nil, capabilities: [CapabilityInput] = []) async throws {
        try requireControllable(id)
        guard !retiredProviderSessions.contains(id), !providerSwitches.contains(id) else { throw AppServerFailure("This provider session is historical or switching") }
        guard connected, !stopping, !workflowBusy.contains(id), var task = tasks[id], task.attached, task.parentID == nil, !task.phase.active, !task.steering, !task.steeringUncertain,
              !requests.values.contains(where: { $0.threadID == id && $0.isBlocking }) else { throw AppServerFailure("This task is not ready for a new turn") }
        var input = try ConversationAttachment.input(prompt: prompt, attachments: attachments)
        for capability in capabilities {
            let valid = capability.kind == "skill" ? skills.contains { $0["path"].string == capability.path && $0["name"].string == capability.name && $0["enabled"].bool } : capability.kind == "mention" && apps.contains { "app://" + ($0["id"].string ?? "") == capability.path && $0["isAccessible"].bool && $0["isEnabled"] != .bool(false) }
            guard valid else { throw AppServerFailure("Selected skill or connector is unavailable; refresh the picker") }
            input.append(capability.wire)
        }
        if let mode, !collaborationModes.contains(where: { $0["mode"].string == mode }) { throw AppServerFailure("This collaboration mode is not advertised by the runtime") }
        let selected = model.isEmpty ? task.model : model
        if !model.isEmpty, (model.hasPrefix("claude/") != (task.provider == .claude)) { throw ExecutionRPCRejection("Changing providers requires a new linked session.") }
        if !model.isEmpty, !models.contains(where: { $0.id == model }) { throw AppServerFailure("Model unavailable") }
        if !effort.isEmpty, !models.contains(where: { $0.id == selected && $0.efforts.contains(effort) }) { throw AppServerFailure("Reasoning effort unavailable for this model") }
        try await GitHubCheckoutLocks.shared.beginAgentSubmission(task.folder)
        guard let current = tasks[id], current.attached, !current.phase.active, current.phase == task.phase,
              !current.steering, !current.steeringUncertain else {
            await GitHubCheckoutLocks.shared.endAgentSubmission(task.folder)
            throw AppServerFailure("This task is not ready for a new turn")
        }
        if let canvas {
            do {
                let identity = conversationCanvasIdentity[id] ?? (task.provider, id)
                let url = try canvas.prepare(folder: task.folder, provider: identity.0, sessionID: identity.1, title: task.title)
                input.append(.object(["type": .string("text"), "text": .string(ConversationCanvas.instructions(for: url))]))
                task.canvasNotice = nil
            } catch {
                task.canvasNotice = "HTML view unavailable for this turn: \(error.localizedDescription)"
            }
        }
        if task.liveStartedAt == nil { task.liveStartedAt = Date() }
        task.work = ExecutionWork(); task.reviewNotice = nil
        task.phase = .submitting; task.requiresReconciliation = true; task.error = nil; task.transcript.source = "Live agent"
        tasks[id] = task
        await GitHubCheckoutLocks.shared.endAgentSubmission(task.folder)
        var params: [String: WireValue] = ["threadId": .string(id), "input": .array(input)]
        if !selected.isEmpty { params["model"] = .string(selected) }
        if !effort.isEmpty { params["effort"] = .string(effort) }
        if let mode {
            var settings: [String: WireValue] = ["model": .string(selected)]
            let selectedEffort = effort.isEmpty ? task.effort : effort
            if !selectedEffort.isEmpty { settings["reasoning_effort"] = .string(selectedEffort) }
            params["collaborationMode"] = .object(["mode": .string(mode), "settings": .object(settings)])
        }
        let permissionOverrides = approvalReview.overrides(folder: task.folder)
        params.merge(permissionOverrides) { _, override in override }
        do {
            let reply = try await transport.request("turn/start", .object(params))
            guard let turn = reply["turn"]["id"].string else { throw AppServerFailure("Turn submission outcome unknown") }
            if tasks[id]?.terminalTurns.contains(turn) != true {
                tasks[id]?.turnID = turn
                tasks[id]?.work.turnID = turn
                if tasks[id]?.phase == .submitting { tasks[id]?.phase = .working }
            }
            if approvalReview != .inherit {
                tasks[id]?.approvalReviewer = permissionOverrides["approvalsReviewer"]?.string
                tasks[id]?.approvalPolicy = permissionOverrides["approvalPolicy"] ?? .null
                tasks[id]?.sandbox = permissionOverrides["sandboxPolicy"] ?? .null
                let lines = tasks[id]?.settings.components(separatedBy: "\n") ?? []
                tasks[id]?.settings = lines.map { line in
                    if line.hasPrefix("Reviewer:") { return "Reviewer: \(permissionOverrides["approvalsReviewer"]?.pretty ?? "unknown")" }
                    if line.hasPrefix("Approval policy:") { return "Approval policy: \(permissionOverrides["approvalPolicy"]?.pretty ?? "unknown")" }
                    if line.hasPrefix("Sandbox:") { return "Sandbox: \(permissionOverrides["sandboxPolicy"]?.pretty ?? "unknown")" }
                    if line.hasPrefix("Permissions:") { return "Permissions: \(approvalReview.title) (accepted turn setting)" }
                    return line
                }.joined(separator: "\n")
            }
            if task.provider == .claude {
                tasks[id]?.sandbox = .null
                let permission = mode == "plan" ? "plan" : approvalReview == .fullAccess ? "bypassPermissions" : approvalReview == .autoReview ? "auto" : approvalReview == .user ? "default" : task.approvalPolicy.string == "plan" ? "default" : task.approvalPolicy.string ?? "default"
                tasks[id]?.approvalPolicy = .string(permission)
                tasks[id]?.settings = "Claude permission mode: \(permission)\nWorking folder: \(task.folder)\nPermissions are enforced by Claude Code."
            }
            if let mode { tasks[id]?.workflow.mode = mode }
            if !model.isEmpty { tasks[id]?.model = model }
            if !effort.isEmpty { tasks[id]?.effort = effort }
            persist()
        } catch let error as ExecutionRPCRejection {
            tasks[id]?.phase = .ready; tasks[id]?.requiresReconciliation = false; throw error
        } catch {
            tasks[id]?.phase = .disconnected
            tasks[id]?.error = "Submission outcome unverified. Reconcile before sending again. \(error.localizedDescription)"
            throw error
        }
    }
    public func canSteer(id: String) -> Bool {
        guard connected, !stopping, let task = tasks[id] else { return false }
        return [Provider.codex, .claude].contains(task.provider) && task.attached && task.parentID == nil && task.phase == .working && task.turnID != nil && !task.steering && !task.steeringUncertain && !requests.values.contains { $0.threadID == id && $0.isBlocking }
    }
    /// Never converts a stale correction into a new turn or retries uncertain delivery.
    public func steer(id: String, expectedTurnID: String, prompt: String, attachments: [ConversationAttachment] = []) async throws {
        try requireControllable(id)
        guard canSteer(id: id), tasks[id]?.turnID == expectedTurnID else { throw AppServerFailure("The active turn changed. Your correction was not sent; review it before sending a new turn.") }
        let input = try ConversationAttachment.input(prompt: prompt, attachments: attachments)
        tasks[id]?.steering = true
        defer { tasks[id]?.steering = false }
        do {
            let reply = try await transport.request("turn/steer", .object(["threadId": .string(id), "expectedTurnId": .string(expectedTurnID), "input": .array(input)]))
            guard reply["turnId"].string == expectedTurnID else { throw AppServerFailure("Correction acknowledgement did not identify the expected turn") }
        } catch let error as ExecutionRPCRejection {
            throw error
        } catch {
            tasks[id]?.steeringUncertain = true
            tasks[id]?.requiresReconciliation = true
            tasks[id]?.phase = .disconnected
            tasks[id]?.error = "Correction delivery is uncertain. Check saved history and reconnect before sending again. " + error.localizedDescription
            throw AppServerFailure(tasks[id]?.error ?? error.localizedDescription)
        }
    }

    public static func resumeUnavailableReason(_ session: Session) -> String? {
        if session.observationOnly { return "View-only Claude Code Desktop conversation. Continue it in Claude Desktop." }
        if session.archived { return "This conversation is archived. Restore it in its original client before continuing here." }
        if session.classification == .internalReview || session.classification == .subagent || session.parentID != nil {
            return "Internal reviews and subagents cannot be resumed as conversations."
        }
        return nil
    }
    /// User-initiated acquisition only. Read first; never send, archive, fork or remove locks.
    public func resumeImported(_ session: Session) async throws {
        let id = session.sessionID
        try requireControllable(id)
        guard !retiredProviderSessions.contains(id) else { throw AppServerFailure("This native session is historical. Continue in the Diorama conversation.") }
        guard !stopping, !resuming.contains(id) else { throw AppServerFailure("Resume is already pending") }
        if let reason = Self.resumeUnavailableReason(session) { throw AppServerFailure(reason) }
        if tasks[id]?.attached == true, tasks[id]?.phase != .disconnected { return }
        resuming.insert(id); resumeErrors[id] = nil
        defer { resuming.remove(id) }
        do {
            if !connected { await connect() }
            guard connected else { throw AppServerFailure(error ?? "Codex connection unavailable") }
            let identity: [String: WireValue] = ["threadId": .string(id), "includeTurns": .bool(false), "dioramaProvider": .string(session.provider.rawValue), "cwd": .string(session.project)]
            let stored = try await transport.request("thread/read", .object(identity))
            let thread = stored["thread"]
            guard thread["id"].string == id else { throw AppServerFailure("Provider returned a different conversation identity") }
            guard thread["parentThreadId"].string == nil, thread["canAcceptDirectInput"] != .bool(false), thread["threadSource"].string != "guardian_review" else {
                throw AppServerFailure("This record cannot accept direct user input")
            }
            var recentTurns = thread["turns"].array
            if session.provider == .codex {
                let page = try await transport.request("thread/turns/list", .object(["threadId": .string(id), "limit": .number(1), "sortDirection": .string("desc"), "itemsView": .string("notLoaded")]))
                guard case .array(let turns) = page["data"] else { throw AppServerFailure("Could not verify the latest turn. No message was sent.") }
                recentTurns = turns
            }
            if thread["status"]["type"].string == "active" || recentTurns.contains(where: { $0["status"].string == "inProgress" }) {
                throw AppServerFailure("This conversation has a recorded turn in progress. Finish or stop it in its original client, then retry.")
            }
            let folder = thread["cwd"].string ?? session.project
            var directory: ObjCBool = false
            guard folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &directory), directory.boolValue else {
                throw AppServerFailure("The recorded working folder is unavailable on this Mac")
            }
            let goal = try await transport.request("thread/goal/get", .object(identity))
            guard goal.object.keys.contains("goal") else { throw AppServerFailure("Could not verify that resume will leave work paused") }
            if goal["goal"]["status"].string == "active" { throw AppServerFailure("This conversation has an active goal. Finish or pause it in the original client before continuing here.") }
            var resumeIdentity = identity
            resumeIdentity["excludeTurns"] = .bool(true)
            let reply = try await transport.request("thread/resume", .object(resumeIdentity))
            guard reply["thread"]["id"].string == id else { throw AppServerFailure("Resume returned an unexpected conversation identity; no prompt was sent") }
            var task = ExecutedTask(id: id, provider: session.provider, title: session.title, folder: folder, attached: true)
            applySettings(reply, to: &task)
            if session.provider == .claude, let previous = tasks[id]?.model, !previous.isEmpty { task.model = previous }
            if reply["thread"]["status"]["type"].string == "active" {
                task.phase = .working; task.requiresReconciliation = true
                task.turnID = reply["thread"]["turns"].array.last { $0["status"].string == "inProgress" }?["id"].string
            }
            task.workflow.steeredQueueIDs = tasks[id]?.workflow.steeredQueueIDs ?? []
            task.workflow.queueUncertain = !task.workflow.steeredQueueIDs.isEmpty
            tasks[id] = task; persist()
        } catch {
            let detail = error.localizedDescription
            resumeErrors[id] = detail.contains("active writer") ? "This conversation is in use by another Codex client. Release it in that client, then retry.\n\nProvider: " + detail : detail
            throw AppServerFailure(resumeErrors[id] ?? detail)
        }
    }
    /// Reconnect only IDs previously acquired by Diorama; imports use resumeImported.
    public func reconnectOwned(id: String) async throws {
        guard connected, !stopping, let task = tasks[id], task.parentID == nil else { throw AppServerFailure(Self.handoffExplanation) }
        guard !task.attached || task.phase == .disconnected else { return }
        try await resumeImported(task.session)
    }

    public func interrupt(id: String) async throws {
        try requireControllable(id)
        queueAutoStart.remove(id)
        if tasks[id]?.workflow.goal["status"].string == "active" { try await setGoal(id: id, status: "paused") }
        guard connected, let task = tasks[id], task.attached, let turn = task.turnID else { throw AppServerFailure("No confirmed active turn to interrupt") }
        _ = try await transport.request("turn/interrupt", .object(["threadId": .string(id), "turnId": .string(turn)]))
        // Acknowledging the request is not the same as observing turn completion.
    }
    public func answer(id: String, result: WireValue) async throws {
        guard connected, let request = requests[id], !request.responding, tasks[request.threadID]?.attached == true else { throw AppServerFailure("This request is no longer actionable") }
        try requireControllable(request.threadID)
        if request.method == "item/commandExecution/requestApproval" || request.method == "item/fileChange/requestApproval" {
            guard request.approvalDecisions.contains(where: { $0.value == result["decision"] }) else { throw AppServerFailure("Decision is not offered by the provider") }
        } else if request.isInput {
            for q in request.params["questions"].array {
                guard let key = q["id"].string, !result["answers"][key]["answers"].array.isEmpty, result["answers"][key]["answers"].array.allSatisfy({ $0.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else { throw AppServerFailure("Answer each question") }
            }
        } else if request.isElicitation {
            try request.validateElicitation(result)
        } else if request.method == "item/permissions/requestApproval" {
            let granted = result["permissions"]
            guard result["scope"].string == "turn", granted == .object([:]) || granted == request.params["permissions"] else { throw AppServerFailure("Only requested permissions for this turn may be granted") }
        } else { throw AppServerFailure("Unsupported request") }
        requests[id]?.responding = true
        do { try await transport.respond(id: request.wireID, result: result) }
        catch { requests[id]?.responding = false; throw error }
    }
    private func terminals(_ id: String) async throws -> [WireValue] {
        let response = try await transport.request("thread/backgroundTerminals/list", .object(["threadId": .string(id)]))
        guard case .array(let data) = response["data"] else { throw AppServerFailure("Background-terminal state is unavailable") }
        return data
    }
    public func requiresQuitConfirmation() async throws -> Bool {
        if hasActiveWork || hasUncertainWork { return true }
        for task in tasks.values where task.attached { if !(try await terminals(task.id)).isEmpty { return true } }
        return false
    }
    public func stopBackgroundTerminals(id: String) async throws {
        guard connected, tasks[id]?.attached == true else { throw AppServerFailure("Only attached Diorama tasks can stop terminal processes") }
        for terminal in try await terminals(id) {
            guard let processID = terminal["processId"].string else { throw AppServerFailure("Terminal identity unavailable") }
            _ = try await transport.request("thread/backgroundTerminals/terminate", .object(["threadId": .string(id), "processId": .string(processID)]))
        }
        let deadline = Date().addingTimeInterval(8)
        while !(try await terminals(id)).isEmpty {
            guard Date() < deadline else { throw AppServerFailure("Terminal shutdown is not yet confirmed") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    public func stopAndShutdown() async throws {
        guard !creating, !stopping, resuming.isEmpty, !tasks.values.contains(where: { $0.steering }) else { throw AppServerFailure("Task creation/shutdown is still pending") }
        stopping = true; defer { stopping = false }
        queueAutoStart.removeAll()
        for task in tasks.values where task.attached && task.workflow.goal["status"].string == "active" { try await setGoal(id: task.id, status: "paused") }
        for task in tasks.values where task.attached && task.phase.active {
            guard task.turnID != nil, task.phase != .disconnected else { throw AppServerFailure("Cannot confirm the state of \(task.title). Keep Diorama open and reconcile first.") }
            try await interrupt(id: task.id)
        }
        guard !hasUncertainWork else { throw AppServerFailure("A disconnected task has an unverified outcome. Reconcile it before quitting.") }
        let deadline = Date().addingTimeInterval(15)
        while tasks.values.contains(where: { $0.attached && $0.phase.active }) || !requests.isEmpty {
            guard Date() < deadline else { throw AppServerFailure("Interruption has not been confirmed. Diorama is still open.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Stop-and-quit is an explicit user action covering owned terminal commands too.
        for task in tasks.values where task.attached { try await stopBackgroundTerminals(id: task.id) }
        for (id, task) in tasks {
            activityWrites[id]?.cancel()
            try await activityStore?.save(task.structuredActivity, provider: task.provider, id: id, members: activityMembership[task.provider.rawValue + ":" + id] ?? [])
        }
        await transport.shutdown(); connected = false
        for id in tasks.keys { tasks[id]?.attached = false }
    }
    func persist() {
        guard let journal else { return }
        do {
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let records = tasks.values.map { TaskBookmark(id: $0.id, folder: $0.folder, title: $0.title, parentID: $0.parentID, pendingQueueSteers: $0.workflow.steeredQueueIDs, provider: $0.provider.rawValue, model: $0.model) }
            try JSONEncoder().encode(records).write(to: journal, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        } catch { self.error = "Could not save task ownership: \(error.localizedDescription)" }
    }
    private func activity(_ id: String, kind: String, state: ActivityState? = nil, call: String? = nil, tool: String? = nil, detail: String? = nil) {
        guard let task = tasks[id] else { return }; sequence += 1
        let event = ActivityEvent(id: "live-\(sequence)", provider: task.provider.rawValue, sessionID: id, kind: kind, source: "App Server · connected execution", recordedAt: nil, observedAt: Date(), turnID: task.turnID, callID: call, parentID: task.parentID, tool: tool, detail: detail, state: state)
        tasks[id]?.activity.append(event)
        if let count = tasks[id]?.activity.count, count > 500 { tasks[id]?.activity.removeFirst(count - 500) }
    }
    public func receive(_ event: WireValue) async {
        let method = event["method"].string ?? "", p = event["params"]
        if method == "diorama/sessionDisconnected" || method == "diorama/providerDisconnected" {
            for id in tasks.keys where tasks[id]?.attached == true && (p["threadId"].string == id || p["provider"].string == tasks[id]?.provider.rawValue) {
                tasks[id]?.structuredActivity.lastKnown = true
                saveActivity(id)
                tasks[id]?.attached = false; tasks[id]?.phase = .disconnected; tasks[id]?.error = p["reason"].string
                requests = requests.filter { $0.value.threadID != id }
            }
            return
        }
        if method == "diorama/disconnected" {
            collaborationModes = []
            connected = false
            for id in tasks.keys where tasks[id]?.attached == true {
                tasks[id]?.attached = false
                if tasks[id]?.phase.active == true { tasks[id]?.phase = .disconnected }
                tasks[id]?.error = p["reason"].string
            }
            requests.removeAll(); error = p["reason"].string; return
        }
        if method == "thread/started", let id = p["thread"]["id"].string, let parent = p["thread"]["parentThreadId"].string, tasks[parent]?.attached == true {
            tasks[id] = ExecutedTask(id: id, title: p["thread"]["agentNickname"].string ?? "Subagent", folder: p["thread"]["cwd"].string ?? tasks[parent]!.folder, parentID: parent, attached: true)
            var state = tasks[parent]!.structuredActivity
            let item: WireValue = .object(["type": .string("collabAgentToolCall"), "id": .string(id), "senderThreadId": .string(parent), "receiverThreadIds": .array([.string(id)]), "agentsStates": .object([id: .object(["agentNickname": p["thread"]["agentNickname"], "status": p["thread"]["status"]["type"]])])])
            SessionActivityReducer.ingest(.object(["method": .string("item/started"), "params": .object(["item": item])]), provider: .codex, sessionID: parent, into: &state)
            tasks[parent]?.structuredActivity = state; saveActivity(parent)
            persist()
        }
        if method == "account/rateLimits/updated" { rateLimits = p; return }
        if ["warning", "configWarning", "deprecationNotice"].contains(method) { featureErrors[method] = p["message"].string ?? p.pretty; return }
        // Some notifications identify only the turn. Route only when that identity is unique.
        let matching = p["turnId"].string.map { turn in tasks.values.filter { $0.turnID == turn }.map(\.id) } ?? []
        let id = p["threadId"].string ?? p["thread"]["id"].string ?? (matching.count == 1 ? matching[0] : "")
        if let task = tasks[id] {
            var snapshot = task.structuredActivity
            SessionActivityReducer.ingest(event, provider: task.provider, sessionID: id, into: &snapshot)
            if snapshot != task.structuredActivity {
                tasks[id]?.structuredActivity = snapshot
                saveActivity(id)
            }
            switch method {
            case "thread/goal/updated": tasks[id]?.workflow.goal = p["goal"]; scheduleNextQueued(id); return
            case "thread/goal/cleared": tasks[id]?.workflow.goal = .null; return
            case "thread/tokenUsage/updated": tasks[id]?.workflow.usage = p["tokenUsage"]; return
            case "thread/queue/changed": await refreshQueue(id: id); return
            case "thread/name/updated": if let name = p["threadName"].string { tasks[id]?.title = name }; return
            default: break
            }
        }
        if event["id"] != .null {
            let supported = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/tool/requestUserInput", "item/permissions/requestApproval", "mcpServer/elicitation/request"]
            guard tasks[id]?.attached == true, supported.contains(method) else {
                // Explicit failure for client-executed tools; never run provider-supplied code.
                let result: WireValue
                if method == "item/tool/call" { result = .object(["success": .bool(false), "contentItems": .array([.object(["type": .string("inputText"), "text": .string("Diorama does not implement this client tool.")])])]) }
                else if method == "mcpServer/elicitation/request" { result = .object(["action": .string("cancel"), "content": .null]) }
                else {
                    try? await transport.reject(id: event["id"], message: "Unsupported request on this Diorama execution connection")
                    if tasks[id] != nil { tasks[id]?.error = "Unsupported provider request: \(method)" }
                    return
                }
                try? await transport.respond(id: event["id"], result: result)
                if tasks[id] != nil { tasks[id]?.error = "Unsupported provider request: \(method)" }
                return
            }
            if let turn = p["turnId"].string, tasks[id]?.terminalTurns.contains(turn) == true {
                try? await transport.reject(id: event["id"], message: "Request belongs to a completed turn")
                return
            }
            if let turn = p["turnId"].string, let current = tasks[id]?.turnID, turn != current {
                try? await transport.reject(id: event["id"], message: "Request belongs to a different turn")
                return
            }
            if tasks[id]?.turnID == nil { tasks[id]?.turnID = p["turnId"].string }
            let request = ExecutionRequest(wireID: event["id"], method: method, params: p, receivedAt: Date())
            requests[request.id] = request
            if request.isBlocking {
                refreshRequestPhase(id)
                activity(id, kind: request.isInput ? "input" : "approval", state: request.isInput ? .input : .approval, call: p["itemId"].string, detail: p["reason"].string)
            }
            return
        }
        guard tasks[id]?.attached == true else { return }
        if method == "serverRequest/resolved" {
            guard requests[p["requestId"].key]?.threadID == id else { return }
            requests.removeValue(forKey: p["requestId"].key)
            refreshRequestPhase(id)
            return
        }
        if let turn = p["turnId"].string, tasks[id]?.terminalTurns.contains(turn) == true { return }
        if let turn = p["turnId"].string, let current = tasks[id]?.turnID, turn != current { return }
        switch method {
        case "turn/started":
            let turn = p["turn"]["id"].string
            guard let turn, tasks[id]?.terminalTurns.contains(turn) != true, tasks[id]?.turnID == nil || tasks[id]?.turnID == turn else { return }
            if tasks[id]?.work.turnID != turn { tasks[id]?.work = ExecutionWork(); tasks[id]?.work.turnID = turn }
            tasks[id]?.turnID = turn; tasks[id]?.phase = .working; tasks[id]?.requiresReconciliation = true
            activity(id, kind: "turnStarted", state: .working)
            refreshRequestPhase(id)
        case "turn/completed":
            guard let turn = p["turn"]["id"].string else { return }
            tasks[id]?.terminalTurns.insert(turn)
            guard tasks[id]?.turnID == turn || tasks[id]?.turnID == nil else { return }
            let status = p["turn"]["status"].string
            tasks[id]?.phase = status == "completed" ? .finished : status == "interrupted" ? .interrupted : .failed
            activity(id, kind: status == "interrupted" ? "interrupted" : "turnFinished", state: status == "completed" ? .finished : status == "interrupted" ? .interrupted : .unknown)
            tasks[id]?.turnID = nil; tasks[id]?.requiresReconciliation = false
            requests = requests.filter { !($0.value.threadID == id && $0.value.params["turnId"].string == turn && $0.value.isBlocking) }
            if tasks[id]?.steeringUncertain == true { tasks[id]?.phase = .disconnected; tasks[id]?.requiresReconciliation = true }
            if status != "completed" { queueAutoStart.remove(id) }
            scheduleNextQueued(id)
        case "thread/status/changed":
            if p["status"]["type"].string == "active", tasks[id]?.turnID != nil {
                let flags = p["status"]["activeFlags"].array.compactMap(\.string)
                tasks[id]?.phase = flags.contains("waitingOnApproval") ? .approval : flags.contains("waitingOnUserInput") ? .input : .working
                if requests.values.contains(where: { $0.threadID == id && $0.isBlocking }) { refreshRequestPhase(id) }
            }
        case "turn/plan/updated":
            guard let turn = p["turnId"].string, tasks[id]?.turnID == turn else { return }
            tasks[id]?.work.turnID = turn
            tasks[id]?.work.explanation = p["explanation"].string
            tasks[id]?.work.plan = p["plan"].array.enumerated().map { ExecutionPlanStep(id: $0.offset, text: $0.element["step"].string ?? "", status: $0.element["status"].string ?? "unknown") }
        case "turn/diff/updated":
            guard let turn = p["turnId"].string, tasks[id]?.turnID == turn, let diff = p["diff"].string else { return }
            tasks[id]?.work.turnID = turn
            tasks[id]?.work.diff = diff
        case "item/autoApprovalReview/started":
            tasks[id]?.reviewNotice = "Automatic approval review in progress"
        case "item/autoApprovalReview/completed":
            tasks[id]?.reviewNotice = "Automatic approval review: " + (p["review"]["status"].string ?? "completed") + ". " + (p["review"]["rationale"].string ?? "")
        case "autoApprovalReview/strictReviewRequired":
            tasks[id]?.reviewNotice = "Automatic approval review requires stricter review. No override has been requested."
        case "item/started", "item/completed":
            guard let itemID = p["item"]["id"].string else { return }
            let item = p["item"], type = item["type"].string ?? "", done = method == "item/completed"
            if done { tasks[id]?.toolProgress.removeValue(forKey: itemID) }
            if type == "reasoning" { return }
            let kind: String; let text: String
            if type == "agentMessage" || type == "plan" { kind = type == "plan" ? "Proposed plan" : "Assistant"; text = item["text"].string ?? "" }
            else if type == "userMessage" {
                let content = item["content"].array.compactMap { $0["text"].string ?? ($0["type"].string == "localImage" ? "Image: \($0["path"].string ?? "attachment")" : "[Image attachment]") }.joined(separator: "\n")
                for (index, part) in MessageContent.split(content, provider: .codex).enumerated() {
                    setEntry(id, itemID: itemID + ":\(index)", kind: part.context ? "System context" : "You", text: part.text, append: false, providerItemID: itemID)
                }
                return
            }
            else if type == "hookPrompt" { kind = "System context"; text = item.pretty }
            else {
                kind = "Tool activity"; text = (item["command"].string ?? type) + "\n\n```json\n" + item.pretty + "\n```"
                activity(id, kind: done ? (item["status"].string == "failed" ? "toolFailed" : "toolFinished") : "toolStarted", state: .working, call: itemID, tool: item["tool"].string ?? type, detail: item["command"].string)
            }
            setEntry(id, itemID: itemID, kind: kind, text: text, append: false,
                     image: TranscriptImage(itemType: type, path: item["path"].string), tool: ToolResult(item: item))
        case "item/agentMessage/delta", "item/plan/delta", "item/commandExecution/outputDelta":
            if let itemID = p["itemId"].string, let delta = p["delta"].string { setEntry(id, itemID: itemID, kind: method.contains("commandExecution") ? "Tool activity" : method == "item/plan/delta" ? "Proposed plan" : "Assistant", text: delta, append: true) }
        case "item/mcpToolCall/progress":
            if let itemID = p["itemId"].string { tasks[id]?.toolProgress[itemID] = p["message"].string ?? p["progress"].scalarText }
        case "error": tasks[id]?.error = p["error"]["message"].string ?? "Provider reported an error"
        default: break
        }
    }
    public func refreshAgents(_ session: Session) async {
        guard connected, session.provider == .codex, agentRefreshes.insert(session.sessionID).inserted else { return }
        defer { agentRefreshes.remove(session.sessionID) }
        var snapshot = activitySnapshot(provider: session.provider, id: session.sessionID)
        // Capability-check experimental discovery once. Results still require explicit parent metadata;
        // old servers may silently ignore unknown filters.
        if childFilterAvailable != false {
            do {
                var candidates: [WireValue] = [], cursor: String?, seen = Set<String>()
                for _ in 0..<5 {
                    var params: [String: WireValue] = ["ancestorThreadId": .string(session.sessionID), "sourceKinds": .array([.string("subAgentThreadSpawn")]), "limit": .number(100)]
                    if let cursor { params["cursor"] = .string(cursor) }
                    let result = try await transport.request("thread/list", .object(params))
                    candidates += result["data"].array
                    cursor = result["nextCursor"].string
                    guard let next = cursor, seen.insert(next).inserted else { break }
                    if Task.isCancelled { return }
                }
                childFilterAvailable = true
                func parent(_ child: WireValue) -> String? {
                    child["parentThreadId"].string ?? child["source"]["subAgent"]["thread_spawn"]["parent_thread_id"].string ?? child["source"]["subagent"]["thread_spawn"]["parent_thread_id"].string
                }
                // Resolve from explicit edges, even when pages arrive child-before-parent.
                // This also protects against servers silently ignoring an experimental filter.
                var known = Set([session.sessionID] + snapshot.agents.map(\.nativeID))
                var changed = true
                while changed {
                    changed = false
                    for child in candidates {
                        guard let parent = parent(child), known.contains(parent), let id = child["id"].string, known.insert(id).inserted else { continue }
                        changed = true
                        let item: WireValue = .object(["type": .string("collabToolCall"), "id": .string(id), "newThreadId": .string(id), "senderThreadId": .string(parent)])
                        SessionActivityReducer.ingest(.object(["method": .string("item/completed"), "params": .object(["item": item])]), provider: .codex, sessionID: session.sessionID, into: &snapshot)
                    }
                }
            } catch {
                // A timeout/disconnection is not proof that the experimental filter is unsupported.
                childFilterAvailable = error is ExecutionRPCRejection ? false : nil
            }
        }
        for agent in snapshot.agents.prefix(20) where agent.provider == Provider.codex.rawValue {
            do {
                let response = try await transport.request("thread/read", .object(["threadId": .string(agent.nativeID), "includeTurns": .bool(false)]))
                guard response["thread"]["id"].string == agent.nativeID else { continue }
                if let index = snapshot.records.firstIndex(where: { $0.id == agent.id }) {
                    var record = snapshot.records[index]
                    // Runtime idle/notLoaded is not an agent-completed assertion.
                    record.data = .object(record.data.object.merging(["runtimeStatus": response["thread"]["status"]]) { _, new in new })
                    record.observedAt = Date()
                    snapshot.apply(record)
                }
            } catch { /* Last reported state is retained; absent history is shown by child inspection. */ }
            if Task.isCancelled { return }
        }
        // Merge against live updates that arrived while awaiting reads; never replace newer streamed records.
        var latest = activitySnapshot(provider: session.provider, id: session.sessionID)
        for record in snapshot.records where !latest.records.contains(where: { $0.id == record.id && $0.observedAt > record.observedAt }) { latest.apply(record) }
        if tasks[session.sessionID] != nil { tasks[session.sessionID]?.structuredActivity = latest; saveActivity(session.sessionID) }
        else { recordedActivity[session.provider.rawValue + ":" + session.sessionID] = latest }
    }

    public func activitySnapshot(provider: Provider, id: String) -> SessionActivitySnapshot {
        if let task = tasks[id], task.provider == provider { return task.structuredActivity }
        return recordedActivity[provider.rawValue + ":" + id] ?? .init()
    }
    public func observeActivity(_ session: Session, snapshot: SessionActivitySnapshot) {
        guard tasks[session.sessionID]?.attached != true else { return }
        recordedActivity[session.provider.rawValue + ":" + session.sessionID] = snapshot
    }

    public func importActivity(_ session: Session, transcript: Transcript) async {
        let key = session.provider.rawValue + ":" + session.sessionID
        guard tasks[session.sessionID]?.attached != true else { return }
        var snapshot = activityDirectory.map { SessionActivityStore.read(directory: $0, provider: session.provider, id: session.sessionID) } ?? .init()
        if snapshot.records.isEmpty { snapshot = await SessionActivityHistory.read(session) }
        // App Server saved-history plans and collaboration items retain their native type.
        for entry in transcript.entries {
            var item = entry.tool?.item ?? .null
            if entry.kind == "Proposed plan" { item = .object(["id": .string(entry.providerItemID ?? entry.id), "type": .string("plan"), "text": .string(entry.text)]) }
            if item != .null {
                SessionActivityReducer.ingest(.object(["method": .string("item/completed"), "params": .object(["item": item])]), provider: session.provider, sessionID: session.sessionID, into: &snapshot)
            }
        }
        snapshot.lastKnown = true
        guard tasks[session.sessionID]?.attached != true else { return }
        if tasks[session.sessionID] != nil { tasks[session.sessionID]?.structuredActivity = snapshot }
        recordedActivity[key] = snapshot
        try? await activityStore?.save(snapshot, provider: session.provider, id: session.sessionID, members: activityMembership[key] ?? [])
    }

    private func saveActivity(_ id: String) {
        guard let activityStore else { return }
        activityWrites[id]?.cancel()
        activityWrites[id] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let task = self?.tasks[id] else { return }
            do { try await activityStore.save(task.structuredActivity, provider: task.provider, id: id, members: self?.activityMembership[task.provider.rawValue + ":" + id] ?? []) }
            catch { self?.tasks[id]?.error = "Could not save activity history: " + error.localizedDescription }
        }
    }

    private func refreshRequestPhase(_ id: String) {
        guard let task = tasks[id], task.turnID != nil, task.phase != .disconnected else { return }
        let pending = requests.values.filter { $0.threadID == id && $0.isBlocking }
        tasks[id]?.phase = pending.contains { !$0.isInput } ? .approval : pending.isEmpty ? .working : .input
    }
    private func setEntry(_ id: String, itemID: String, kind: String, text: String, append: Bool, image: TranscriptImage? = nil, tool: ToolResult? = nil, providerItemID: String? = nil) {
        guard var task = tasks[id] else { return }
        let key = (task.turnID ?? "turn") + ":" + itemID
        if let index = task.transcript.entries.firstIndex(where: { $0.id == key }) {
            let old = task.transcript.entries[index]
            var result = tool ?? old.tool
            if append, result?.type == "commandExecution", var payload = result?.item.object {
                payload["aggregatedOutput"] = .string(String(((result?.output ?? "") + text).prefix(256 * 1024)))
                result = ToolResult(item: .object(payload))
            }
            task.transcript.entries[index] = Entry(id: key, kind: kind, text: String((append ? old.text + text : text).prefix(256 * 1024)), timestamp: nil, image: append ? old.image : image, tool: result, turnID: task.turnID, providerItemID: providerItemID ?? itemID)
        } else { task.transcript.entries.append(Entry(id: key, kind: kind, text: String(text.prefix(256 * 1024)), timestamp: nil, image: image, tool: tool, turnID: task.turnID, providerItemID: providerItemID ?? itemID)) }
        if task.transcript.entries.count > 500 { task.transcript.entries.removeFirst(task.transcript.entries.count - 500); task.transcript.earlierContentOmitted = true }
        task.transcript.source = "Live agent · current turn (bounded preview)"
        tasks[id] = task
    }
}

public extension ExecutedTask {
    var session: Session {
        Session(id: provider.rawValue + ":" + id, provider: provider, url: nil, sessionID: id,
                title: title.isEmpty ? "New Codex task" : title, project: folder, modified: Date(), bytes: 0, archived: false,
                parentID: parentID, classification: parentID == nil ? .conversation : .subagent,
                classificationEvidence: parentID == nil ? "Created explicitly through Diorama" : "App Server explicit parentThreadId", historySource: "Diorama execution")
    }
}
