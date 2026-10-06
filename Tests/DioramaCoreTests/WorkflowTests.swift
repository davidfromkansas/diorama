import Foundation
import Testing
@testable import DioramaCore

private actor WorkflowStub: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue>
    var calls: [(String, WireValue)] = []
    var queue: [WireValue] = []
    var counter = 0
    var failQueue = false
    var steerFailure = 0
    var deleteFailure = false
    var failApps = false
    var holdSkills = false
    var heldSkill: CheckedContinuation<Void, Never>?
    var skillWaiter: CheckedContinuation<Void, Never>?
    var catalogPages = false
    init() { let (stream, _) = AsyncStream<WireValue>.makeStream(); events = stream }
    func connect() {}
    func request(_ method: String, _ p: WireValue) async throws -> WireValue {
        calls.append((method, p))
        if method == "skills/list", holdSkills {
            holdSkills = false
            await withCheckedContinuation { continuation in
                heldSkill = continuation; skillWaiter?.resume(); skillWaiter = nil
            }
        }
        switch method {
        case "model/list": return .object(["data": .array([.object(["model": .string("fixture"), "displayName": .string("Fixture"), "supportedReasoningEfforts": .array([])])])])
        case "thread/start": return .object(["thread": .object(["id": .string("test")]), "model": .string("fixture"), "cwd": .string("/tmp"), "approvalsReviewer": .string("auto_review"), "approvalPolicy": .string("on-request"), "sandbox": .object(["type": .string("workspaceWrite")])])
        case "thread/turns/list": return .object(["data": .array([])])
        case "thread/read": return .object(["thread": .object(["id": p["threadId"], "cwd": .string("/tmp"), "turns": .array([])])])
        case "thread/resume": return .object(["thread": .object(["id": p["threadId"], "status": .object(["type": .string("idle")])]), "model": .string("fixture"), "cwd": .string("/tmp"), "approvalsReviewer": .string("auto_review"), "approvalPolicy": .string("on-request"), "sandbox": .object(["type": .string("workspaceWrite")])])
        case "thread/goal/get": return .object(["goal": .null])
        case "thread/goal/set": return .object(["goal": .object(["objective": p["objective"].string == nil ? .string("Goal") : p["objective"], "status": p["status"], "tokensUsed": .number(0)])])
        case "thread/goal/clear": return .object(["cleared": .bool(true)])
        case "collaborationMode/list": return .object(["data": .array([.object(["name": .string("Plan"), "mode": .string("plan")]), .object(["name": .string("Default"), "mode": .string("default")])])])
        case "turn/start", "thread/queue/start", "review/start":
            counter += 1
            if method == "thread/queue/start" { queue.removeAll { $0["id"] == p["queuedSubmissionId"] } }
            return .object(["turn": .object(["id": .string("turn-\(counter)")]), "reviewThreadId": .string("test")])
        case "thread/queue/list": return .object(["data": .array(queue)])
        case "thread/queue/add":
            if failQueue { throw AppServerFailure("timeout") }
            let row: WireValue = .object(["id": .string(UUID().uuidString), "clientUserMessageId": p["clientUserMessageId"], "input": p["input"]]); queue.append(row)
            return .object(["queuedSubmission": row])
        case "turn/steer":
            if steerFailure == 1 { throw ExecutionRPCRejection("stale turn") }
            if steerFailure == 2 { throw AppServerFailure("timeout") }
            return .object(["turnId": p["expectedTurnId"]])
        case "thread/queue/delete":
            if deleteFailure { throw AppServerFailure("timeout") }
            queue.removeAll { $0["id"] == p["queuedSubmissionId"] }; return .object(["deleted": .bool(true)])
        case "thread/fork": return .object(["thread": .object(["id": .string("fork")]), "model": .string("fixture"), "cwd": p["cwd"].string == nil ? .string("/tmp") : p["cwd"]])
        case "skills/list": return .object(["data": .array([.object(["skills": .array([.object(["name": .string("audit"), "path": .string("/tmp/SKILL.md"), "enabled": .bool(true)])])])])])
        case "app/installed": return .object(["apps": .array([.object(["id": .string("installed"), "runtimeName": .string("Installed connector"), "enabled": .bool(true), "callable": .bool(true)])])])
        case "app/list":
            if catalogPages {
                let second = p["cursor"].string != nil
                return .object(["data": .array([.object(["id": .string(second ? "second" : "installed"), "name": .string("Directory name"), "isAccessible": .bool(true)])]), "nextCursor": second ? .null : .string("page-2")])
            }
            if failApps { throw AppServerFailure("Catalog timed out") }
            return .object(["data": .array([.object(["id": .string("connector"), "name": .string("Connector"), "isAccessible": .bool(true), "isEnabled": .bool(true)])])])
        case "mcpServerStatus/list": return .object(["data": .array([.object(["name": .string("fixture"), "authStatus": .string("notLoggedIn")])])])
        case "mcpServer/oauth/login": return .object(["authorizationUrl": .string("https://example.com/oauth")])
        case "thread/search", "thread/searchOccurrences": return .object(["data": .array([.object(["snippet": .string("match"), "turnId": .string("found"), "itemId": .string("item")])]), "nextCursor": .string("next-page")])
        case "thread/items/list": return .object(["data": .array([.object(["turnId": .string("found"), "item": .object(["id": .string("item"), "type": .string("agentMessage"), "text": .string("Found content")])])])])
        default: return .object([:])
        }
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
    func holdNextSkills() { holdSkills = true }
    func waitForHeldSkills() async {
        if heldSkill != nil { return }
        await withCheckedContinuation { skillWaiter = $0 }
    }
    func releaseSkills() { heldSkill?.resume(); heldSkill = nil }
    func useCatalogPages() { catalogPages = true }
    func setAppFailure() { failApps = true }
    func setSteerFailure(_ value: Int) { steerFailure = value }
    func setDeleteFailure() { deleteFailure = true }
    func setQueueFailure() { failQueue = true }
    func params(_ method: String) -> WireValue? { calls.last { $0.0 == method }?.1 }
    func count(_ method: String) -> Int { calls.filter { $0.0 == method }.count }
}

@MainActor struct WorkflowTests {
    private func setup() async throws -> (ExecutionController, WorkflowStub) {
        let stub = WorkflowStub(); let c = ExecutionController(transport: stub)
        await c.connect(); _ = try await c.prepare(folder: "/tmp", title: "Fixture", model: "fixture")
        return (c, stub)
    }
    private func event(_ method: String, _ p: [String: WireValue]) -> WireValue { .object(["method": .string(method), "params": .object(p)]) }
    @Test func explicitGoalRecoveryPausesBeforeResumeAndDoesNotSend() async throws {
        let (c, stub) = try await setup(); let session = try #require(c.tasks["test"]?.session)
        c.tasks.removeValue(forKey: "test")
        try await c.pauseGoalAndResume(session: session)
        let calls = await stub.calls.map { $0.0 }
        let pause = try #require(calls.firstIndex(of: "thread/goal/set"))
        let resume = try #require(calls.firstIndex(of: "thread/resume"))
        #expect(pause < resume)
        #expect(await stub.params("thread/goal/set")?["status"] == .string("paused"))
        #expect(await stub.count("turn/start") == 0)
    }
    @Test func pickerReusesRecentResultsAndRefreshBypassesCache() async throws {
        let (c, stub) = try await setup()
        await c.loadIntegrations(folder: "/tmp", threadID: "test")
        await c.loadIntegrations(folder: "/tmp", threadID: "test")
        #expect(await stub.count("skills/list") == 1)
        #expect(await stub.count("app/list") == 0)
        #expect(await stub.params("skills/list")?["forceReload"] == .bool(false))
        await c.loadIntegrations(folder: "/tmp", threadID: "test", forceRefresh: true)
        #expect(await stub.count("skills/list") == 2)
        #expect(await stub.params("skills/list")?["forceReload"] == .bool(true))
        c.integrationsLoadedAt = .distantPast
        await c.loadIntegrations(folder: "/tmp", threadID: "test")
        #expect(await stub.count("skills/list") == 3)
    }
    @Test func slowSkillsDoNotBlockOtherSectionsOrDuplicateOpening() async throws {
        let (c, stub) = try await setup(); await stub.holdNextSkills()
        let loading = Task { await c.loadIntegrations(folder: "/tmp", threadID: "test") }
        await stub.waitForHeldSkills()
        for _ in 0..<1000 {
            if !c.apps.isEmpty && !c.connectors.isEmpty { break }
            await Task.yield()
        }
        #expect(c.apps.count == 1 && c.connectors.count == 1)
        #expect(c.skills.isEmpty && c.integrationsLoading)
        await c.loadIntegrations(folder: "/tmp", threadID: "test")
        #expect(await stub.count("skills/list") == 1)
        await stub.releaseSkills(); await loading.value
        #expect(!c.integrationsLoading && c.skills.count == 1)
    }
    @Test func lateContextResultsCannotReplaceNewContext() async throws {
        let (c, stub) = try await setup(); await stub.holdNextSkills()
        let old = Task { await c.loadIntegrations(folder: "/old", threadID: "test") }
        await stub.waitForHeldSkills()
        await c.loadIntegrations(folder: "/new", threadID: nil)
        c.skills = [.object(["name": .string("new context marker")])]
        await stub.releaseSkills(); await old.value
        #expect(c.skills.first?["name"] == .string("new context marker"))
        #expect(c.integrationContext == ["/new", ""])
        #expect(!c.integrationsLoading)
    }
    @Test func directoryLoadsOnePageAtATimeAndMergesInstalledApps() async throws {
        let (c, stub) = try await setup(); await stub.useCatalogPages()
        await c.loadIntegrations(folder: "/tmp", threadID: "test")
        await c.loadMoreApps(threadID: "test")
        #expect(await stub.count("app/list") == 1)
        #expect(c.apps.count == 1 && c.apps.first?["name"] == .string("Directory name"))
        #expect(c.appDirectoryCursor == "page-2")
        await c.loadMoreApps(threadID: "test")
        #expect(c.apps.count == 2 && c.appDirectoryCursor == nil)
        await c.loadMoreApps(threadID: "test")
        #expect(await stub.count("app/list") == 2)
    }
    @Test func installedAppsRemainUsableWhenFullCatalogFails() async throws {
        let (c, stub) = try await setup(); await stub.setAppFailure()
        await c.loadIntegrations(folder: "/tmp", threadID: "test")
        #expect(c.apps.first?["id"] == .string("installed"))
        #expect(await stub.count("app/list") == 0)
        await c.loadMoreApps(threadID: "test")
        #expect(c.featureErrors["app/list"]?.contains("showing installed") == true)
        try await c.send(id: "test", prompt: "Use connector", capabilities: [.init(name: "Installed connector", path: "app://installed", kind: "mention")])
        #expect(await stub.params("turn/start")?["input"].array.last?["type"] == .string("mention"))
    }
    @Test func stoppingPausesAnActiveGoalBeforeInterruptingTurn() async throws {
        let (c, stub) = try await setup()
        try await c.setGoal(id: "test", objective: "Goal", status: "active")
        try await c.send(id: "test", prompt: "Work")
        try await c.interrupt(id: "test")
        #expect(c.tasks["test"]?.workflow.goal["status"] == .string("paused"))
        let calls = await stub.calls.map { $0.0 }
        #expect(calls.last == "turn/interrupt")
        #expect(calls.dropLast().last == "thread/goal/set")
    }
    @Test func commandOutputDeltasUpdateTheRichCard() async throws {
        let (c, _) = try await setup(); try await c.send(id: "test", prompt: "Run")
        await c.receive(event("item/started", ["threadId": .string("test"), "turnId": .string("turn-1"), "item": .object(["id": .string("command"), "type": .string("commandExecution"), "command": .string("test"), "aggregatedOutput": .string("")])]))
        await c.receive(event("item/commandExecution/outputDelta", ["threadId": .string("test"), "turnId": .string("turn-1"), "itemId": .string("command"), "delta": .string("first output")]))
        #expect(c.tasks["test"]?.transcript.entries.last?.tool?.output == "first output")
    }
    @Test func goalAndUsageEventsRemainDistinctFromTurnCompletion() async throws {
        let (c, stub) = try await setup()
        try await c.setGoal(id: "test", objective: "Test", status: "active", tokenBudget: 1000)
        #expect(await stub.params("thread/goal/set")?["tokenBudget"] == .number(1000))
        #expect(c.hasActiveWork)
        await c.receive(event("thread/tokenUsage/updated", ["threadId": .string("test"), "turnId": .string("t"), "tokenUsage": .object(["last": .object(["totalTokens": .number(25)])])]))
        await c.receive(event("account/rateLimits/updated", ["rateLimits": .object(["primary": .object(["usedPercent": .number(10)])])]))
        #expect(c.tasks["test"]?.workflow.usage["last"]["totalTokens"] == .number(25))
        #expect(c.rateLimits["rateLimits"]["primary"]["usedPercent"] == .number(10))
        try await c.setGoal(id: "test", status: "paused")
        try await c.clearGoal(id: "test")
        #expect(c.tasks["test"]?.workflow.goal == .null)
        #expect(await stub.count("turn/start") == 0)
    }
    @Test func planModeUsesAdvertisedModeAndTypedCapabilities() async throws {
        let (c, stub) = try await setup()
        do { try await c.send(id: "test", prompt: "Plan", mode: "plan"); Issue.record("Unadvertised mode accepted") } catch {}
        await c.loadModes(); await c.loadIntegrations(folder: "/tmp", threadID: "test"); await c.loadMoreApps(threadID: "test")
        try await c.send(id: "test", prompt: "Plan", mode: "plan", capabilities: [.init(name: "audit", path: "/tmp/SKILL.md", kind: "skill"), .init(name: "Connector", path: "app://connector", kind: "mention")])
        let p = try #require(await stub.params("turn/start"))
        #expect(p["collaborationMode"]["mode"] == .string("plan"))
        #expect(p["collaborationMode"]["settings"]["model"] == .string("fixture"))
        #expect(p["input"].array.map { $0["type"].string } == ["text", "skill", "mention"])
        #expect(p["approvalPolicy"] == .null)
    }
    @Test func invalidCapabilitiesCannotBeSpoofedAndOpeningPickerDoesNotLogin() async throws {
        let (c, stub) = try await setup(); await c.loadIntegrations(folder: "/tmp", threadID: "test")
        #expect(await stub.count("mcpServer/oauth/login") == 0)
        do { try await c.send(id: "test", prompt: "Use", capabilities: [.init(name: "fake", path: "/other", kind: "skill")]); Issue.record("Unknown skill accepted") } catch {}
        #expect(try await c.connectorLogin(name: "fixture", threadID: "test").scheme == "https")
    }
    @Test func forkDefersGoalContinuationAndDoesNotStartATurn() async throws {
        let (c, stub) = try await setup(); let session = try #require(c.tasks["test"]?.session)
        let id = try await c.fork(session: session, through: "earlier-turn", folder: "/tmp/isolated-fork", projectContext: "New Project context")
        #expect(id == "fork")
        #expect(await stub.params("thread/fork")?["cwd"] == .string("/tmp/isolated-fork"))
        #expect(await stub.params("thread/fork")?["developerInstructions"] == AgentInstructions.compose("New Project context").map(WireValue.string))
        #expect(await stub.params("thread/fork")?["deferGoalContinuation"] == .bool(true))
        #expect(await stub.params("thread/fork")?["lastTurnId"] == .string("earlier-turn"))
        #expect(await stub.count("turn/start") == 0)
        #expect(c.tasks[id]?.phase == .ready)
    }
    @Test func reviewScopesAreExplicitAndBlockDuplicateTurns() async throws {
        let (c, stub) = try await setup(); try await c.review(id: "test", baseBranch: "main")
        #expect(await stub.params("review/start")?["target"]["branch"] == .string("main"))
        #expect(c.tasks["test"]?.phase == .working)
        do { try await c.review(id: "test"); Issue.record("Concurrent review accepted") } catch {}
        #expect(await stub.count("review/start") == 1)
    }
    @Test func queueRunsOnlyAfterSuccessfulCompletionAndDoesNotSteer() async throws {
        let (c, stub) = try await setup(); try await c.send(id: "test", prompt: "First")
        try await c.enqueue(id: "test", prompt: "Second")
        #expect(await stub.count("thread/queue/start") == 0)
        #expect(await stub.count("turn/steer") == 0)
        await c.receive(event("turn/completed", ["threadId": .string("test"), "turn": .object(["id": .string("turn-1"), "status": .string("completed")])]))
        for _ in 0..<1000 { if await stub.count("thread/queue/start") == 1 { break }; await Task.yield() }
        #expect(await stub.count("thread/queue/start") == 1)
        #expect(await stub.count("turn/start") == 1)
    }
    @Test func interruptedTurnsDoNotDrainQueueAndUncertainAddsCannotRepeat() async throws {
        let (c, stub) = try await setup(); try await c.send(id: "test", prompt: "First"); try await c.enqueue(id: "test", prompt: "Second")
        await c.receive(event("turn/completed", ["threadId": .string("test"), "turn": .object(["id": .string("turn-1"), "status": .string("interrupted")])]))
        #expect(!c.queueAutoStart.contains("test"))
        #expect(await stub.count("thread/queue/start") == 0)
        await stub.setQueueFailure()
        do { try await c.enqueue(id: "test", prompt: "Uncertain"); Issue.record("Expected timeout") } catch {}
        do { try await c.enqueue(id: "test", prompt: "Retry"); Issue.record("Blind retry accepted") } catch {}
        #expect(await stub.count("thread/queue/add") == 2)
    }
    @Test func queuedSteeringAcknowledgesBeforeDeletingAndPreservesInput() async throws {
        let (c, stub) = try await setup()
        try await c.send(id: "test", prompt: "First")
        try await c.enqueue(id: "test", prompt: "Correct course")
        let row = try #require(c.tasks["test"]?.workflow.queue.first)
        try await c.steerQueued(id: "test", submissionID: row["id"].string!)
        #expect(await stub.params("turn/steer")?["input"] == row["input"])
        #expect(await stub.params("turn/steer")?["expectedTurnId"] == .string("turn-1"))
        let methods = await stub.calls.map { $0.0 }
        #expect(methods.firstIndex(of: "turn/steer")! < methods.firstIndex(of: "thread/queue/delete")!)
        #expect(c.tasks["test"]?.workflow.queue.isEmpty == true)
    }
    @Test func uncertainSteeringAndRemovalNeverAutoStartQueuedCopy() async throws {
        for failure in [1, 2, 3] {
            let (c, stub) = try await setup()
            try await c.send(id: "test", prompt: "First")
            try await c.enqueue(id: "test", prompt: "Correction")
            let row = try #require(c.tasks["test"]?.workflow.queue.first)
            if failure == 3 { await stub.setDeleteFailure() } else { await stub.setSteerFailure(failure) }
            do { try await c.steerQueued(id: "test", submissionID: row["id"].string!); Issue.record("Expected failure") } catch {}
            #expect(!c.queueAutoStart.contains("test"))
            #expect(c.tasks["test"]?.workflow.queue.count == 1)
            if failure != 1 {
                #expect(c.tasks["test"]?.workflow.queueUncertain == true)
                do { try await c.acknowledgeQueueInspection(id: "test"); Issue.record("Uncertain steering cleared") } catch {}
            }
            #expect(await stub.count("thread/queue/start") == 0)
        }
    }
    @Test func pendingQueueSteeringSurvivesAppRestart() async throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("queue-recovery-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let c = ExecutionController(transport: WorkflowStub(), journal: file)
        await c.connect(); _ = try await c.prepare(folder: "/tmp", title: "Recovery", model: "fixture")
        c.tasks["test"]?.workflow.steeredQueueIDs = ["queued-uncertain"]
        c.persist()
        let restored = ExecutionController(transport: WorkflowStub(), journal: file)
        #expect(restored.tasks["test"]?.workflow.queueUncertain == true)
        #expect(restored.tasks["test"]?.workflow.steeredQueueIDs == ["queued-uncertain"])
        #expect(restored.queueAutoStart.isEmpty)
        try await restored.resumeImported(try #require(restored.tasks["test"]?.session))
        #expect(restored.tasks["test"]?.workflow.queueUncertain == true)
        #expect(restored.tasks["test"]?.workflow.steeredQueueIDs == ["queued-uncertain"])
    }
    @Test func goalSendHasOneTurnAndPlanCannotActivateGoal() async throws {
        let (c, stub) = try await setup(); await c.loadModes()
        do { try await c.sendWithGoal(id: "test", prompt: "Goal", mode: "plan", goal: true); Issue.record("Conflicting modes accepted") } catch {}
        #expect(await stub.count("turn/start") == 0)
        try await c.sendWithGoal(id: "test", prompt: "Goal", goal: true)
        #expect(await stub.count("turn/start") == 1)
        #expect(c.tasks["test"]?.workflow.goal["status"] == .string("active"))
        let methods = await stub.calls.map { $0.0 }
        #expect(methods.firstIndex(of: "thread/goal/set")! < methods.firstIndex(of: "turn/start")!)
        #expect(methods.lastIndex(of: "thread/goal/set")! > methods.firstIndex(of: "turn/start")!)
    }
    @Test func searchUsesCorrectQueryScopeAndFetchesTheMatchingTurn() async throws {
        let (c, stub) = try await setup()
        let page = try await c.searchMessages(query: "needle", threadID: nil, archived: true)
        #expect(page.nextCursor == "next-page")
        #expect(await stub.params("thread/search")?["archived"] == .bool(true))
        _ = try await c.searchMessages(query: "needle", threadID: "test", cursor: "next-page")
        #expect(await stub.params("thread/searchOccurrences")?["cursor"] == .string("next-page"))
        let transcript = try await c.searchTurn(threadID: "test", turnID: "found")
        #expect(transcript.entries.first?.text == "Found content")
        #expect(transcript.entries.first?.turnID == "found")
        #expect(await stub.count("thread/resume") == 0)
    }
    @Test func renameAndArchiveUseOfficialMethodsWithoutPinMetadata() async throws {
        let (c, stub) = try await setup(); let session = try #require(c.tasks["test"]?.session)
        try await c.rename(session: session, name: "Renamed")
        #expect(c.tasks["test"]?.title == "Renamed")
        try await c.setArchived(session: session, archived: true)
        #expect(await stub.count("thread/archive") == 1)
        #expect(await stub.count("thread/metadata/update") == 0)
    }
    @Test func richResultsRetainStructuredMetadataAndExcludeReasoning() {
        let result = ToolResult(item: .object(["type": .string("commandExecution"), "command": .string("swift test"), "aggregatedOutput": .string("passed"), "exitCode": .number(0)]))
        #expect(result?.output == "passed")
        #expect(result?.item["exitCode"] == .number(0))
        #expect(ToolResult(item: .object(["type": .string("reasoning")])) == nil)
    }
}
