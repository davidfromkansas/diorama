import Foundation
import Testing
@testable import DioramaCore

struct KitchenActivityTests {
    @Test func shellCommandsAreUnderstood() {
        let cases: [(String, String, KitchenActivity)] = [
            ("commandExecution", #"/bin/zsh -lc "sed -n 1,80p Sources/App.swift""#, .researching),
            ("commandExecution", #"/bin/zsh -lc 'rg -n "foo" Sources | head -20'"#, .researching),
            ("Bash", "cd app && npm test", .testing),
            ("Bash", "swift test --filter Kitchen 2>&1 | tail -5", .testing),
            ("Bash", "git log --oneline -5", .researching),
            ("Bash", "git status --short && git diff --stat", .researching),
            ("Bash", "git commit -m x", .commands),
            ("Bash", "python3 build.py", .commands),
            ("Bash", "ls -la && cat README.md", .researching),
            ("Bash", "sed -i '' 's/a/b/' file.swift", .commands),
            ("Bash", "cat a > b", .commands),
            ("Bash", "FOO=1 rg foo 2>/dev/null", .researching),
            ("Bash", "echo contest", .researching),
            ("exec_command", #"["/bin/zsh","-lc","cat package.json"]"#, .researching),
            ("Bash", "", .commands),
        ]
        for (tool, detail, expected) in cases {
            #expect(KitchenActivity.classify(tool: tool, detail: detail) == expected, "\(tool) \(detail)")
        }
    }

    @Test func toolNamesMapToActivities() {
        #expect(KitchenActivity.classify(tool: "Read") == .researching)
        #expect(KitchenActivity.classify(tool: "ToolSearch") == .researching)
        #expect(KitchenActivity.classify(tool: "web__run") == .researching)
        #expect(KitchenActivity.classify(tool: "webSearch") == .researching)
        #expect(KitchenActivity.classify(tool: "TaskCreate") == .planning)
        #expect(KitchenActivity.classify(tool: "update_plan") == .planning)
        #expect(KitchenActivity.classify(tool: "Edit") == .editing)
        #expect(KitchenActivity.classify(tool: "fileChange") == .editing)
        #expect(KitchenActivity.classify(tool: "apply_patch") == .editing)
        #expect(KitchenActivity.classify(tool: "mcp__linear__create_issue") == .other)
        #expect(KitchenActivity.classify(tool: "Agent") == .other)
    }

    @Test func codeModeCallsRevealTheInnerTool() throws {
        let exec = try #require(ActivityParser.codeModeCall(#"text(await tools.exec_command({cmd:"cat \"a b\".md",max_output_tokens:6000}));"#))
        #expect(exec.tool == "exec_command")
        #expect(exec.detail == #"cat "a b".md"#)
        #expect(ActivityParser.codeModeCall("await tools.exec_command({cmd:'rg -n foo'})")?.detail == "rg -n foo")
        #expect(ActivityParser.codeModeCall("await tools.exec_command({cmd:`npm test`})")?.detail == "npm test")
        #expect(ActivityParser.codeModeCall("text(await tools.web__run({search_query:[{q:'x'}]}))")?.tool == "web__run")
        #expect(ActivityParser.codeModeCall("await tools.update_plan({plan:[]})")?.tool == "update_plan")
        #expect(ActivityParser.codeModeCall("text(ALL_TOOLS.filter(x=>x))") == nil)
    }

    @Test func codexExecTranscriptLineBecomesTheInnerCommand() {
        let session = Session(id: "codex:s", provider: .codex, url: nil, sessionID: "s", title: "s", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let line: [String: Any] = ["type": "response_item", "timestamp": "2026-10-04T10:00:00Z",
                                   "payload": ["type": "custom_tool_call", "name": "exec", "call_id": "c1",
                                               "input": #"text(await tools.exec_command({cmd:"sed -n 1,40p README.md"}));"#]]
        let event = ActivityParser.transcript(line, session: session, id: "x", now: Date()).first
        #expect(event?.tool == "exec_command")
        #expect(event?.detail == "sed -n 1,40p README.md")
        #expect(KitchenActivity.classify(tool: event?.tool ?? "", detail: event?.detail ?? "") == .researching)
    }

    @Test func codexArgvCommandsAreJoined() {
        let item = CodexOutputEvidence.canonical(.object(["type": .string("CommandExecution"), "command": .array([.string("/bin/zsh"), .string("-lc"), .string("npm test")])]))
        #expect(item["command"].string == "/bin/zsh -lc npm test")
        #expect(KitchenActivity.classify(tool: "commandExecution", detail: item["command"].string ?? "") == .testing)
    }
}
