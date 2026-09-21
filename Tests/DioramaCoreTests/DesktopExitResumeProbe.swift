import Foundation
import Testing
@testable import DioramaCore

@MainActor struct DesktopExitResumeProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_DESKTOP_EXIT_PROBE"] == "1"))
    func continueAfterDesktopExit() async throws {
        let id = "01a0b6cc-6ea4-7f51-842c-112fe57860db"
        let transport = CodexExecutionTransport()
        let controller = ExecutionController(transport: transport)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let reportURL = root.appendingPathComponent("evidence/desktop-exit-native.json")
        var report: [String: Any] = ["thread_id": id, "date": ISO8601DateFormatter().string(from: Date())]
        do {
            var session = Session(id: "Codex:" + id, provider: .codex, url: nil, sessionID: id, title: "Designated Desktop exit test", project: root.appendingPathComponent(".local/imported-resume-0217E525-F77F-4999-93A2-72B7BED468FC").path, modified: Date(), bytes: 0, archived: false, parentID: nil)
            session.classification = .conversation
            try await controller.resumeImported(session)
            report["resume_same_id"] = controller.tasks[id]?.attached == true
            report["resume_did_not_start_turn"] = controller.tasks[id]?.turnID == nil
            try await controller.send(id: id, prompt: "Disposable Desktop exit test. Do not use tools or change files. Repeat the additional DESKTOP marker from the preceding Desktop message and the earlier OAK token. Append INDEPENDENT_AFTER_QUIT_5291.")
            let end = Date().addingTimeInterval(90)
            while controller.tasks[id]?.phase != .finished {
                guard Date() < end, controller.tasks[id]?.phase != .failed else { throw AppServerFailure("Test reply did not finish") }
                try await Task.sleep(for: .milliseconds(100))
            }
            let answer = controller.tasks[id]?.transcript.entries.filter { $0.kind == "Assistant" }.map(\.text).joined() ?? ""
            report["desktop_context_retained"] = answer.contains("DESKTOP-CEDAR-8426") && answer.contains("OAK-6274")
            report["new_marker_recorded"] = answer.contains("INDEPENDENT_AFTER_QUIT_5291")
            #expect(report["desktop_context_retained"] as? Bool == true)
            #expect(report["new_marker_recorded"] as? Bool == true)
            try await controller.stopAndShutdown()
            report["diorama_execution_shutdown"] = !controller.connected
        } catch {
            report["error"] = error.localizedDescription
            await transport.shutdown()
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
            throw error
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
    }
}
