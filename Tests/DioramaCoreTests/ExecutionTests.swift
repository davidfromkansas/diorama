import Foundation
import Testing
@testable import DioramaCore

private actor ExecutionStub: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue>
    let sink: AsyncStream<WireValue>.Continuation
    var calls: [String] = []
    var responses: [(WireValue, WireValue)] = []
    var serial = 0
    var failSubmission = false
    var steerError = ""
    var holdSteer = false
    var steerContinuation: CheckedContinuation<Void, Never>?
    var closed = false
    var terminalRunning = false
    var resumeFailure: String?
    var activeGoal = false
    var readActive = false
    var parameters: [String: WireValue] = [:]
    init() { (events, sink) = AsyncStream.makeStream() }
    func connect() {}
    func request(_ method: String, _ p: WireValue) async throws -> WireValue {
        calls.append(method); parameters[method] = p
        switch method {
        case "model/list":
            let model: WireValue = .object(["model": .string("fixture"), "displayName": .string("Fixture"), "isDefault": .bool(true), "defaultReasoningEffort": .string("low"), "supportedReasoningEfforts": .array([.object(["reasoningEffort": .string("low")])])])
            return .object(["data": .array([model])])
        case "thread/start":
            serial += 1
            return .object(["thread": .object(["id": .string("task-\(serial)")]), "cwd": p["cwd"], "model": .string("fixture"), "approvalsReviewer": .string("auto_review"), "approvalPolicy": .string("on-request"), "sandbox": .object(["type": .string("workspaceWrite")])])
        case "turn/start":
            if failSubmission { throw AppServerFailure("Submission timed out") }
            return .object(["turn": .object(["id": .string("turn-" + (p["threadId"].string ?? ""))])])
        case "turn/steer":
            if holdSteer { await withCheckedContinuation { steerContinuation = $0 } }
            if steerError == "rejected" { throw ExecutionRPCRejection("Turn has already completed") }
            if steerError == "timeout" { throw AppServerFailure("Response timed out") }
            return .object(["turnId": p["expectedTurnId"]])
        case "thread/read": return .object(["thread": .object(["id": p["threadId"], "cwd": .string("/tmp"), "turns": .array(readActive ? [.object(["status": .string("inProgress")])] : [])])])
        case "thread/turns/list": return .object(["data": .array(readActive ? [.object(["status": .string("inProgress")])] : [])])
        case "thread/goal/get": return .object(["goal": activeGoal ? .object(["status": .string("active")]) : .null])
        case "thread/resume":
            if let resumeFailure { throw AppServerFailure(resumeFailure) }
            return .object(["thread": .object(["id": p["threadId"], "status": .object(["type": .string("idle")])]), "model": .string("fixture"), "approvalsReviewer": p["approvalsReviewer"] == .null ? .string("auto_review") : p["approvalsReviewer"], "approvalPolicy": .string("on-request"), "sandbox": .object(["type": .string("workspaceWrite"), "networkAccess": .bool(false)])])
        case "thread/backgroundTerminals/list": return .object(["data": .array(terminalRunning ? [.object(["processId": .string("fixture-terminal")])] : [])])
        case "thread/backgroundTerminals/terminate": terminalRunning = false; return .object([:])
        default: return .object([:])
        }
    }
    func respond(id: WireValue, result: WireValue) { responses.append((id, result)) }
    func reject(id: WireValue, message: String) { responses.append((id, .object(["error": .string(message)]))) }
    func shutdown() { closed = true }
    func configureResume(failure: String? = nil, goal: Bool = false, active: Bool = false) { resumeFailure = failure; activeGoal = goal; readActive = active }
    func configureSteer(error: String = "", hold: Bool = false) { steerError = error; holdSteer = hold }
    func releaseSteer() { steerContinuation?.resume(); steerContinuation = nil }
    func startTerminal() { terminalRunning = true }
    func failNextSubmission() { failSubmission = true }
}

@MainActor struct ExecutionTests {
    @Test func steerIsTurnBoundAndDoesNotStartAnotherTurn() async throws {
        let (c, stub, id) = try await setup()
        try await c.send(id: id, prompt: "Start")
        #expect(c.canSteer(id: id))
        try await c.steer(id: id, expectedTurnID: "turn-" + id, prompt: "Correction")
        #expect(await stub.parameters["turn/steer"]?["expectedTurnId"] == .string("turn-" + id))
        #expect(await stub.parameters["turn/steer"]?["input"].array.first?["text"] == .string("Correction"))
        #expect(await stub.calls.filter { $0 == "turn/start" }.count == 1)
        await c.receive(completion(id, "turn-" + id))
        do { try await c.steer(id: id, expectedTurnID: "turn-" + id, prompt: "Stale"); Issue.record("Stale steer sent") } catch {}
        #expect(await stub.calls.filter { $0 == "turn/steer" }.count == 1)
    }
    @Test func completionBeforeSteerReplyDoesNotResurrectTurn() async throws {
        let (c, stub, id) = try await setup(); try await c.send(id: id, prompt: "Start")
        await stub.configureSteer(hold: true)
        let send = Task { try await c.steer(id: id, expectedTurnID: "turn-" + id, prompt: "Correction") }
        while await stub.steerContinuation == nil { await Task.yield() }
        #expect(!c.canSteer(id: id))
        await c.receive(completion(id, "turn-" + id))
        do { try await c.send(id: id, prompt: "Too early"); Issue.record("New turn started before correction acknowledgement") } catch {}
        await stub.releaseSteer(); try await send.value
        #expect(c.tasks[id]?.phase == .finished)
        #expect(c.tasks[id]?.turnID == nil)
    }
    @Test func rejectedSteerIsDistinctFromUncertainDelivery() async throws {
        let (c, stub, id) = try await setup(); try await c.send(id: id, prompt: "Start")
        await stub.configureSteer(error: "rejected")
        do { try await c.steer(id: id, expectedTurnID: "turn-" + id, prompt: "Correction"); Issue.record("Expected rejection") } catch {}
        #expect(c.tasks[id]?.steeringUncertain == false)
        await stub.configureSteer(error: "timeout")
        do { try await c.steer(id: id, expectedTurnID: "turn-" + id, prompt: "Correction"); Issue.record("Expected timeout") } catch {}
        await c.receive(completion(id, "turn-" + id))
        #expect(c.tasks[id]?.phase == .disconnected)
        #expect(c.tasks[id]?.requiresReconciliation == true)
        do { try await c.send(id: id, prompt: "Do not retry"); Issue.record("Uncertain correction retried") } catch {}
        #expect(await stub.calls.filter { $0 == "turn/start" }.count == 1)
    }
    @Test func plansAndDiffsStayWithTheirTurnAndDoNotInventCompletion() async throws {
        let (c, _, id) = try await setup(); try await c.send(id: id, prompt: "Start")
        let other = try await c.prepare(folder: "/tmp", title: "Other", model: "fixture")
        let turn = "turn-" + id
        let step: WireValue = .object(["step": .string("Verify"), "status": .string("inProgress")])
        await c.receive(notification("turn/plan/updated", ["threadId": .string(id), "turnId": .string(turn), "plan": .array([step])]))
        let diff = "diff --git a/A.swift b/A.swift\n--- a/A.swift\n+++ b/A.swift\n@@ -1 +1 @@\n-old\n+new"
        await c.receive(notification("turn/diff/updated", ["threadId": .string(id), "turnId": .string(turn), "diff": .string(diff)]))
        await c.receive(notification("turn/diff/updated", ["threadId": .string(id), "turnId": .string("wrong-turn"), "diff": .string("wrong")]))
        #expect(c.tasks[id]?.work.files.first?.path == "A.swift")
        #expect(c.tasks[id]?.work.files.first?.additions == 1)
        #expect(c.tasks[other]?.work.diff.isEmpty == true)
        await c.receive(completion(id, turn))
        await c.receive(notification("turn/plan/updated", ["threadId": .string(id), "turnId": .string(turn), "plan": .array([])]))
        #expect(c.tasks[id]?.work.plan.first?.status == "inProgress")
        #expect(c.tasks[id]?.work.diff == diff)
        try await c.send(id: id, prompt: "Next")
        #expect(c.tasks[id]?.work.plan.isEmpty == true)
        #expect(c.tasks[id]?.work.diff.isEmpty == true)
    }
    @Test func optionalQuestionsContinueAndBlockingRequestsResolveIndependently() async throws {
        let (c, stub, id) = try await setup(); try await c.send(id: id, prompt: "Start")
        func question(_ key: String, blocking: Bool) -> WireValue {
            .object(["id": .string(key), "method": .string("item/tool/requestUserInput"), "params": .object(["threadId": .string(id), "turnId": .string("turn-" + id), "isBlocking": .bool(blocking), "questions": .array([.object(["id": .string("choice"), "question": .string("Which?")])])])])
        }
        await c.receive(question("optional", blocking: false))
        #expect(c.tasks[id]?.phase == .working)
        #expect(c.canSteer(id: id))
        await c.receive(question("required", blocking: true))
        #expect(c.tasks[id]?.phase == .input)
        #expect(!c.canSteer(id: id))
        await c.receive(notification("serverRequest/resolved", ["threadId": .string("wrong"), "requestId": .string("required")]))
        #expect(c.requests.count == 2)
        await c.receive(notification("serverRequest/resolved", ["threadId": .string(id), "requestId": .string("required")]))
        #expect(c.tasks[id]?.phase == .working)
        await c.receive(completion(id, "turn-" + id))
        #expect(c.requests[WireValue.string("optional").key] != nil)
        try await c.answer(id: WireValue.string("optional").key, result: .object(["answers": .object(["choice": .object(["answers": .array([.string("A")])])])]))
        #expect(await stub.responses.last?.0 == .string("optional"))
    }
    @Test func structuredApprovalCannotBroadenOfferedRule() async throws {
        let (c, stub, id) = try await setup(); try await c.send(id: id, prompt: "Start")
        let offered: WireValue = .object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": .array([.string("git"), .string("status")])])])
        await c.receive(.object(["id": .string("approval"), "method": .string("item/commandExecution/requestApproval"), "params": .object(["threadId": .string(id), "turnId": .string("turn-" + id), "availableDecisions": .array([offered, .string("cancel")])])]))
        let key = WireValue.string("approval").key
        let broader: WireValue = .object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": .array([.string("git")])])])
        do { try await c.answer(id: key, result: .object(["decision": broader])); Issue.record("Broader rule accepted") } catch {}
        #expect(await stub.responses.isEmpty)
        try await c.answer(id: key, result: .object(["decision": offered]))
        #expect(await stub.responses.last?.1["decision"] == offered)
    }
    @Test func connectorFormWithoutTurnIsActionableWithoutPausingTask() async throws {
        let (c, stub, id) = try await setup()
        await c.receive(.object(["id": .string("form"), "method": .string("mcpServer/elicitation/request"), "params": .object(["threadId": .string(id), "turnId": .null, "mode": .string("form"), "serverName": .string("fixture"), "requestedSchema": .object(["type": .string("object"), "properties": .object(["count": .object(["type": .string("integer"), "minimum": .number(1)])]), "required": .array([.string("count")])])])]))
        #expect(c.tasks[id]?.phase == .ready)
        #expect(await stub.responses.isEmpty)
        let key = WireValue.string("form").key
        do { try await c.answer(id: key, result: .object(["action": .string("accept"), "content": .object(["count": .number(0.5)])])); Issue.record("Invalid form accepted") } catch {}
        try await c.answer(id: key, result: .object(["action": .string("accept"), "content": .object(["count": .number(2)])]))
        #expect(await stub.responses.last?.1["content"]["count"] == .number(2))
    }
    @Test func sendingDoesNotDependOnCanvasStorage() async throws {
        let root = try ConversationCanvasTests().directory()
        let stub = ExecutionStub()
        let controller = ExecutionController(transport: stub)
        await controller.connect()
        let id = try await controller.prepare(folder: root.path, title: "Task", model: "fixture")
        try FileManager.default.removeItem(at: root)
        try await controller.send(id: id, prompt: "Continue")
        #expect(await stub.parameters["turn/start"]?["input"].array.count == 1)
    }
    @Test func ordinaryTurnsSendOnlyUserInputWithoutCreatingCanvas() async throws {
        let root = try ConversationCanvasTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = ExecutionStub()
        let controller = ExecutionController(transport: stub)
        await controller.connect()
        let id = try await controller.prepare(folder: root.path, title: "Canvas task", model: "fixture")
        for prompt in ["First request", "Next request"] {
            try await controller.send(id: id, prompt: prompt)
            let input = await stub.parameters["turn/start"]?["input"].array ?? []
            #expect(input.first?["text"].string == prompt)
            #expect(input.count == 1)
            #expect(!input.contains { $0["text"].string?.contains("<diorama_html_view>") == true })
            await controller.receive(completion(id, "turn-" + id))
        }
        let url = try ConversationCanvas().location(folder: root.path, provider: .codex, sessionID: id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func liveImageViewUpdatesOneEntryAndRetainsPreview() async throws {
        let (controller, _, id) = try await setup()
        for method in ["item/started", "item/completed"] {
            await controller.receive(notification(method, ["threadId": .string(id), "item": .object([
                "id": .string("image"), "type": .string("imageView"), "path": .string("/tmp/preview.png")
            ])]))
        }
        let entries = try #require(controller.tasks[id]?.transcript.entries)
        #expect(entries.count == 1)
        #expect(entries.first?.image?.url.path == "/tmp/preview.png")
        #expect(entries.first?.text.contains("imageView") == true)
    }
    func notification(_ method: String, _ params: [String: WireValue]) -> WireValue { .object(["method": .string(method), "params": .object(params)]) }
    func completion(_ id: String, _ turn: String, status: String = "completed") -> WireValue {
        notification("turn/completed", ["threadId": .string(id), "turn": .object(["id": .string(turn), "status": .string(status)])])
    }
    private func setup() async throws -> (ExecutionController, ExecutionStub, String) {
        let stub = ExecutionStub(); let controller = ExecutionController(transport: stub)
        await controller.connect()
        let id = try await controller.prepare(folder: "/tmp", title: "Fixture task", model: "fixture")
        return (controller, stub, id)
    }
    private func imported(_ id: String = "imported", archived: Bool = false) -> Session {
        var session = Session(id: "Codex:" + id, provider: .codex, url: nil, sessionID: id, title: "Existing conversation", project: "/tmp", modified: Date(), bytes: 0, archived: archived, parentID: nil)
        session.classification = .conversation
        return session
    }
    @Test func importedResumePreservesIdentityAndWaitsForExplicitSend() async throws {
        let stub = ExecutionStub()
        let controller = ExecutionController(transport: stub)
        let session = imported()
        try await controller.resumeImported(session)
        #expect(controller.tasks[session.sessionID]?.attached == true)
        #expect(await stub.calls.filter { $0 == "thread/resume" }.count == 1)
        #expect(await stub.parameters["thread/resume"]?["threadId"].string == session.sessionID)
        #expect(await stub.calls.contains("turn/start") == false)
        #expect(await stub.parameters["thread/read"]?["includeTurns"] == .bool(false))
        #expect(await stub.parameters["thread/resume"]?["excludeTurns"] == .bool(true))
        #expect(await stub.parameters["thread/turns/list"]?["limit"] == .number(1))
        #expect(await stub.parameters["thread/turns/list"]?["itemsView"] == .string("notLoaded"))
        try await controller.send(id: session.sessionID, prompt: "Explicit new message")
        #expect(await stub.parameters["turn/start"]?["threadId"].string == session.sessionID)
    }
    @Test func sendAcquiresConversationAndSubmitsExactlyOnce() async throws {
        let stub = ExecutionStub(); let c = ExecutionController(transport: stub)
        try await c.send(in: imported(), prompt: "My draft")
        let calls = await stub.calls
        #expect(calls.firstIndex(of: "thread/resume")! < calls.firstIndex(of: "turn/start")!)
        #expect(calls.filter { $0 == "turn/start" }.count == 1)
        #expect(await stub.parameters["turn/start"]?["input"].array.first?["text"].string == "My draft")
    }
    @Test func writerRetrySendsOnlyAfterSuccessfulAcquisition() async throws {
        let stub = ExecutionStub(); let c = ExecutionController(transport: stub)
        await stub.configureResume(failure: "already has an active writer")
        do { try await c.send(in: imported(), prompt: "Preserved draft"); Issue.record("Expected conflict") } catch {}
        #expect(await stub.calls.contains("turn/start") == false)
        await stub.configureResume()
        try await c.send(in: imported(), prompt: "Preserved draft")
        #expect(await stub.calls.filter { $0 == "turn/start" }.count == 1)
    }
    @Test func attachmentOnlyRetryPreservesOfficialInput() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let attachments = [try ConversationAttachment(url: url)]
        let stub = ExecutionStub(); let c = ExecutionController(transport: stub)
        await stub.configureResume(failure: "already has an active writer")
        do { try await c.send(in: imported(), prompt: "", attachments: attachments); Issue.record("Expected conflict") } catch {}
        #expect(await stub.calls.contains("turn/start") == false)
        await stub.configureResume()
        try await c.send(in: imported(), prompt: "", attachments: attachments)
        let sent = await stub.parameters["turn/start"]
        #expect(sent?["input"].array.first?["text"].string?.contains(url.lastPathComponent) == true)
        #expect(await stub.calls.filter { $0 == "turn/start" }.count == 1)
    }
    @Test func codingTurnsApplyExplicitWorkspacePermissionBeforePrompt() async throws {
        let (controller, stub, id) = try await setup()
        controller.tasks[id]?.sandbox = .object(["type": .string("readOnly")])
        try await controller.send(id: id, prompt: "Implement", approvalReview: .autoReview)
        let prepared = await stub.parameters["thread/resume"]
        #expect(prepared?["sandbox"] == .string("workspace-write"))
        #expect(prepared?["approvalsReviewer"] == .string("auto_review"))
        #expect(await stub.parameters["turn/start"]?["sandboxPolicy"] == .null)
        #expect(controller.tasks[id]?.sandbox["type"] == .string("workspaceWrite"))
    }
    @Test func inheritsProviderReviewAndOnlyOverridesOnExplicitSend() async throws {
        let stub = ExecutionStub(); let c = ExecutionController(transport: stub)
        await c.connect()
        let id = try await c.prepare(folder: "/tmp", title: "Defaults", model: "")
        #expect(await stub.parameters["thread/start"]?["approvalsReviewer"] == .string("auto_review"))
        #expect(c.tasks[id]?.approvalReviewer == "auto_review")
        try await c.send(id: id, prompt: "Keep settings")
        #expect(await stub.parameters["turn/start"]?["approvalsReviewer"] == .null)
        try await c.resumeImported(imported())
        #expect(await stub.parameters["thread/resume"]?["approvalsReviewer"] == .null)
        #expect(c.tasks["imported"]?.approvalReviewer == "auto_review")
        try await c.send(id: "imported", prompt: "Manual review", approvalReview: .user)
        #expect(await stub.parameters["thread/resume"]?["approvalsReviewer"].string == "user")
        #expect(await stub.parameters["thread/resume"]?["sandbox"] == .null)
        #expect(await stub.parameters["thread/resume"]?["approvalPolicy"].string == "on-request")
        #expect(c.tasks["imported"]?.approvalReviewer == "user")
        let other = try await c.prepare(folder: "/tmp", title: "Auto", model: "")
        try await c.send(id: other, prompt: "Auto review", approvalReview: .autoReview)
        #expect(await stub.parameters["thread/resume"]?["approvalsReviewer"].string == "auto_review")
        #expect(c.tasks[id]?.approvalReviewer == "auto_review")
    }
    @Test func uncertainSendCannotBeAutomaticallyResumedAndResent() async throws {
        let stub = ExecutionStub(); let c = ExecutionController(transport: stub)
        await stub.failNextSubmission()
        do { try await c.send(in: imported(), prompt: "One attempt"); Issue.record("Expected timeout") } catch {}
        do { try await c.send(in: imported(), prompt: "One attempt"); Issue.record("Must reconcile") } catch {}
        #expect(await stub.calls.filter { $0 == "turn/start" }.count == 1)
        #expect(await stub.calls.filter { $0 == "thread/resume" }.count == 1)
    }
    @Test func writerConflictLeavesImportsReadableAndAllowsExplicitRetry() async throws {
        let stub = ExecutionStub()
        let c = ExecutionController(transport: stub)
        await stub.configureResume(failure: "thread imported already has an active writer")
        do { try await c.resumeImported(imported()); Issue.record("Writer conflict ignored") } catch {}
        #expect(c.tasks["imported"] == nil)
        #expect(c.resumeErrors["imported"]?.contains("in use by another Codex client") == true)
        #expect(c.resuming.isEmpty)
        await stub.configureResume()
        try await c.resumeImported(imported())
        #expect(c.resumeErrors["imported"] == nil)
        #expect(c.tasks["imported"]?.attached == true)
        #expect(await stub.calls.contains("turn/start") == false)
    }
    @Test func importedResumeRejectsReviewsArchivesAndAutomaticWork() async throws {
        let stub = ExecutionStub(), c = ExecutionController(transport: stub)
        var session = imported(archived: true)
        do { try await c.resumeImported(session); Issue.record("Archived import resumed") } catch {}
        session = imported(); session.classification = .internalReview
        do { try await c.resumeImported(session); Issue.record("Review resumed") } catch {}
        await stub.configureResume(goal: true)
        do { try await c.resumeImported(imported()); Issue.record("Active goal resumed") } catch {}
        await stub.configureResume(active: true)
        do { try await c.resumeImported(imported()); Issue.record("Active turn resumed") } catch {}
        #expect(await stub.calls.contains("thread/resume") == false)
        #expect(await stub.calls.contains("turn/start") == false)
    }
    @Test func idleTaskWithTerminalRequiresConfirmationAndConfirmedTermination() async throws {
        let (c, stub, _) = try await setup()
        await stub.startTerminal()
        #expect(try await c.requiresQuitConfirmation())
        try await c.stopAndShutdown()
        #expect(await stub.calls.contains("thread/backgroundTerminals/terminate"))
        #expect(await stub.terminalRunning == false)
        #expect(await stub.closed)
    }
    @Test func modelCatalogPreparationAndDuplicateSubmission() async throws {
        let (c, stub, id) = try await setup()
        #expect(c.models.first?.efforts == ["low"])
        #expect(c.tasks[id]?.settings.contains("on-request") == true)
        #expect(await stub.calls.contains("turn/start") == false)
        try await c.send(id: id, prompt: "Hello", model: "fixture", effort: "low")
        do { try await c.send(id: id, prompt: "Duplicate"); Issue.record("Duplicate accepted") } catch {}
        #expect(await stub.calls.filter { $0 == "turn/start" }.count == 1)
        await c.receive(completion(id, "turn-" + id))
        #expect(c.tasks[id]?.phase == .finished)
        #expect(!c.hasActiveWork)
        do { try await c.send(id: id, prompt: "Invalid effort", effort: "ultra"); Issue.record("Unsupported effort accepted") } catch {}
    }
    @Test func streamingFinalReplacementAndLateEvents() async throws {
        let (c, _, id) = try await setup(); try await c.send(id: id, prompt: "Stream")
        let p: [String: WireValue] = ["threadId": .string(id), "turnId": .string("turn-" + id), "itemId": .string("answer"), "delta": .string("partial")]
        await c.receive(notification("item/agentMessage/delta", p))
        #expect(c.tasks[id]?.transcript.entries.last?.text == "partial")
        await c.receive(notification("item/completed", ["threadId": .string(id), "turnId": .string("turn-" + id), "item": .object(["id": .string("answer"), "type": .string("agentMessage"), "text": .string("**Final**")])]))
        #expect(c.tasks[id]?.transcript.entries.count == 1)
        #expect(c.tasks[id]?.transcript.entries.last?.text == "**Final**")
        await c.receive(completion(id, "turn-" + id))
        await c.receive(notification("item/agentMessage/delta", p))
        #expect(c.tasks[id]?.transcript.entries.last?.text == "**Final**")
        #expect(c.tasks[id]?.phase == .finished)
    }
    @Test func approvalRequiresExplicitAvailableDecisionAndResolution() async throws {
        let (c, stub, id) = try await setup(); try await c.send(id: id, prompt: "Approve")
        let wireID = WireValue.number(42)
        let request: WireValue = .object(["id": wireID, "method": .string("item/commandExecution/requestApproval"), "params": .object(["threadId": .string(id), "turnId": .string("turn-" + id), "itemId": .string("call"), "availableDecisions": .array([.string("decline"), .string("cancel")])])])
        await c.receive(request)
        #expect(await stub.responses.isEmpty)
        #expect(c.tasks[id]?.phase == .approval)
        do { try await c.answer(id: wireID.key, result: .object(["decision": .string("accept")])); Issue.record("Unavailable decision accepted") } catch {}
        try await c.answer(id: wireID.key, result: .object(["decision": .string("decline")]))
        #expect(c.requests[wireID.key]?.responding == true)
        await c.receive(notification("serverRequest/resolved", ["threadId": .string(id), "requestId": wireID]))
        #expect(c.requests.isEmpty)
        do { try await c.answer(id: wireID.key, result: .object(["decision": .string("cancel")])); Issue.record("Resolved response accepted") } catch {}
    }
    @Test func questionsAndUnsupportedToolsNeverExecuteClientCode() async throws {
        let (c, stub, id) = try await setup(); try await c.send(id: id, prompt: "Ask")
        let question: WireValue = .object(["id": .string("q"), "method": .string("item/tool/requestUserInput"), "params": .object(["threadId": .string(id), "turnId": .string("turn-" + id), "questions": .array([.object(["id": .string("choice"), "question": .string("Which?")])])])])
        await c.receive(question)
        do { try await c.answer(id: WireValue.string("q").key, result: .object(["answers": .object([:])])); Issue.record("Empty answer accepted") } catch {}
        try await c.answer(id: WireValue.string("q").key, result: .object(["answers": .object(["choice": .object(["answers": .array([.string("Alpha")])])])]))
        await c.receive(.object(["id": .string("tool"), "method": .string("item/tool/call"), "params": .object(["threadId": .string(id), "tool": .string("arbitrary-client-code")])]))
        #expect(await stub.responses.last?.1["success"] == .bool(false))
    }
    @Test func importedHandoffBlockedAndAmbiguousSubmissionNotRetried() async throws {
        let (c, stub, id) = try await setup()
        do { try await c.reconnectOwned(id: "imported-id"); Issue.record("Imported task acquired") } catch {}
        #expect(await stub.calls.contains("thread/resume") == false)
        await stub.failNextSubmission()
        do { try await c.send(id: id, prompt: "Uncertain"); Issue.record("Expected failure") } catch {}
        #expect(c.tasks[id]?.phase == .disconnected)
        do { try await c.send(id: id, prompt: "Retry"); Issue.record("Blind retry accepted") } catch {}
        #expect(await stub.calls.filter { $0 == "turn/start" }.count == 1)
        do { try await c.stopAndShutdown(); Issue.record("Unconfirmed shutdown accepted") } catch {}
        #expect(await stub.closed == false)
    }
    @Test func simultaneousTasksAndWorkerRemainIndependent() async throws {
        let (c, _, first) = try await setup()
        let second = try await c.prepare(folder: "/tmp", title: "Second", model: "fixture")
        try await c.send(id: first, prompt: "One"); try await c.send(id: second, prompt: "Two")
        await c.receive(notification("thread/started", ["thread": .object(["id": .string("worker"), "parentThreadId": .string(first), "cwd": .string("/tmp")])]))
        await c.receive(notification("turn/started", ["threadId": .string("worker"), "turn": .object(["id": .string("worker-turn")])]))
        await c.receive(completion(first, "turn-" + first))
        #expect(c.tasks[second]?.phase == .working)
        #expect(c.tasks["worker"]?.phase == .working)
        #expect(c.hasActiveWork)
    }
    @Test func shutdownWaitsForCompletionAndJournalNeverRestarts() async throws {
        let fixture = SessionLibraryTests(); let root = try fixture.directory(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("owned.json"), stub = ExecutionStub()
        let c = ExecutionController(transport: stub, journal: journal)
        await c.connect(); let id = try await c.prepare(folder: "/tmp", title: "Resume later", model: "fixture")
        try await c.send(id: id, prompt: "Do not save this prompt in ownership journal")
        let stopping = Task { try await c.stopAndShutdown() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await stub.closed == false)
        await c.receive(completion(id, "turn-" + id, status: "interrupted"))
        try await stopping.value
        #expect(await stub.closed)
        let saved = try String(contentsOf: journal, encoding: .utf8)
        #expect(!saved.contains("Do not save"))
        let fresh = ExecutionController(transport: ExecutionStub(), journal: journal)
        #expect(fresh.tasks[id]?.attached == false)
        #expect(fresh.tasks[id]?.phase == .disconnected)
        #expect(!fresh.connected)
    }
}

extension ExecutionTests {
    @Test func projectContextUsesOfficialThreadInstructionsAndKeepsMessageClean() async throws {
        let stub = ExecutionStub(); let controller = ExecutionController(transport: stub)
        await controller.connect()
        let context = "Use the Project instructions and selected references."
        let id = try await controller.prepare(folder: "/tmp", title: "Project task", model: "fixture", projectContext: context)
        #expect(await stub.parameters["thread/start"]?["developerInstructions"] == .string(context))
        #expect(await stub.parameters["thread/start"]?["cwd"] == .string("/tmp"))
        #expect(await stub.calls.contains("turn/start") == false)
        try await controller.send(id: id, prompt: "Hello")
        #expect(await stub.parameters["turn/start"]?["input"].array.first?["text"] == .string("Hello"))
    }
}
