import Foundation
import Testing
@testable import DioramaCore

@MainActor
struct ClaudeExecutionTests {
    @Test func subscriptionGateDoesNotTreatLoggedInAsSubscription() {
        #expect(!ClaudeExecutionTransport.usesSubscription(.object([:])))
        #expect(!ClaudeExecutionTransport.usesSubscription(.object(["account": .object(["apiKeySource": .string("/login managed key"), "tokenSource": .string("none")])])))
        #expect(!ClaudeExecutionTransport.usesSubscription(.object(["account": .object(["apiKeySource": .string("environment"), "tokenSource": .string("user")])])))
        #expect(ClaudeExecutionTransport.usesSubscription(.object(["account": .object(["apiKeySource": .string("none"), "tokenSource": .string("user")])])))
    }
    @Test func currentSubscriptionCatalogIsRecognizedWithoutTokenSource() {
        let account: WireValue = .object(["subscriptionType": .string("Claude Max"), "apiProvider": .string("firstParty")])
        #expect(ClaudeExecutionTransport.usesSubscription(.object(["account": account])))
        #expect(!ClaudeExecutionTransport.usesSubscription(.object(["account": .object(["subscriptionType": .string("Claude Max"), "apiProvider": .string("firstParty"), "apiKeySource": .string("environment")])])))
        #expect(!ClaudeExecutionTransport.usesSubscription(.object(["account": .object(["subscriptionType": .string("unknown"), "apiProvider": .string("firstParty")])])))
    }
    @Test func unsupportedEffortIsNotAdvertised() {
        let rows = ClaudeExecutionTransport.modelRows(.object(["models": .array([.object(["value": .string("sonnet"), "displayName": .string("Sonnet"), "supportedEffortLevels": .array([.string("high")])])])]))
        #expect(rows.first?["model"] == .string("claude/sonnet"))
        #expect(rows.first?["supportedReasoningEfforts"].array.isEmpty == true)
    }
    @Test func rejectsUnknownAttachmentInsteadOfSendingItAsText() throws {
        #expect(throws: ExecutionRPCRejection.self) { try ClaudeExecutionTransport.input([.object(["type": .string("mention"), "path": .string("app://private")])]) }
    }
    @Test func processStreamsApprovalsStopAndContinues() async throws {
        let fixture = try makeFixture(api: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let transport = ClaudeExecutionTransport(folder: fixture.path, executable: fixture.appendingPathComponent("claude"))
        let controller = ExecutionController(transport: transport)
        await controller.connect()
        #expect(controller.connected)
        let id = try await controller.prepare(folder: fixture.path, title: "Fixture", model: "claude/haiku")
        #expect(controller.tasks[id]?.provider == .claude)
        try await controller.send(id: id, prompt: "hello", model: "claude/haiku")
        try await wait { controller.tasks[id]?.phase == .finished }
        #expect(controller.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text == "hello" } == true)
        try await controller.send(id: id, prompt: "approval")
        try await wait { !controller.requests.isEmpty }
        let request = try #require(controller.requests.values.first)
        #expect(request.decisions == ["accept", "decline"])
        try await controller.answer(id: request.id, result: .object(["decision": .string("decline")]))
        try await wait { controller.tasks[id]?.phase == .finished }
        #expect(controller.requests.isEmpty)
        try await controller.send(id: id, prompt: "wait")
        try await controller.interrupt(id: id)
        try await wait { controller.tasks[id]?.phase == .interrupted }
        try await controller.send(id: id, prompt: "after stop")
        try await wait { controller.tasks[id]?.phase == .finished }
        #expect(controller.tasks[id]?.transcript.entries.contains { $0.text == "after stop" } == true)
        await transport.shutdown()
    }
    @Test func apiBillingIsRejectedBeforeAnyPrompt() async throws {
        let fixture = try makeFixture(api: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let transport = ClaudeExecutionTransport(folder: fixture.path, executable: fixture.appendingPathComponent("claude"))
        do { try await transport.connect(); Issue.record("API billing was accepted") } catch { #expect(error.localizedDescription.contains("API credentials")) }
        #expect(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent("sent").path))
        await transport.shutdown()
    }
    @Test func queuedMessagesSurviveProcessRestartWithoutAutoSending() async throws {
        let fixture = try makeFixture(api: false), id = UUID().uuidString.lowercased()
        let queueFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/ClaudeQueue/" + id + ".json")
        defer { try? FileManager.default.removeItem(at: fixture); try? FileManager.default.removeItem(at: queueFile) }
        let first = ClaudeExecutionTransport(folder: fixture.path, sessionID: id, executable: fixture.appendingPathComponent("claude"))
        try await first.connect()
        _ = try await first.request("thread/queue/add", .object(["clientUserMessageId": .string("queued-fixture"), "input": .array([.object(["type": .string("text"), "text": .string("Later")])])]))
        await first.shutdown()
        let second = ClaudeExecutionTransport(folder: fixture.path, sessionID: id, resume: true, executable: fixture.appendingPathComponent("claude"))
        try await second.connect()
        let rows = try await second.request("thread/queue/list", .object([:]))["data"].array
        #expect(rows.count == 1)
        #expect(rows.first?["clientUserMessageId"] == .string("queued-fixture"))
        #expect(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent("sent").path))
        _ = try await second.request("thread/queue/delete", .object(["queuedSubmissionId": rows[0]["id"]]))
        #expect(try await second.request("thread/queue/list", .object([:]))["data"].array.isEmpty)
        await second.shutdown()
    }
    @Test func claudeSteeringInterruptsAndStartsReplacement() async throws {
        let fixture = try makeFixture(api: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let transport = ClaudeExecutionTransport(folder: fixture.path, executable: fixture.appendingPathComponent("claude"))
        let controller = ExecutionController(transport: transport)
        await controller.connect()
        let id = try await controller.prepare(folder: fixture.path, title: "Steering", model: "claude/haiku")
        try await controller.send(id: id, prompt: "wait")
        let old = try #require(controller.tasks[id]?.turnID)
        #expect(controller.canSteer(id: id))
        try await controller.steer(id: id, expectedTurnID: old, prompt: "correction")
        try await wait { controller.tasks[id]?.phase == .finished }
        #expect(controller.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text == "correction" } == true)
        #expect(controller.tasks[id]?.turnID != old)
        do {
            _ = try await transport.request("turn/steer", .object(["expectedTurnId": .string(old), "input": .array([])]))
            Issue.record("Stale steer was accepted")
        } catch is ExecutionRPCRejection {}
        await transport.shutdown()
    }
    @Test func goalContinuesAndCompletesThenSurvivesRestart() async throws {
        let fixture = try makeFixture(api: false), id = UUID().uuidString.lowercased()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let transport = ClaudeExecutionTransport(folder: fixture.path, sessionID: id, executable: fixture.appendingPathComponent("claude"))
        let controller = ExecutionController(transport: transport)
        await controller.connect()
        let task = try await controller.prepare(folder: fixture.path, title: "Goal", model: "claude/haiku")
        await controller.loadModes()
        try await controller.sendWithGoal(id: task, prompt: "goal fixture", goal: true)
        try await wait { controller.tasks[task]?.workflow.goal["status"].string == "complete" }
        #expect(controller.tasks[task]?.workflow.goal["turnsUsed"].number == 2)
        await transport.shutdown()
        let resumed = ClaudeExecutionTransport(folder: fixture.path, sessionID: id, resume: true, executable: fixture.appendingPathComponent("claude"))
        try await resumed.connect()
        #expect(try await resumed.request("thread/goal/get", .object([:]))["goal"]["status"].string == "complete")
        await resumed.shutdown()
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/ClaudeGoals/" + id + ".json")
        try? FileManager.default.removeItem(at: file)
    }
    @Test func activeGoalRecoveredFromDiskStaysPausedWithoutSending() async throws {
        let fixture = try makeFixture(api: false), id = UUID().uuidString.lowercased()
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/ClaudeGoals/" + id + ".json")
        defer { try? FileManager.default.removeItem(at: fixture); try? FileManager.default.removeItem(at: file) }
        var goal = ClaudeGoal(objective: "Recovered")
        goal.status = "active"; goal.pendingResult = true; goal.turnsUsed = 2
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(goal).write(to: file)
        #expect(ClaudeExecutionTransport.savedGoal(sessionID: id)["status"].string == "paused")
        #expect(try JSONDecoder().decode(ClaudeGoal.self, from: Data(contentsOf: file)).status == "active")
        let transport = ClaudeExecutionTransport(folder: fixture.path, sessionID: id, executable: fixture.appendingPathComponent("claude"))
        try await transport.connect()
        let saved = try await transport.request("thread/goal/get", .object([:]))["goal"]
        #expect(saved["status"].string == "paused")
        #expect(saved["turnsUsed"].number == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent("sent").path))
        await transport.shutdown()
    }
    @Test func queuedClaudeCorrectionIsRemovedOnceAfterReplacement() async throws {
        let fixture = try makeFixture(api: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let transport = ClaudeExecutionTransport(folder: fixture.path, executable: fixture.appendingPathComponent("claude"))
        let controller = ExecutionController(transport: transport)
        await controller.connect()
        let id = try await controller.prepare(folder: fixture.path, title: "Queued steer", model: "claude/haiku")
        try await controller.send(id: id, prompt: "wait")
        try await controller.enqueue(id: id, prompt: "queued correction")
        let row = try #require(controller.tasks[id]?.workflow.queue.first?["id"].string)
        try await controller.steerQueued(id: id, submissionID: row)
        try await wait { controller.tasks[id]?.phase == .finished }
        #expect(controller.tasks[id]?.workflow.queue.isEmpty == true)
        #expect(controller.tasks[id]?.workflow.queueUncertain == false)
        #expect(controller.tasks[id]?.transcript.entries.filter { $0.kind == "Assistant" && $0.text == "queued correction" }.count == 1)
        await transport.shutdown()
    }
    @Test func blockedFirstGoalResponseNeverRestartsItself() async throws {
        let fixture = try makeFixture(api: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let transport = ClaudeExecutionTransport(folder: fixture.path, executable: fixture.appendingPathComponent("claude"))
        let controller = ExecutionController(transport: transport)
        await controller.connect(); await controller.loadModes()
        let id = try await controller.prepare(folder: fixture.path, title: "Blocked goal", model: "claude/haiku")
        try await controller.sendWithGoal(id: id, prompt: "blocked fixture", goal: true)
        // Completion and the goal update are distinct ordered stream events.
        try await wait { controller.tasks[id]?.phase == .finished && controller.tasks[id]?.workflow.goal["status"].string == "paused" }
        #expect(controller.tasks[id]?.workflow.goal["status"].string == "paused")
        let result = try await transport.request("thread/goal/set", .object(["status": .string("active"), "activateSubmittedGoal": .bool(true)]))
        #expect(result["goal"]["status"].string == "paused")
        #expect(result["goal"]["turnsUsed"].number == 1)
        await transport.shutdown()
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        Issue.record("Timed out waiting for execution state")
    }
    private func makeFixture(api: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-claude-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = #"""
#!/usr/bin/python3
import sys,json,pathlib,re
API = API_VALUE
def emit(x): print(json.dumps(x),flush=True)
def result(error=False, text=''):emit({'type':'result','is_error':error,'result':text})
for line in sys.stdin:
 e=json.loads(line)
 if e['type']=='control_request':
  r=e['request'];sub=r['subtype'];reply={}
  if sub=='initialize':reply={'models':[{'value':'haiku','displayName':'Haiku'}],'account':{'apiKeySource':'managed' if API else 'none','tokenSource':'none' if API else 'user'}}
  emit({'type':'control_response','response':{'subtype':'success','request_id':e['request_id'],'response':reply}})
  if sub=='interrupt':result(True)
 elif e['type']=='control_response':result()
 elif e['type']=='user':
  pathlib.Path('sent').write_text('yes')
  text=e['message']['content'][0]['text']
  if len(e['message']['content']) > 1:
   instruction=e['message']['content'][-1].get('text','')
   marker=re.search(r'DIORAMA_GOAL_([A-Fa-f0-9-]+):',instruction)
   if marker:
    status='BLOCKED' if text=='blocked fixture' else 'CONTINUE' if text=='goal fixture' else 'COMPLETE'
    result(text='DIORAMA_GOAL_'+marker.group(1)+':'+status);continue
  if text=='wait':continue
  if text=='approval':
   emit({'type':'control_request','request_id':'permission','request':{'subtype':'can_use_tool','tool_name':'Write','input':{'file_path':'test'},'tool_use_id':'tool1'}});continue
  emit({'type':'stream_event','event':{'delta':{'type':'text_delta','text':text}}})
  emit({'type':'assistant','message':{'content':[{'type':'text','text':text}]}})
  result()
"""#.replacingOccurrences(of: "API_VALUE", with: api ? "True" : "False")
        let url = dir.appendingPathComponent("claude")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return dir
    }
}
