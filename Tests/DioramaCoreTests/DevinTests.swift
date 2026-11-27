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
