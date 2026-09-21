import Foundation
import Testing
@testable import DioramaCore

@MainActor struct ProjectLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_PROJECT_PROBE"] == "1"))
    func worktreeAndContextReachRealAppServer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-project-live-" + UUID().uuidString).resolvingSymlinksInPath()
        let project = try await ProjectGit.initialize(root.path)
        var configured = project
        configured.context.instructions = "For this disposable verification, the verification word is PROJECT_CONTEXT_7291. Do not use tools."
        let work = try await ProjectGit.createWorkspace(project: configured, id: UUID().uuidString, root: root.appendingPathComponent("trees"))
        let transport = CodexExecutionTransport()
        let c = ExecutionController(transport: transport)
        do {
            await c.connect()
            let id = try await c.prepare(folder: work.folder, title: "Diorama Project context verification", model: "", projectContext: work.context.prompt(folder: work.folder, commit: work.baseCommit))
            #expect(c.tasks[id]?.folder == work.folder)
            await c.loadModes()
            try await c.sendWithGoal(id: id, prompt: "Reply with only the verification word from the Project instructions. Do not use tools or access files.", goal: false)
            let deadline = Date().addingTimeInterval(60)
            while c.tasks[id]?.phase != .finished && c.tasks[id]?.phase != .failed {
                guard Date() < deadline else { throw AppServerFailure("Project live verification timed out") }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(c.tasks[id]?.phase == .finished)
            #expect(c.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("PROJECT_CONTEXT_7291") } == true)
            let evidence: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "thread": id, "worktree": work.folder, "branch": work.branch, "base": work.baseCommit, "phase": c.tasks[id]?.phase.rawValue ?? "unknown", "context_received": c.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("PROJECT_CONTEXT_7291") } == true]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/diorama-project-live-evidence.json"))
            if let session = c.tasks[id]?.session { try await c.setArchived(session: session, archived: true) }
            await transport.shutdown()
        } catch { await transport.shutdown(); throw error }
    }
}
