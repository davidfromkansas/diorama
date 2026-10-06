import Foundation
import Testing
@testable import DioramaCore

actor SwitchTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue>
    var calls: [(String, WireValue)] = []
    var rejectCreation = false
    var count = 0
    var queues: [String: [WireValue]] = [:]
    init() { let (stream, _) = AsyncStream<WireValue>.makeStream(); events = stream }
    func connect() {}
    func request(_ method: String, _ p: WireValue) async throws -> WireValue {
        calls.append((method,p))
        switch method {
        case "model/list": return .object(["data": .array([.object(["model": .string("openai-fixture")]), .object(["model": .string("claude/fixture")])])])
        case "thread/start":
            if rejectCreation { throw ExecutionRPCRejection("Not logged in") }
            count += 1
            return .object(["thread": .object(["id": .string("target-\(count)")]), "cwd": p["cwd"], "model": p["model"]])
        case "thread/goal/get": return .object(["goal": .object(["objective": .string("Finish the task"), "status": .string("paused")])])
        case "thread/goal/set": return .object(["goal": .object(["objective": p["objective"], "status": p["status"]])])
        case "thread/queue/list": return .object(["data": .array(queues[p["threadId"].string ?? ""] ?? [])])
        case "thread/queue/add":
            let id = p["threadId"].string ?? ""
            let row: WireValue = .object(["id": .string("q-" + p["clientUserMessageId"].scalarText), "clientUserMessageId": p["clientUserMessageId"], "input": p["input"]])
            queues[id, default: []].append(row); return .object(["queuedSubmission": row])
        case "thread/queue/delete":
            queues[p["threadId"].string ?? ""]?.removeAll { $0["id"] == p["queuedSubmissionId"] }
            return .object(["deleted": .bool(true)])
        default: return .object([:])
        }
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
    func failCreation() { rejectCreation = true }
}
@MainActor struct ProviderSwitchTests {
    func setup(_ transport: SwitchTransport) async -> ExecutionController {
        let controller = ExecutionController(transport: transport)
        await controller.connect()
        var task = ExecutedTask(id: "source", title: "Task", folder: "/tmp", attached: true)
        task.phase = .finished; task.model = "openai-fixture"
        controller.tasks[task.id] = task
        return controller
    }
    @Test func preservesFolderAndNeverStartsWorkDuringPreparation() async throws {
        let transport = SwitchTransport(); let controller = await setup(transport)
        let session = try #require(controller.tasks["source"]?.session)
        let id = try await controller.prepareProviderSwitch(session: session, model: "claude/fixture", handoff: "Context")
        #expect(controller.tasks[id]?.folder == session.project)
        #expect(controller.tasks[id]?.workflow.goal["status"].string == "paused")
        let calls = await transport.calls
        #expect(!calls.contains { ["turn/start", "thread/queue/start", "thread/fork"].contains($0.0) })
        #expect(calls.first { $0.0 == "thread/start" }?.1["developerInstructions"].string == AgentInstructions.compose("Context"))
        controller.retireProviderSession("source")
        await #expect(throws: (any Error).self) { try await controller.resumeImported(session) }
    }
    @Test func activeTurnAndUnavailableProviderDoNotSwitch() async throws {
        let transport = SwitchTransport(); let controller = await setup(transport)
        let session = try #require(controller.tasks["source"]?.session)
        controller.tasks["source"]?.phase = .working
        await #expect(throws: (any Error).self) { try await controller.prepareProviderSwitch(session: session, model: "claude/fixture", handoff: "Context") }
        #expect(await transport.count == 0)
        controller.tasks["source"]?.phase = .finished; await transport.failCreation()
        await #expect(throws: (any Error).self) { try await controller.prepareProviderSwitch(session: session, model: "claude/fixture", handoff: "Context") }
        #expect(!controller.retiredProviderSessions.contains("source"))
        #expect(controller.tasks["source"]?.attached == true)
    }
    @Test func carriedQueueReconcilesWithoutAutostart() async throws {
        let transport = SwitchTransport(); let controller = await setup(transport)
        let item = CarriedSubmission(sourceID: "old", row: .object(["id": .string("q-old"), "input": .array([.object(["type": .string("text"), "text": .string("Do next")])])]))
        let first = try await controller.importCarriedSubmission(id: "source", submission: item)
        let second = try await controller.importCarriedSubmission(id: "source", submission: item)
        #expect(first == second)
        let calls = await transport.calls
        #expect(calls.filter { $0.0 == "thread/queue/add" }.count == 1)
        #expect(!calls.contains { $0.0 == "thread/queue/start" })
    }
    @Test func conversationIdentityAndHistoryRoundTrip() throws {
        let original = ExecutedTask(id: "source", title: "Task", folder: "/tmp", attached: true).session
        var record = DioramaConversation(session: original, model: "openai-fixture")
        record.segments[0].history = [Entry(id: "message", kind: "You", text: "Keep the files", timestamp: nil)]
        record.segments.append(ConversationSegment(nativeID: "claude", provider: .claude, model: "claude/fixture", handoff: "Existing work"))
        record.segments[1].history = [Entry(id: "message", kind: "Assistant", text: "Changed a file", timestamp: nil)]
        record.segments.append(ConversationSegment(nativeID: "openai-again", provider: .codex, model: "openai-fixture", handoff: "Updated work"))
        let native = ExecutedTask(id: "openai-again", title: "Another", folder: "/tmp", attached: true).session
        #expect(record.session(using: native).id == original.id)
        #expect(record.session(using: native).title == original.title)
        #expect(Set(record.precedingEntries().map(\.id)).count == 4)
        #expect(record.precedingEntries().contains { $0.text == "Changed a file" })
        #expect(try JSONDecoder().decode(DioramaConversation.self, from: JSONEncoder().encode(record)) == record)
    }
}
