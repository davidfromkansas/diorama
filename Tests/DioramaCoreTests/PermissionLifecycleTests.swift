import Foundation
import Testing
@testable import DioramaCore

private actor PermissionTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue>
    let sink: AsyncStream<WireValue>.Continuation
    var calls: [(String, WireValue)] = []
    var reviewer = "auto_review"
    var rejectMode = false
    var failMessage = false
    init() { (events, sink) = AsyncStream.makeStream() }
    func connect() {}
    func shutdown() {}
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func configure(reject: Bool = false, fail: Bool = false) { rejectMode = reject; failMessage = fail }
    func request(_ method: String, _ p: WireValue) throws -> WireValue {
        calls.append((method, p))
        switch method {
        case "diorama/connections": return .object(["codex": .bool(true)])
        case "model/list": return .object(["data": .array([])])
        case "thread/start", "thread/resume":
            if rejectMode { throw ExecutionRPCRejection("Managed policy rejects this mode") }
            reviewer = p["approvalsReviewer"].string ?? reviewer
            return .object(["thread": .object(["id": p["threadId"].string.map(WireValue.string) ?? .string("permission-test")]), "cwd": .string("/tmp"), "approvalsReviewer": .string(reviewer), "approvalPolicy": .string("on-request"), "sandbox": .object(["type": .string("workspaceWrite"), "networkAccess": .bool(true)])])
        case "diorama/permissions/set":
            if rejectMode { throw ExecutionRPCRejection("Auto unavailable") }
            return .object(["permissionMode": p["permissionMode"], "model": p["model"]])
        case "turn/start":
            if failMessage { throw ExecutionRPCRejection("Message rejected") }
            return .object(["turn": .object(["id": .string("turn")])])
        default: return .object([:])
        }
    }
}

@MainActor struct PermissionLifecycleTests {
    @Test func acceptedModePersistsBeforeFailedMessageAndPreservesBoundaries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = PermissionTransport(), journal = root.appendingPathComponent("tasks.json")
        let controller = ExecutionController(transport: stub, journal: journal)
        await controller.connect()
        let id = try await controller.prepare(folder: "/tmp", title: "Test", model: "")
        #expect(controller.tasks[id]?.permissionPreference == .autoReview)
        await stub.configure(fail: true)
        do { try await controller.send(id: id, prompt: "Fixture", approvalReview: .user); Issue.record("Expected message rejection") } catch {}
        #expect(controller.tasks[id]?.permissionPreference == .user)
        #expect(controller.tasks[id]?.sandbox["networkAccess"] == .bool(true))
        let params = await stub.calls.first { $0.0 == "thread/resume" }?.1
        #expect(params?["sandbox"] == .null)
        let restored = ExecutionController(transport: PermissionTransport(), journal: journal)
        #expect(restored.tasks[id]?.permissionPreference == .user)
        #expect(restored.tasks[id]?.attached == false)
    }
    @Test func rejectionNeverSubmitsOrChangesSavedChoice() async throws {
        let stub = PermissionTransport()
        let c = ExecutionController(transport: stub)
        await c.connect()
        let id = try await c.prepare(folder: "/tmp", title: "Test", model: "")
        await stub.configure(reject: true)
        do { try await c.send(id: id, prompt: "Fixture", approvalReview: .user); Issue.record("Expected rejection") } catch {}
        #expect(await stub.calls.filter { $0.0 == "turn/start" }.isEmpty)
        #expect(c.tasks[id]?.permissionPreference == .autoReview)
        #expect(c.tasks[id]?.permissionNotice != nil)
    }
    @Test func claudeRestoresExecutionPreferenceAfterPlanning() async throws {
        let stub = PermissionTransport()
        let controller = ExecutionController(transport: stub)
        await controller.connect()
        var task = ExecutedTask(id: "claude-test", provider: .claude, title: "Test", folder: "/tmp", attached: true)
        task.permissionPreference = .acceptEdits; task.approvalPolicy = .string("plan")
        controller.tasks[task.id] = task
        try await controller.preparePermissions(id: task.id, mode: "default")
        #expect(controller.tasks[task.id]?.approvalPolicy == .string("acceptEdits"))
        #expect(await stub.calls.last?.1["executionPermissionMode"] == .string("acceptEdits"))
        #expect(await stub.calls.last?.1["sandboxPolicy"] == .null)
        controller.tasks[task.id]?.permissionPreference = nil
        controller.tasks[task.id]?.approvalPolicy = .string("plan")
        do { try await controller.preparePermissions(id: task.id, mode: "default"); Issue.record("Imported Plan Mode guessed an execution preference") } catch {}
    }
    @Test func externalMismatchNeedsExplicitChoice() async throws {
        let c = ExecutionController(transport: PermissionTransport())
        var task = ExecutedTask(id: "test", title: "Test", folder: "/tmp", attached: true)
        task.permissionPreference = .autoReview; task.approvalReviewer = "user"
        task.approvalPolicy = .string("on-request"); task.sandbox = .object(["type": .string("workspaceWrite")])
        c.tasks[task.id] = task
        do { try await c.preparePermissions(id: task.id); Issue.record("Mismatch accepted") } catch {}
    }
    @Test func movedWorkspaceRequiresChoiceAndReplacedApprovalCannotBeAnswered() async throws {
        let c = ExecutionController(transport: PermissionTransport())
        await c.connect()
        var task = ExecutedTask(id: "test", title: "Test", folder: "/tmp/new", attached: true)
        task.permissionFolder = "/tmp/old"; task.permissionPreference = .autoReview
        c.tasks[task.id] = task
        do { try await c.preparePermissions(id: task.id); Issue.record("Old workspace permissions reused") } catch {}
        let old = ExecutionRequest(wireID: .string("reused"), method: "item/commandExecution/requestApproval", params: .object(["threadId": .string(task.id)]))
        let current = ExecutionRequest(wireID: .string("reused"), method: old.method, params: old.params)
        await c.receive(.object(["id": current.wireID, "method": .string(current.method), "params": current.params]))
        do { try await c.answer(id: old.id, result: .object(["decision": .string("accept")]), expectedInstance: old.instanceID); Issue.record("Stale approval accepted") } catch {}
        #expect(c.requests[current.id]?.responding == false)
    }
    @Test func managedPoliciesDisableRestrictedModes() {
        let c = ExecutionController(transport: PermissionTransport())
        c.permissionRequirements = .object(["allowedApprovalPolicies": .array([.string("on-request")]), "allowedSandboxModes": .array([.string("workspace-write")])])
        #expect(c.permissionUnavailable(.fullAccess, model: "fixture") != nil)
        #expect(c.permissionUnavailable(.autoReview, model: "fixture") == nil)
    }
    @Test func claudeCapabilitiesAndModesRemainDistinct() {
        let rows = ClaudeExecutionTransport.modelRows(.object(["models": .array([.object(["value": .string("fixture"), "supportsAutoMode": .bool(false)])])]))
        #expect(rows.first?["supportsAutoMode"] == .bool(false))
        #expect(ApprovalReviewChoice.claude("acceptEdits") == .acceptEdits)
        #expect(ApprovalReviewChoice.claude("dontAsk") == nil)
        #expect(ApprovalReviewChoice.autoReview.claudeMode == "auto")
    }
}
