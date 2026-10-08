import Testing
@testable import DioramaCore

struct CodeModeResourceTests {
    /// Rose's script: a plugin skill fetched by MCP resource, then a web read, in one code-mode call.
    let rose = #"text(await tools.read_mcp_resource({server:"codex_apps",uri:"skill://plugin_connector_690a90ec05c881918afb6a55dc9bbaa1/domains"})); text(await tools.web__run({open:[{ref_id:"https://vercel.com/docs"}]}));"#

    @Test func codeModeResourceReadsGoToThePantry() {
        let calls = ActivityParser.codeModeCalls(rose)
        #expect(calls.map(\.tool) == ["read_mcp_resource", "web__run"])
        #expect(calls[0].detail == "skill://plugin_connector_690a90ec05c881918afb6a55dc9bbaa1/domains")
        #expect(KitchenActivity.classify(tool: "read_mcp_resource", detail: calls[0].detail ?? "") == .resources)
        #expect(KitchenActivity.classify(tool: "list_mcp_resources", detail: "") == .resources)
        #expect(KitchenActivity.classify(tool: "list_mcp_resource_templates", detail: "") == .resources)
    }

    @Test func theTurnRemembersTheSkillByItsURI() {
        var work = TurnWork()
        work.started(tool: "read_mcp_resource", detail: "skill://plugin_connector_690a/domains", call: "c1")
        #expect(work.resources == ["skill://plugin_connector_690a/domains"])
    }
}

struct TestCommandTests {
    @Test func testRunnersCountOnlyAsTheCommandRun() {
        #expect(KitchenActivity.classify(tool: "exec_command", detail: "python3 -m unittest discover -v") == .testing)
        #expect(KitchenActivity.classify(tool: "exec_command", detail: "cd app && npx vitest run") == .testing)
        #expect(KitchenActivity.classify(tool: "Bash", detail: "FOO=1 uv run pytest -q") == .testing)
        // Naming a test file or config in arguments isn't running tests.
        #expect(KitchenActivity.classify(tool: "commandExecution", detail: "/bin/zsh -lc pwd; rg --files -g '*test*' -g 'pytest.ini'") == .researching)
        #expect(KitchenActivity.classify(tool: "exec_command", detail: "cat test_textutils.py") == .researching)
    }
}
