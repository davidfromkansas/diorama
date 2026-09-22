import Foundation
import Testing
@testable import DioramaCore

struct SessionActivityTests {
    private func wire(_ json: String) throws -> WireValue { try JSONDecoder().decode(WireValue.self, from: Data(json.utf8)) }
    private func claude(_ json: String, into state: inout SessionActivitySnapshot) throws {
        SessionActivityReducer.ingest(.object(["method": .string("diorama/claudeActivity"), "params": .object(["event": try wire(json), "turnId": .string("turn")])]), provider: .claude, sessionID: "parent", into: &state)
    }
    @Test func claudeTasksAgentsAndDeduplication() throws {
        var state = SessionActivitySnapshot()
        try claude(#"{"type":"user","uuid":"one","tool_use_result":{"task":{"id":"1","subject":"Review"}}}"#, into: &state)
        try claude(#"{"type":"user","uuid":"two","tool_use_result":{"taskId":"1","statusChange":{"to":"completed"}}}"#, into: &state)
        try claude(#"{"type":"user","uuid":"two","tool_use_result":{"taskId":"1","statusChange":{"to":"completed"}}}"#, into: &state)
        #expect(state.steps.first?.title == "Review"); #expect(state.steps.first?.status == "completed"); #expect(state.events.count == 2)
        try claude(#"{"type":"system","subtype":"task_started","task_id":"child","task_type":"local_agent","description":"Inspect file","tool_use_id":"call","prompt":"Read fixture"}"#, into: &state)
        try claude(#"{"type":"system","subtype":"task_notification","task_id":"child","status":"completed","usage":{"total_tokens":42}}"#, into: &state)
        #expect(state.agents.count == 1); #expect(state.agents[0].kind == "agent")
        #expect(state.agents[0].title == "Inspect file"); #expect(state.agents[0].status == "completed")
        #expect(state.agents[0].data["delegationID"].string == "call")
        try claude(#"{"type":"system","subtype":"task_started","task_id":"shell","task_type":"local_bash","description":"Build"}"#, into: &state)
        #expect(state.agents.last?.kind == "job")
    }
    @Test func proposalsRemainDistinctFromExecutionAndFinalReplacesDraft() throws {
        var state = SessionActivitySnapshot()
        for json in [#"{"method":"item/plan/delta","params":{"itemId":"plan","delta":"Draft"}}"#,
                     #"{"method":"item/completed","params":{"item":{"id":"plan","type":"plan","text":"Final proposal"}}}"#] {
            SessionActivityReducer.ingest(try wire(json), provider: .codex, sessionID: "same", into: &state)
        }
        #expect(state.plans.count == 1); #expect(state.plans[0].detail == "Final proposal"); #expect(state.steps.isEmpty)
        try claude(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"plan","name":"ExitPlanMode","input":{"plan":"Claude plan"}}]}}"#, into: &state)
        #expect(state.plans.count == 2)
        #expect(Set(state.plans.map(\.id)).count == 2)
    }
    @Test func revisedChecklistAndTurnCompletionDoNotInventCompletion() throws {
        var state = SessionActivitySnapshot()
        for json in [#"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[{"step":"A","status":"inProgress"},{"step":"B","status":"pending"}]}}"#,
                     #"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[{"step":"Different","status":"pending"}]}}"#,
                     #"{"method":"turn/completed","params":{"turn":{"id":"t","status":"completed"}}}"#] {
            SessionActivityReducer.ingest(try wire(json), provider: .codex, sessionID: "s", into: &state)
        }
        #expect(state.steps.count == 1); #expect(state.steps[0].status == "pending")
        #expect(state.events.filter { $0.kind == "checklist" }.count == 2)
        SessionActivityReducer.ingest(try wire(#"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[]}}"#), provider: .codex, sessionID: "s", into: &state)
        #expect(state.steps.isEmpty)
    }
    @Test func reasoningAndUnknownEventsAreNotExposed() throws {
        var state = SessionActivitySnapshot()
        try claude(#"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"private"}]}}"#, into: &state)
        try claude(#"{"type":"system","subtype":"thinking_tokens","estimated_tokens":99}"#, into: &state)
        #expect(state.events.isEmpty)
    }
    @Test func journalRestoresLastKnownAndKeepsBaselineWhenTruncated() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = SessionActivitySnapshot()
        try claude(#"{"type":"user","tool_use_result":{"task":{"id":"1","subject":"A"}}}"#, into: &state)
        try claude(#"{"type":"user","tool_use_result":{"taskId":"1","statusChange":{"to":"completed"}}}"#, into: &state)
        state.bound(eventLimit: 1)
        #expect(state.events.count == 1); #expect(state.truncated); #expect(state.steps[0].status == "completed")
        try await SessionActivityStore(directory: directory).save(state, provider: .claude, id: "s")
        let restored = SessionActivityStore.read(directory: directory, provider: .claude, id: "s")
        #expect(restored.lastKnown); #expect(restored.steps[0].status == "completed")
        #expect(SessionActivityStore.read(directory: directory, provider: .codex, id: "s").records.isEmpty)
        try Data("broken".utf8).write(to: SessionActivityStore.file(directory: directory, provider: .claude, id: "s"))
        #expect(SessionActivityStore.read(directory: directory, provider: .claude, id: "s").records.isEmpty)
    }
}

@MainActor struct ActivityInspectionTests {
    actor ReadOnlyTransport: ExecutionTransport {
        nonisolated let events: AsyncStream<WireValue> = AsyncStream { $0.finish() }
        var methods: [String] = []
        func connect() {}
        func shutdown() {}
        func request(_ method: String, _ params: WireValue) throws -> WireValue {
            methods.append(method)
            if method == "thread/list" {
                return .object(["data": .array([
                    .object(["id": .string("grandchild"), "source": .object(["subagent": .object(["thread_spawn": .object(["parent_thread_id": .string("child")])])])]),
                    .object(["id": .string("unrelated"), "parentThreadId": .string("other-root")]),
                    .object(["id": .string("child"), "parentThreadId": .string("root")])
                ])])
            }
            if method == "thread/read" { return .object(["thread": .object(["id": params["threadId"], "turns": .array([])])]) }
            throw AppServerFailure("Unavailable")
        }
        func respond(id: WireValue, result: WireValue) {}
        func reject(id: WireValue, message: String) {}
    }
    @Test func descendantDiscoveryUsesExplicitEdgesAndExcludesUnrelatedTasks() async {
        let transport = ReadOnlyTransport(), controller = ExecutionController(transport: ReadOnlyTransport())
        let c = ExecutionController(transport: transport)
        await c.connect()
        let session = Session(id: "root", provider: .codex, url: nil, sessionID: "root", title: "Root", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        await c.refreshAgents(session)
        let agents = c.activitySnapshot(provider: .codex, id: "root").agents
        #expect(Set(agents.map(\.nativeID)) == ["child", "grandchild"])
        #expect(agents.first { $0.nativeID == "grandchild" }?.parentID == "child")
        #expect(await transport.methods.allSatisfy { ["model/list", "thread/list", "thread/read"].contains($0) })
        #expect(controller.tasks.isEmpty)
    }
    @Test func turnOnlyPlansRouteToTheUniqueTaskAndNeverGuess() async throws {
        let controller = ExecutionController(transport: ReadOnlyTransport())
        var first = ExecutedTask(id: "one", title: "One", folder: "/tmp")
        first.turnID = "turn"
        controller.tasks["one"] = first
        let event = try JSONDecoder().decode(WireValue.self, from: Data(#"{"method":"turn/plan/updated","params":{"turnId":"turn","plan":[{"step":"Inspect","status":"pending"}]}}"#.utf8))
        await controller.receive(event)
        #expect(controller.tasks["one"]?.structuredActivity.steps.count == 1)
        var second = ExecutedTask(id: "two", title: "Two", folder: "/tmp")
        second.turnID = "turn"; controller.tasks["two"] = second
        await controller.receive(event)
        #expect(controller.tasks["two"]?.structuredActivity.steps.isEmpty == true)
    }
    @Test func childInspectionNeverResumesOrExecutes() async throws {
        let transport = ReadOnlyTransport(), c = ExecutionController(transport: ReadOnlyTransport())
        let controller = ExecutionController(transport: transport)
        _ = try await controller.inspectChild(provider: .codex, parentID: "p", childID: "c", folder: "/tmp")
        #expect(await transport.methods == ["thread/read"])
        #expect(controller.tasks.isEmpty); #expect(c.tasks.isEmpty)
    }
}

struct ConversationActivityBudgetTests {
    private func sample(_ provider: Provider, _ id: String) throws -> SessionActivitySnapshot {
        var state = SessionActivitySnapshot()
        let json = #"{"method":"turn/plan/updated","params":{"turnId":"t","plan":[{"step":"Inspect","status":"pending"}]}}"#
        SessionActivityReducer.ingest(try JSONDecoder().decode(WireValue.self, from: Data(json.utf8)), provider: provider, sessionID: id, into: &state)
        return state
    }
    @Test func sharedCountAndByteBudgetPreservesProviderBaselines() throws {
        var values = [try sample(.codex, "same"), try sample(.claude, "same")]
        ConversationActivityBudget.bound(&values, eventLimit: 1)
        #expect(values.reduce(0) { $0 + $1.events.count } == 1)
        #expect(values.allSatisfy { !$0.steps.isEmpty })
        #expect(values.contains { $0.truncated })
        #expect(values[0].steps[0].id != values[1].steps[0].id)
        ConversationActivityBudget.bound(&values, byteLimit: 1000)
        let bytes = try values.reduce(0) { try $0 + JSONEncoder().encode($1).count }
        #expect(bytes <= 1000)
    }
    @Test func storeEnforcesConversationBudgetAcrossRestartAndProviders() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let members = [ActivitySessionIdentity(provider: .codex, id: "same"), ActivitySessionIdentity(provider: .claude, id: "same")]
        var first = try sample(.codex, "same"), second = try sample(.claude, "same")
        let a = first.events[0], b = second.events[0]
        first.events = (0..<6000).map { var r = a; r.id = "a\($0)"; return r }
        second.events = (0..<6000).map { var r = b; r.id = "b\($0)"; return r }
        try await SessionActivityStore(directory: directory).save(first, provider: .codex, id: "same", members: members)
        // A new actor simulates restart; membership is supplied by persisted conversation records.
        try await SessionActivityStore(directory: directory).save(second, provider: .claude, id: "same", members: members)
        let restored = members.map { SessionActivityStore.read(directory: directory, provider: $0.provider, id: $0.id) }
        #expect(restored.reduce(0) { $0 + $1.events.count } <= 10_000)
        #expect(restored.allSatisfy { $0.lastKnown && !$0.steps.isEmpty })
        #expect(restored.contains { $0.truncated })
    }
}
