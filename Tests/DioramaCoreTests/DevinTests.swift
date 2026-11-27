import Foundation
import Testing
@testable import DioramaCore

struct DevinProviderTests {
    @Test func modelIdsNameTheirProvider() {
        #expect(Provider.forModel("devin/opus") == .devin)
        #expect(Provider.forModel("devin/default") == .devin)
        #expect(Provider.forModel("claude/default") == .claude)
        #expect(Provider.forModel("gpt-5.6") == .codex)
        #expect(Provider.forModel("") == .codex)
        #expect(Provider.connectable == [.claude, .codex, .devin])
        #expect(Provider.devin.key == "devin" && Provider.devin.loginArguments == ["auth", "login"])
    }
    @Test func devinPermissionModesRoundTrip() {
        for choice in [ApprovalReviewChoice.user, .autoReview, .acceptEdits, .fullAccess] {
            #expect(ApprovalReviewChoice.devin(choice.devinMode) == choice)
            #expect(choice.mode(for: .devin) == choice.devinMode)
        }
        #expect(ApprovalReviewChoice.inherit.mode(for: .devin) == nil)
        #expect(ApprovalReviewChoice.fullAccess.mode(for: .codex) == nil)
    }
    @Test func catalogReadsEveryReportedShape() {
        let objects = DevinCatalog.rows(.array([.object(["slug": .string("opus"), "name": .string("Claude Opus")]), .object(["id": .string("swe-1-6-fast")])]))
        #expect(objects.map { $0["model"].string } == ["devin/default", "devin/opus", "devin/swe-1-6-fast"])
        #expect(objects[1]["displayName"].string == "Devin · Claude Opus")
        let wrapped = DevinCatalog.rows(.object(["models": .array([.string("gemini"), .string("gemini")])]))
        #expect(wrapped.map { $0["model"].string } == ["devin/default", "devin/gemini"])
        // Unreadable output still offers Devin's own default.
        #expect(DevinCatalog.rows(.null).map { $0["model"].string } == ["devin/default"])
    }
    @Test func onboardingCanStartWithDevinAlone() {
        let models = [ExecutionModel(id: "devin/default", name: "Devin · Default", efforts: [], defaultEffort: "", isDefault: false)]
        let connections: WireValue = .object(["devin": .bool(true)])
        #expect(OnboardingModels.initialSelection(models: models, connections: connections) == "devin/default")
        #expect(OnboardingModels.isAvailable("devin/default", models: models, connections: connections))
        #expect(!OnboardingModels.isAvailable("", models: models, connections: connections))
    }
    @Test func childEnvironmentOnlySetsWhatWasChosen() {
        let chosen = DevinExecutionTransport.childEnvironment(["DEVIN_MODEL": "old"], folder: "/tmp/x/../y", model: "devin/opus", permissionMode: "accept-edits")
        #expect(chosen["DEVIN_MODEL"] == "opus" && chosen["DEVIN_PERMISSION_MODE"] == "accept-edits" && chosen["PWD"] == "/tmp/y")
        let defaults = DevinExecutionTransport.childEnvironment(["DEVIN_MODEL": "old"], folder: "/tmp", model: "devin/default", permissionMode: nil)
        #expect(defaults["DEVIN_MODEL"] == nil && defaults["DEVIN_PERMISSION_MODE"] == nil)
    }
}

/// Runs the transport against a small stand-in for `devin acp` that speaks the Agent Client
/// Protocol: it starts a session, streams a message, asks permission for one tool, and ends.
struct DevinTransportTests {
    static let fakeAgent = #"""
    import json, sys
    def send(m): sys.stdout.write(json.dumps(m) + "\n"); sys.stdout.flush()
    asked = None
    for line in sys.stdin:
        m = json.loads(line)
        method, mid = m.get("method"), m.get("id")
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": 1, "agentCapabilities": {"loadSession": True}}})
        elif method == "session/new":
            send({"jsonrpc": "2.0", "id": mid, "result": {"sessionId": "brisk-otter"}})
        elif method == "session/prompt":
            sid = m["params"]["sessionId"]
            def update(u): send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": u}})
            update({"sessionUpdate": "plan", "entries": [{"content": "Look around", "status": "in_progress", "priority": "high"}]})
            update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Hello "}})
            update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "there"}})
            update({"sessionUpdate": "tool_call", "toolCallId": "t1", "title": "ls", "kind": "execute", "status": "pending", "rawInput": {"command": "ls"}})
            asked = mid
            send({"jsonrpc": "2.0", "id": 900, "method": "session/request_permission", "params": {"sessionId": sid,
                  "toolCall": {"toolCallId": "t1", "title": "ls", "kind": "execute", "rawInput": {"command": "ls"}},
                  "options": [{"optionId": "yes", "name": "Allow", "kind": "allow_once"}, {"optionId": "no", "name": "Deny", "kind": "reject_once"}]}})
        elif mid == 900:
            sid = "brisk-otter"
            choice = m["result"]["outcome"].get("optionId")
            send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": {"sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed" if choice == "yes" else "failed", "content": [{"type": "content", "content": {"type": "text", "text": "README.md"}}]}}})
            send({"jsonrpc": "2.0", "id": asked, "result": {"stopReason": "end_turn"}})
    """#

    @Test func turnStreamsMessagesToolsAndApprovals() async throws {
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devin-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("agent.py")
        try Self.fakeAgent.write(to: script, atomically: true, encoding: .utf8)
        let executable = folder.appendingPathComponent("devin")
        try "#!/bin/sh\nexec /usr/bin/python3 \"\(script.path)\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let transport = DevinExecutionTransport(folder: folder.path, context: "Project notes", executable: executable)
        try await transport.connect()
        #expect(await transport.id == "brisk-otter")
        let started = try await transport.request("thread/start", .object([:]))
        #expect(started["thread"]["id"].string == "brisk-otter")

        var seen: [WireValue] = []
        let collector = Task { () -> [WireValue] in
            var events: [WireValue] = []
            for await event in transport.events {
                events.append(event)
                if event["method"].string == "item/commandExecution/requestApproval" {
                    try? await transport.respond(id: event["id"], result: .object(["decision": .string("accept")]))
                }
                if event["method"].string == "turn/completed" { break }
            }
            return events
        }
        _ = try await transport.request("turn/start", .object(["input": .array([.object(["type": .string("text"), "text": .string("Hi")])])]))
        seen = await collector.value
        let methods = seen.compactMap { $0["method"].string }
        #expect(methods.first == "turn/started")
        #expect(methods.contains("turn/plan/updated") && methods.contains("item/commandExecution/requestApproval") && methods.contains("serverRequest/resolved"))
        let message = seen.first { $0["method"].string == "item/completed" && $0["params"]["item"]["type"].string == "agentMessage" }
        #expect(message?["params"]["item"]["text"].string == "Hello there")
        let tool = seen.last { $0["method"].string == "item/completed" && $0["params"]["item"]["id"].string == "t1" }
        #expect(tool?["params"]["item"]["status"].string == "completed" && tool?["params"]["item"]["result"].string == "README.md")
        #expect(seen.last?["params"]["turn"]["status"].string == "completed")
        await transport.shutdown()
    }
}

/// A stand-in for Devin's REST API: one session that answers once and then waits for the person.
actor FakeDevinAPI {
    var requests: [(method: String, path: String, body: WireValue)] = []
    var polls = 0
    func handle(_ request: URLRequest) -> (Data, URLResponse) {
        let path = request.url!.path, method = request.httpMethod ?? "GET"
        let body = request.httpBody.flatMap { try? JSONDecoder().decode(WireValue.self, from: $0) } ?? .null
        requests.append((method, path, body))
        var reply: WireValue = .object([:]), status = 200
        if request.value(forHTTPHeaderField: "Authorization") != "Bearer cog_good" { status = 401; reply = .object(["detail": .string("bad key")]) }
        else if method == "POST", path.hasSuffix("/organizations/org-1/sessions") {
            reply = .object(["session_id": .string("abc"), "url": .string("https://app.devin.ai/sessions/abc"), "status": .string("new")])
        } else if path.hasSuffix("/sessions/devin-abc/messages"), method == "GET" {
            polls += 1
            reply = .object(["items": .array(polls == 1 ? [
                .object(["event_id": .string("e1"), "source": .string("user"), "message": .string("Fix it")]),
                .object(["event_id": .string("e2"), "source": .string("devin"), "message": .string("Opened a pull request")]),
            ] : []), "end_cursor": .string("c\(polls)"), "has_next_page": .bool(false)])
        } else if path.hasSuffix("/sessions/devin-abc") {
            reply = .object(["status": .string("running"), "status_detail": .string("waiting_for_user")])
        } else if path.hasSuffix("/sessions") { reply = .object(["items": .array([])]) }
        let data = try! JSONEncoder().encode(reply)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private actor NoCodex: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    func connect() async throws { throw AppServerFailure("Codex not installed") }
    func request(_ method: String, _ params: WireValue) async throws -> WireValue { throw AppServerFailure("Codex not installed") }
    func respond(id: WireValue, result: WireValue) async throws {}
    func reject(id: WireValue, message: String) async throws {}
    func shutdown() async {}
}

struct DevinCloudTests {
    @Test func githubRemotesNameTheRepository() {
        #expect(DevinCloudTransport.githubName("https://github.com/davidfromkansas/diorama.git") == "davidfromkansas/diorama")
        #expect(DevinCloudTransport.githubName("git@github.com:owner/repo.git\n") == "owner/repo")
        #expect(DevinCloudTransport.githubName("ssh://git@github.com/owner/repo") == "owner/repo")
        #expect(DevinCloudTransport.githubName("https://gitlab.com/owner/repo") == nil)
    }
    @Test func sessionStatesEndTheTurn() {
        #expect(DevinCloudTransport.outcome(status: "running", detail: "working") == nil)
        #expect(DevinCloudTransport.outcome(status: "running", detail: "waiting_for_user")?.status == "completed")
        #expect(DevinCloudTransport.outcome(status: "running", detail: "out_of_credits")?.status == "failed")
        #expect(DevinCloudTransport.outcome(status: "exit", detail: nil)?.status == "completed")
        #expect(DevinCloudTransport.outcome(status: "suspended", detail: nil)?.notice != nil)
    }
    @MainActor @Test func cloudPermissionsFollowTheOrganization() {
        let controller = ExecutionController(transport: NoCodex())
        #expect(controller.permissionUnavailable(.fullAccess, model: DevinCloudAPI.modelID) != nil)
        #expect(controller.permissionUnavailable(.fullAccess, model: "devin/opus") == nil)
    }
    @Test func badKeyIsReported() async {
        let fake = FakeDevinAPI()
        let api = DevinCloudAPI(credentials: .init(apiKey: "cog_wrong", organization: "org-1"), send: { await fake.handle($0) })
        await #expect(throws: ExecutionRPCRejection.self) { try await api.verify() }
    }
    @Test func apiKeyAloneConnectsDevinAndRunsACloudTurn() async throws {
        let fake = FakeDevinAPI()
        let api = DevinCloudAPI(credentials: .init(apiKey: " cog_good\n", organization: "org-1"), send: { await fake.handle($0) })
        let router = AgentExecutionTransport(codex: NoCodex(), claudeProbe: { [] }, devinProbe: { throw AppServerFailure("Devin CLI not installed") },
                                             devinCloudProbe: { try await api.verify(); return api })
        try await router.connect()
        let info = try await router.request("diorama/connections", .null)
        #expect(info["devin"].bool && info["devinAPI"].bool && !info["devinCLI"].bool && info["devinError"] == .null)
        let models = try await router.request("model/list", .null)["data"].array.compactMap { $0["model"].string }
        #expect(models == [DevinCloudAPI.modelID])
        // The CLI isn't connected, so a CLI model still says so.
        await #expect(throws: ExecutionRPCRejection.self) { try await router.request("thread/start", .object(["model": .string("devin/default")])) }

        let started = try await router.request("thread/start", .object(["model": .string(DevinCloudAPI.modelID), "cwd": .string("/tmp"), "developerInstructions": .string("Notes")]))
        let thread = try #require(started["thread"]["id"].string)
        #expect(thread.hasPrefix(DevinCloudAPI.threadPrefix) && started["provider"].string == "Devin")
        defer { try? FileManager.default.removeItem(at: DevinCloudTransport.file(thread)) }

        let collector = Task { () -> [WireValue] in
            var events: [WireValue] = []
            for await event in router.events {
                events.append(event)
                if event["method"].string == "turn/completed" { break }
            }
            return events
        }
        _ = try await router.request("turn/start", .object(["threadId": .string(thread), "input": .array([.object(["type": .string("text"), "text": .string("Fix it")])])]))
        let seen = await collector.value
        let texts = seen.filter { $0["method"].string == "item/completed" && $0["params"]["item"]["type"].string == "agentMessage" }.compactMap { $0["params"]["item"]["text"].string }
        #expect(texts.first?.contains("https://app.devin.ai/sessions/abc") == true)
        #expect(texts.contains("Opened a pull request") && !texts.contains("Fix it"))
        #expect(seen.last?["params"]["turn"]["status"].string == "completed")
        let created = await fake.requests.first { $0.method == "POST" }
        #expect(created?.path == "/v3/organizations/org-1/sessions")
        #expect(created?.body["prompt"].string?.contains("<diorama_context>\nNotes") == true && created?.body["prompt"].string?.hasSuffix("Fix it") == true)
        await router.shutdown()
    }
}
