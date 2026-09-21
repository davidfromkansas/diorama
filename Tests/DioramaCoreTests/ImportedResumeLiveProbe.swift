import Foundation
import Testing
@testable import DioramaCore

@MainActor struct ImportedResumeLiveProbe {
    func wait(until condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(90)
        while !condition() {
            guard Date() < end else { throw AppServerFailure("Resume probe timed out") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_RESUME_PROBE"] == "1"))
    func nativeImportedResume() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local/imported-resume-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalTransport = CodexExecutionTransport(), nextTransport = CodexExecutionTransport()
        let original = ExecutionController(transport: originalTransport)
        let next = ExecutionController(transport: nextTransport, journal: root.appendingPathComponent("owned.json"))
        var report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "desktop_quit_reopen_tested": false]
        do {
            await original.connect()
            let id = try await original.prepare(folder: root.path, title: "Diorama imported-resume verification", model: "")
            report["thread_id"] = id
            try await original.send(id: id, prompt: "Disposable integration test. No tools or file changes. Remember OAK-6274 and reply with that token.")
            try await wait { original.tasks[id]?.phase == .finished }
            let imported = try #require(original.tasks[id]?.session)
            do { try await next.resumeImported(imported); Issue.record("Writer conflict was not rejected") } catch {}
            report["writer_conflict_explained"] = next.resumeErrors[id]?.contains("in use by another Codex client") == true
            #expect(report["writer_conflict_explained"] as? Bool == true)
            try await original.stopAndShutdown()
            try await next.resumeImported(imported)
            #expect(next.tasks[id]?.attached == true)
            #expect(next.tasks[id]?.turnID == nil)
            report["resumed_same_id_without_turn"] = next.tasks[id]?.attached == true && next.tasks[id]?.turnID == nil
            try await next.send(id: id, prompt: "No tools or file changes. Repeat the token from our earlier conversation and append RESUME_VERIFIED.")
            try await wait { next.tasks[id]?.phase == .finished }
            let answer = next.tasks[id]?.transcript.entries.filter { $0.kind == "Assistant" }.map(\.text).joined() ?? ""
            report["continued_with_prior_context"] = answer.contains("OAK-6274") && answer.contains("RESUME_VERIFIED")
            #expect(report["continued_with_prior_context"] as? Bool == true)
            try await next.send(id: id, prompt: "Approval test. Use exec_command to run exactly /usr/bin/printf RESUME_APPROVAL_OK with sandbox_permissions=require_escalated and a justification asking to verify this harmless print through Diorama. No other commands or file changes.")
            try await wait { !next.requests.isEmpty || next.tasks[id]?.phase == .finished }
            let request = try #require(next.requests.values.first { $0.threadID == id && $0.method == "item/commandExecution/requestApproval" })
            let command = request.params["command"].string ?? ""
            let allowed = ["/usr/bin/printf RESUME_APPROVAL_OK", "/bin/zsh -lc '/usr/bin/printf RESUME_APPROVAL_OK'", "/bin/zsh -lc \"/usr/bin/printf RESUME_APPROVAL_OK\""]
            guard allowed.contains(command) else { throw AppServerFailure("Unexpected probe command; no approval sent") }
            try await next.answer(id: request.id, result: .object(["decision": .string("accept")]))
            try await wait { next.requests[request.id] == nil && next.tasks[id]?.phase == .finished }
            report["resumed_approval_resolved"] = true
            try await next.send(id: id, prompt: "Interruption test. Use only the terminal tool to run /bin/sleep 30. Do not modify files.")
            try await wait { next.tasks[id]?.activity.contains { $0.kind == "toolStarted" && $0.tool == "commandExecution" } == true }
            try await next.interrupt(id: id)
            try await wait { next.tasks[id]?.phase == .interrupted }
            report["resumed_turn_interruption_confirmed"] = true
            try await next.stopAndShutdown()
            report["shutdown_confirmed"] = !next.connected
            let returningTransport = CodexExecutionTransport()
            let returning = ExecutionController(transport: returningTransport)
            do {
                try await returning.resumeImported(imported)
                try await returning.send(id: id, prompt: "No tools. Repeat the remembered token and the verification marker from before the interruption.")
                try await wait { returning.tasks[id]?.phase == .finished }
                let returned = returning.tasks[id]?.transcript.entries.filter { $0.kind == "Assistant" }.map(\.text).joined() ?? ""
                report["return_to_fresh_client_retained_context"] = returned.contains("OAK-6274") && returned.contains("RESUME_VERIFIED")
                #expect(report["return_to_fresh_client_retained_context"] as? Bool == true)
                try await returning.stopAndShutdown()
            } catch { await returningTransport.shutdown(); throw error }
        } catch {
            report["error"] = error.localizedDescription
            await originalTransport.shutdown(); await nextTransport.shutdown()
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/imported-resume-native.json"))
            throw error
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/imported-resume-native.json"))
        print("IMPORTED_RESUME_PROBE \(report)")
    }
}
