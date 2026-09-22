import Foundation
import Testing
@testable import DioramaCore

private actor DelayedGoalTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { _ in }
    private var reply: CheckedContinuation<WireValue, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func connect() {}
    func request(_ method: String, _ params: WireValue) async throws -> WireValue {
        if method == "thread/goal/get" {
            return await withCheckedContinuation { continuation in
                reply = continuation
                waiter?.resume(); waiter = nil
            }
        }
        return .object(["data": .array([])])
    }
    func waitUntilGoalRequest() async {
        if reply != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finishGoalRequest() {
        reply?.resume(returning: .object(["goal": .object(["status": .string("paused")])]))
        reply = nil
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}

@MainActor struct WorkflowReentrancyTests {
    @Test func goalRefreshPreservesTaskChangesReceivedWhileAwaitingReply() async throws {
        let transport = DelayedGoalTransport()
        let controller = ExecutionController(transport: transport)
        await controller.connect()
        controller.tasks["fixture"] = ExecutedTask(id: "fixture", title: "Fixture", folder: "/tmp", attached: true)
        let refresh = Task { await controller.loadWorkflow(id: "fixture") }
        await transport.waitUntilGoalRequest()
        controller.tasks["fixture"]?.phase = .working
        controller.tasks["fixture"]?.turnID = "new-turn"
        controller.tasks["fixture"]?.transcript.notice = "Received during goal refresh"
        controller.tasks["fixture"]?.structuredActivity.truncated = true
        await transport.finishGoalRequest()
        await refresh.value
        let task = try #require(controller.tasks["fixture"])
        #expect(task.workflow.goal["status"].string == "paused")
        #expect(task.phase == .working)
        #expect(task.turnID == "new-turn")
        #expect(task.transcript.notice == "Received during goal refresh")
        #expect(task.structuredActivity.truncated)
    }
    @Test func goalRefreshDoesNotRestoreTaskRemovedWhileAwaitingReply() async {
        let transport = DelayedGoalTransport()
        let controller = ExecutionController(transport: transport)
        await controller.connect()
        controller.tasks["fixture"] = ExecutedTask(id: "fixture", title: "Fixture", folder: "/tmp", attached: true)
        let refresh = Task { await controller.loadWorkflow(id: "fixture") }
        await transport.waitUntilGoalRequest()
        controller.tasks.removeValue(forKey: "fixture")
        await transport.finishGoalRequest()
        await refresh.value
        #expect(controller.tasks["fixture"] == nil)
    }

}
