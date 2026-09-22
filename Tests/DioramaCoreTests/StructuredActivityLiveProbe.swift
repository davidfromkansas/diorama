import Foundation
import Testing
@testable import DioramaCore

@MainActor struct StructuredActivityLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_ACTIVITY_LIVE"] == "claude"))
    func claudeSDKActivity() async throws { try await run(claude: true) }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_ACTIVITY_LIVE"] == "codex"))
    func codexActivity() async throws { try await run(claude: false) }
    private func run(claude: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "ACTIVITY_MARKER".write(to: folder.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        let transport: any ExecutionTransport = claude ? ClaudeExecutionTransport(folder: folder.path, backend: .sdk) : CodexExecutionTransport(executable: ProcessInfo.processInfo.environment["DIORAMA_ACTIVITY_CODEX_BINARY"].map { URL(fileURLWithPath: $0) })
        let c = ExecutionController(transport: transport, journal: folder.appendingPathComponent("owned.json"))
        do {
            await c.connect(); try #require(c.connected)
            let id = try await c.prepare(folder: folder.path, title: "Structured activity verification", model: claude ? "claude/sonnet" : (ProcessInfo.processInfo.environment["DIORAMA_ACTIVITY_CODEX_MODEL"] ?? ""))
            let nested = !claude && ProcessInfo.processInfo.environment["DIORAMA_ACTIVITY_NESTED"] == "1"
            let tools = claude ? "Use TaskCreate and TaskUpdate to track exactly two steps, inspect and report. Use exactly one foreground general-purpose Agent child to read fixture.txt and return its marker." : "Use update_plan to track exactly two steps, inspect and report. Use spawn_agent to delegate reading fixture.txt to exactly one child agent, and wait for that child."
            let leafPrompt = "You are the leaf reader. Read " + folder.appendingPathComponent("fixture.txt").path + " with exec_command and return the marker. Do not delegate, access the network, or edit files."
            let childPrompt = "You are the middle agent. Spawn exactly one leaf agent with fork_context false and this exact message: " + leafPrompt + " Then wait for that leaf and return its marker. Do not pass this middle-agent instruction to the leaf."
            let nestedPrompt = "You are the root. Spawn exactly one middle agent with fork_context false and this exact message: " + childPrompt + " Wait for that middle agent and report the marker. Do not pass this root instruction to it. This explicitly authorizes two levels only."

            try await c.send(id: id, prompt: "Isolated integration test. " + (nested ? "Use update_plan for two steps, inspect and report. " + nestedPrompt : tools) + " Do no other work, do not access network, do not edit files. Mark both steps completed after the child reports. Finish with ACTIVITY_VERIFIED.")
            let deadline = Date().addingTimeInterval(150)
            while c.tasks[id]?.phase != .finished {
                guard Date() < deadline, c.tasks[id]?.phase != .failed else { throw AppServerFailure("Live activity failed: " + (c.tasks[id]?.error ?? "timeout")) }
                if let request = c.requests.values.first { throw AppServerFailure("Unexpected approval in read-only activity probe: " + request.method) }
                try await Task.sleep(for: .milliseconds(100))
            }
            if nested, let session = c.tasks[id]?.session { await c.refreshAgents(session) }
            let snapshot = try #require(c.tasks[id]?.structuredActivity)
            if nested {
                try #require(snapshot.agents.count >= 2)
                try #require(snapshot.agents.contains { agent in snapshot.agents.contains { $0.nativeID == agent.parentID } })
            }
            if !claude && snapshot.steps.isEmpty { print("CODEX_COVERAGE: No structured checklist reported. Checklist live coverage remains unverified.") }
            if claude || ProcessInfo.processInfo.environment["DIORAMA_ACTIVITY_REQUIRE_STEPS"] == "1" {
                try #require(!snapshot.steps.isEmpty)
                try #require(snapshot.steps.allSatisfy { $0.status == "completed" })
            }
            if let child = snapshot.agents.first(where: { $0.kind == "agent" }) {
                let history = try await c.inspectChild(provider: claude ? .claude : .codex, parentID: id, childID: child.nativeID, folder: folder.path)
                try #require(history.error == nil); try #require(history.entries.contains { $0.text.contains("ACTIVITY_MARKER") })
            } else if claude { Issue.record("Claude child was not captured") }
            else { print("CODEX_COVERAGE: No structured agent event observed; do not claim live subagent coverage for this runtime.") }
            try #require(c.tasks[id]?.transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("ACTIVITY_VERIFIED") } == true)
            try await Task.sleep(for: .milliseconds(500))
            let restored = SessionActivityStore.read(directory: folder.appendingPathComponent("SessionActivity"), provider: claude ? .claude : .codex, id: id)
            try #require(restored.lastKnown); if claude { try #require(!restored.agents.isEmpty) }
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/" + (claude ? "claude" : "codex") + "-structured-activity.json")
            try JSONEncoder().encode(snapshot).write(to: output, options: .atomic)
            await transport.shutdown()
        } catch { for task in c.tasks.values where task.turnID != nil { try? await c.interrupt(id: task.id) }; await transport.shutdown(); throw error }
    }
}
