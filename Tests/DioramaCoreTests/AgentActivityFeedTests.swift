import Foundation
import Testing
@testable import DioramaCore

struct AgentActivityFeedTests {
    private func event(_ kind: String, tool: String? = nil, detail: String? = nil, call: String? = nil, at seconds: Double = 0) -> ActivityEvent {
        ActivityEvent(id: UUID().uuidString, provider: "Codex", sessionID: "s", kind: kind, source: "test",
                      recordedAt: Date(timeIntervalSince1970: seconds), callID: call, tool: tool, detail: detail)
    }

    @Test func distillsATurnIntoShortLines() {
        let feed = AgentActivityFeed.entries(from: [
            event("started"),
            event("toolStarted", tool: "exec_command", detail: "pwd", call: "1"), event("toolFinished", call: "1"),
            event("toolStarted", tool: "exec_command", detail: "cat README.md", call: "2"), event("toolFinished", call: "2"),
            event("toolStarted", tool: "Read", detail: "/r/math.js", call: "3"),
            event("toolStarted", tool: "apply_patch", detail: "/r/test.js", call: "4"),
            event("toolStarted", tool: "exec_command", detail: "npm test", call: "5", at: 10), event("toolFailed", detail: "exit=1", call: "5", at: 11),
            event("toolStarted", tool: "js", call: "6"),
            event("toolStarted", tool: "exec_command", detail: "/bin/zsh -lc 'npm run build'", call: "7", at: 20),
            event("toolFinished", detail: "session=9", call: "7", at: 21),
            event("toolStarted", tool: "write_stdin", detail: "session=9", call: "8"), event("toolFinished", detail: "exit=0", call: "8", at: 35),
            event("finished"),
        ])
        #expect(feed.map(\.title) == ["Started a turn", "Looked at project files, README.md +1", "Edited test.js", "Tested · npm test", "Ran npm run build", "Turn finished"])
        #expect(feed[3].outcome == .failed && feed[3].duration == 1)
        // The build kept running in its shell session; a later poll reported it.
        #expect(feed[4].outcome == .done && feed[4].duration == 15)
    }

    @Test func codexHistoryCountsEachCallOnce() {
        func record(_ title: String, _ status: String, id: String, detail: String = "", data: WireValue = .null) -> SessionActivityRecord {
            SessionActivityRecord(id: id + ":r:" + UUID().uuidString, provider: "Codex", sessionID: "s", nativeID: id, kind: "tool", title: title,
                                  status: status, detail: detail, source: "test", observedAt: Date(), data: data)
        }
        let item: WireValue = .object(["nativeItem": .bool(true), "exitCode": .number(1), "durationMs": .number(2500)])
        let feed = AgentActivityFeed.entries(from: [
            record("exec_command", "Called", id: "a", detail: "npm test"),
            record("commandExecution", "running", id: "b", detail: "/bin/zsh -lc 'npm test'", data: .object(["nativeItem": .bool(true)])),
            record("commandExecution", "completed", id: "b", detail: "/bin/zsh -lc 'npm test'", data: item),
            record("exec_command", "Returned", id: "a", detail: "npm test"),
        ])
        #expect(feed.map(\.title) == ["Tested · npm test"])
        #expect(feed.first?.outcome == .failed && feed.first?.duration == 2.5)
    }

    @Test func codexPollsNameTheSessionTheyRead() {
        let session = Session(id: "s", provider: .codex, url: nil, sessionID: "s", title: "t", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let poll: [String: Any] = ["type": "response_item", "payload": ["type": "custom_tool_call", "call_id": "p", "name": "exec",
            "input": #"text(await tools.write_stdin({session_id:17775,chars:"",yield_time_ms:1000}));"#]]
        let call: [String: Any] = ["type": "response_item", "payload": ["type": "function_call", "call_id": "q", "name": "write_stdin", "arguments": #"{"session_id":42,"chars":""}"#]]
        #expect(ActivityParser.transcript(poll, session: session, id: "1", now: Date()).first?.detail == "session=17775")
        #expect(ActivityParser.transcript(call, session: session, id: "2", now: Date()).first?.detail == "session=42")
    }
}
