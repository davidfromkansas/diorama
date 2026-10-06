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
            ("Bash", "sed -i '' 's/a/b/' file.swift", .editing),
            ("Bash", "cat a > b", .editing),
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
        // Skills and MCP tools are fetched from the pantry.
        #expect(KitchenActivity.classify(tool: "mcp__linear__create_issue") == .resources)
        #expect(KitchenActivity.classify(tool: "Skill") == .resources)
        #expect(KitchenActivity.classify(tool: "mcpToolCall") == .resources)
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

    @Test func shellWritesCountAsEdits() {
        // Ruby wrote a whole website from the shell and never used an edit tool.
        let page = "cat > sf-time/dist/index.html <<'EOF'\n<!doctype html>\n<div class=\"a\">x > y</div>\nEOF"
        #expect(KitchenActivity.writtenFiles(command: page) == ["sf-time/dist/index.html"])
        #expect(KitchenActivity.classify(tool: "exec_command", detail: page) == .editing)
        #expect(KitchenActivity.isEditing(tool: "exec_command", detail: page))
        #expect(KitchenActivity.writtenFiles(command: "curl -fsSL https://x/suncalc.js -o sf-time/dist/suncalc.js && echo done") == ["sf-time/dist/suncalc.js"])
        #expect(KitchenActivity.writtenFiles(command: "node report.js | tee summary.md") == ["summary.md"])
        // Scratch output isn't editing the project.
        #expect(KitchenActivity.writtenFiles(command: "npm run build 2>&1 | tee build.log").isEmpty)
        #expect(KitchenActivity.writtenFiles(command: "python3 -m http.server 5184 > /tmp/server.out 2>&1 &").isEmpty)
        #expect(KitchenActivity.writtenFiles(command: "sed -i '' 's/a/b/' math.js") == ["math.js"])
        #expect(KitchenActivity.writtenFiles(command: "cp a.txt b.txt") == ["b.txt"])
        // Not writes: stream redirects, /dev/null, plain reads, directory setup.
        #expect(KitchenActivity.writtenFiles(command: "npm run build > /dev/null 2>&1").isEmpty)
        #expect(KitchenActivity.writtenFiles(command: "cat README.md").isEmpty)
        #expect(KitchenActivity.writtenFiles(command: "mkdir -p sf-time/dist").isEmpty)
        #expect(KitchenActivity.classify(tool: "exec_command", detail: "npm test > out.txt") == .testing)
    }

    @Test func testsAfterAnInlineFileAreStillSeen() {
        // Remy wrote app.js from a heredoc, then built and tested in the same command.
        let body = String(repeating: "const x = 1;\n", count: 200)
        let command = "cat > public/app.js <<'EOF'\n" + body + "EOF\nnpm run build && npm test"
        #expect(KitchenActivity.withoutHeredocs(command) == "cat > public/app.js <<'EOF'\nnpm run build && npm test")
        #expect(KitchenActivity.classify(command: command) == .testing)
        #expect(KitchenActivity.classify(command: "node --test") == .testing)
        #expect(KitchenActivity.classify(command: "node time.test.mjs") == .testing)
        var work = TurnWork(); work.started(tool: "exec_command", detail: command, call: "1"); work.finished(call: "1", failed: false)
        #expect(work.files == ["public/app.js"] && work.tests.map(\.outcome) == [.passed])
    }

    @Test func skillsAndComputerUseAreFetchedFromThePantry() {
        let session = Session(id: "s", provider: .codex, url: nil, sessionID: "s", title: "t", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
        // Remy's first script listed files, then read a skill's instructions.
        let script: [String: Any] = ["type": "response_item", "payload": ["type": "custom_tool_call", "call_id": "a", "name": "exec",
            "input": #"text(await tools.exec_command({cmd:"rg --files"})); text(await tools.exec_command({cmd:"cat /x/skills/sites-building/SKILL.md"}));"#]]
        // Each command in the script is its own event; the second reads the skill.
        let events = ActivityParser.transcript(script, session: session, id: "1", now: Date()).filter { $0.kind == "toolStarted" }
        #expect(events.map(\.detail) == ["rg --files", "cat /x/skills/sites-building/SKILL.md"])
        let started = events.last
        #expect(KitchenActivity.classify(tool: started?.tool ?? "", detail: started?.detail ?? "") == .resources)
        #expect(KitchenActivity.skillName(started?.detail ?? "") == "sites-building")
        // Listing skill folders is not using a skill.
        #expect(KitchenActivity.classify(tool: "Bash", detail: "ls ~/.claude/skills/*/SKILL.md") == .researching)
        #expect(KitchenActivity.classify(tool: "Read", detail: "/Users/me/.claude/skills/release/SKILL.md") == .resources)
        // Driving the Computer Use plugin from Codex's JavaScript runner.
        let browser: [String: Any] = ["type": "response_item", "payload": ["type": "function_call", "call_id": "b", "name": "js",
            "arguments": #"{"code":"await cua.createBrowserTab('iab','http://localhost:5173')","title":"Preview the clock"}"#]]
        let preview = ActivityParser.transcript(browser, session: session, id: "2", now: Date()).first
        // Looking at the result in a browser is checking the work: tasting, not the pantry.
        #expect(preview?.tool == "computer_use" && KitchenActivity.classify(tool: "computer_use") == .checking)
        #expect(KitchenActivity.classify(tool: "mcp__Claude_Browser__navigate") == .checking)
        #expect(KitchenActivity.classify(tool: "mcp__linear__create_issue") == .resources)
        var work = TurnWork(); work.started(tool: "exec_command", detail: started?.detail ?? "", call: "a")
        #expect(work.resources == ["sites-building"])
    }

    @Test func batteryFindingsAreClassifiedAsTheWorkTheyAre() {
        // Claude edited with a python heredoc; the file text inside is not a test run.
        #expect(KitchenActivity.classify(command: "python3 - <<'EOF'\np='math.js'; s=open(p).read()\n# node test.js\nEOF") == .commands)
        // Looping over files to read them, and asking a tool its version, are reading.
        #expect(KitchenActivity.classify(command: "for p in a b; do if [ -f \"$p\" ]; then cat \"$p\"; fi; done") == .researching)
        #expect(KitchenActivity.classify(command: "cat test.js .gitignore; node --version") == .researching)
        // Fetching the local server checks the work.
        #expect(KitchenActivity.classify(command: "curl -s http://localhost:5191/ | head") == .checking)
        // One file named two ways counts once.
        var work = TurnWork()
        work.started(tool: "Write", detail: "/r/src/stats.js", call: "1")
        work.started(tool: "Bash", detail: "cat > src/stats.js <<'EOF'\nx\nEOF", call: "2")
        #expect(work.files == ["/r/src/stats.js"])
    }
}
