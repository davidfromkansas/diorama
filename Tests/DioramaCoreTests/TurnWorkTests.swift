import Foundation
import Testing
@testable import DioramaCore

struct TurnWorkTests {
    private func event(_ kind: String, tool: String? = nil, detail: String? = nil, call: String? = nil) -> ActivityEvent {
        ActivityEvent(id: UUID().uuidString, provider: "Codex", sessionID: "s", kind: kind, source: "test", callID: call, tool: tool, detail: detail)
    }

    @Test func summarizesOnlyTheCurrentTurn() {
        let work = TurnWork.from([
            event("started"), event("toolStarted", tool: "Edit", detail: "/old.swift", call: "0"),
            event("turnStarted"),
            event("toolStarted", tool: "exec_command", detail: "rg --files", call: "1"), event("toolFinished", call: "1"),
            event("toolStarted", tool: "apply_patch", detail: "/r/a.js\n/r/b.js", call: "2"), event("toolFinished", call: "2"),
            event("toolStarted", tool: "Edit", detail: "/r/a.js", call: "3"),
            event("toolStarted", tool: "Bash", detail: "npm run build", call: "4"), event("toolFailed", call: "4"),
            event("toolStarted", tool: "Bash", detail: "npm test", call: "5"), event("toolFailed", call: "5"),
            event("toolStarted", tool: "exec_command", detail: "/bin/zsh -lc 'npm test'", call: "6"), event("toolFinished", call: "6"),
            event("toolStarted", tool: "Bash", detail: "swift test", call: "7"),
        ])
        #expect(work.files == ["/r/a.js", "/r/b.js"])
        // Read-only lookups and tests are not counted as commands.
        #expect(work.commands == 1 && work.failedCommands == 1)
        #expect(work.tests.map(\.outcome) == [.failed, .passed, .running])
        #expect(work.tests[1].command == "npm test")
        #expect(TurnWork.from([event("started")]).isEmpty)
    }

    @Test func readsFinalStatusFromToolRecords() {
        func record(_ title: String, _ status: String, command: String? = nil, detail: String = "") -> SessionActivityRecord {
            SessionActivityRecord(id: UUID().uuidString, provider: "Claude", sessionID: "s", nativeID: UUID().uuidString, kind: "tool", title: title,
                                  status: status, detail: detail, source: "test", observedAt: Date(), data: command.map { .object(["command": .string($0)]) } ?? .null)
        }
        let work = TurnWork.from([record("Write", "completed", detail: "/r/new.md"), record("Bash", "failed", command: "pytest -q"),
                                  record("Bash", "completed", command: "make")])
        #expect(work.files == ["/r/new.md"] && work.commands == 1 && work.failedCommands == 0)
        #expect(work.tests == [.init(command: "pytest -q", outcome: .failed)])
    }

    @Test func codexTranscriptsNamePatchedFilesAndFailedCommands() {
        let session = Session(id: "s", provider: .codex, url: nil, sessionID: "s", title: "t", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let patch: [String: Any] = ["type": "response_item", "payload": ["type": "custom_tool_call", "call_id": "c1", "name": "apply_patch",
            "input": "*** Begin Patch\n*** Update File: /r/a.js\n@@\n-x\n+y\n*** Add File: /r/b.js\n+z\n*** End Patch"]]
        let started = ActivityParser.transcript(patch, session: session, id: "1", now: Date())
        #expect(started.first?.tool == "apply_patch" && started.first?.detail == "/r/a.js\n/r/b.js")
        let output: [String: Any] = ["type": "response_item", "payload": ["type": "function_call_output", "call_id": "c2",
            "output": "Command: /bin/zsh -lc 'npm test'\nWall time: 1 seconds\nProcess exited with code 1\nOutput:"]]
        #expect(ActivityParser.transcript(output, session: session, id: "2", now: Date()).first?.kind == "toolFailed")
        #expect(ActivityParser.exitCode("Process exited with code 0\n") == 0)
        #expect(ActivityParser.exitCode("no status") == nil)
    }
}
