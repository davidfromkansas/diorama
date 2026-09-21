import Foundation
import Testing
@testable import DioramaCore

@MainActor struct ExecutionLiveProbe {
    func wait(_ seconds: Double = 60, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw AppServerFailure("Live probe condition timed out") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_EXECUTION_PROBE"] == "1"))
    func realExecutionLifecycle() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/execution-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = CodexExecutionTransport()
        let c = ExecutionController(transport: transport, journal: root.appendingPathComponent("owned.json"))
        await c.connect(); #expect(c.connected); #expect(!c.models.isEmpty)
        var evidence: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "model_count": c.models.count]
        do {
            let id = try await c.prepare(folder: root.path, title: "Diorama native execution verification", model: "")
            evidence["thread_id"] = id; evidence["effective_settings"] = c.tasks[id]?.settings
            try await c.send(id: id, prompt: "This is a disposable integration test. Do not use tools or modify files. Reply exactly DIORAMA_EXECUTION_READY.")
            try await wait { c.tasks[id]?.phase == .finished || c.tasks[id]?.phase == .failed }
            #expect(c.tasks[id]?.transcript.entries.contains { $0.text.contains("DIORAMA_EXECUTION_READY") } == true)
            evidence["new_task_streaming_completed"] = c.tasks[id]?.phase == .finished
            try await c.send(id: id, prompt: "Now use the built-in terminal tool to run only /usr/bin/printf DIORAMA_TOOL_VERIFIED, then repeat its output. Do not modify files.")
            try await wait { c.tasks[id]?.phase == .finished || c.tasks[id]?.phase == .failed }
            evidence["tool_completed"] = c.tasks[id]?.activity.contains { $0.kind == "toolFinished" && $0.tool == "commandExecution" } == true
            #expect(evidence["tool_completed"] as? Bool == true)
            try await c.send(id: id, prompt: "Approval verification: use exec_command to run exactly /usr/bin/printf DIORAMA_APPROVAL_CHECK with sandbox_permissions=require_escalated and justification 'Verify a harmless print command through Diorama approval handling'. No other commands or file changes. If the escalation tool is unavailable, say APPROVAL_UNAVAILABLE.")
            try await wait { !c.requests.isEmpty || c.tasks[id]?.phase == .finished || c.tasks[id]?.phase == .failed }
            if let request = c.requests.values.first(where: { $0.threadID == id && $0.method == "item/commandExecution/requestApproval" }) {
                evidence["approval_received"] = true
                // Explicitly authorized test: only allow the exact harmless print command.
                guard request.params["command"].string?.contains("/usr/bin/printf DIORAMA_APPROVAL_CHECK") == true else { throw AppServerFailure("Unexpected approval command; not approving") }
                try await c.answer(id: request.id, result: .object(["decision": .string("accept")]))
                try await wait { c.requests[request.id] == nil }
                evidence["approval_resolved"] = true
            } else { evidence["approval_received"] = false }
            try await wait { c.tasks[id]?.phase == .finished || c.tasks[id]?.phase == .failed }
            // Use documented plan mode only for this designated input-request probe.
            _ = try await transport.request("turn/start", .object(["threadId": .string(id), "collaborationMode": .object(["mode": .string("plan"), "settings": .object(["model": .string(c.tasks[id]?.model ?? ""), "reasoning_effort": .string("low"), "developer_instructions": .null])]), "input": .array([.object(["type": .string("text"), "text": .string("Use request_user_input now to ask which harmless test label I prefer: Alpha or Beta. Do not use any other tools or change files. After my answer, reply with the chosen label.")])])]))
            try await wait { c.requests.values.contains { $0.isInput } || c.tasks[id]?.phase == .failed }
            if let request = c.requests.values.first(where: { $0.isInput }) {
                var answers: [String: WireValue] = [:]
                for question in request.params["questions"].array {
                    if let key = question["id"].string { answers[key] = .object(["answers": .array([.string(question["options"].array.first?["label"].string ?? "Alpha")])]) }
                }
                try await c.answer(id: request.id, result: .object(["answers": .object(answers)]))
                try await wait { c.requests[request.id] == nil }
                evidence["input_resolved"] = true
            }
            try await wait { c.tasks[id]?.phase == .finished || c.tasks[id]?.phase == .failed }
            let second = try await c.prepare(folder: root.path, title: "Diorama simultaneous execution verification", model: "")
            evidence["second_thread_id"] = second
            try await c.send(id: second, prompt: "Use only the terminal tool to run /bin/sleep 30. Do not modify files. This is an interruption test.")
            try await wait { c.tasks[second]?.activity.contains { $0.kind == "toolStarted" && $0.tool == "commandExecution" } == true }
            try await c.send(id: id, prompt: "Without tools, reply CONCURRENT_TASK_OK.")
            try await wait { c.tasks[id]?.phase == .finished }
            evidence["simultaneous_tasks"] = c.tasks[second]?.phase == .working
            try await c.interrupt(id: second)
            try await wait { c.tasks[second]?.phase == .interrupted }
            evidence["interruption_confirmed"] = true
            try await c.stopAndShutdown()
            evidence["shutdown_confirmed"] = !c.connected
            let fresh = ExecutionController(transport: CodexExecutionTransport(), journal: root.appendingPathComponent("owned.json"))
            #expect(!fresh.connected)
            evidence["restart_did_not_start_work"] = fresh.tasks.values.allSatisfy { !$0.attached }
            await fresh.connect()
            try await fresh.reconnectOwned(id: id)
            evidence["owned_reconnect"] = fresh.tasks[id]?.attached == true
            try await fresh.stopAndShutdown()
        } catch {
            evidence["error"] = error.localizedDescription
            // Finish only our probe processes; never interrupt imported conversations.
            for task in c.tasks.values where task.attached && task.turnID != nil { try? await c.interrupt(id: task.id) }
            await transport.shutdown()
            let report = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/execution-native.json")
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: report)
            throw error
        }
        let report = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/execution-native.json")
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: report)
        print("EXECUTION_PROBE " + String(decoding: try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]), as: UTF8.self))
    }
}
