import Foundation
import Testing
@testable import DioramaCore

struct CodexOutputsTests {
    private func parse(_ lines: String, start: UInt64 = 0) -> Transcript {
        CodexTranscriptNormalizer.parse(Data((lines + "\n").utf8), scope: "test", start: start, limit: 300)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_CODEX_OUTPUT_TRANSCRIPT"] != nil))
    func designatedLiveCLIOutputCanBePreviewed() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["DIORAMA_CODEX_OUTPUT_TRANSCRIPT"])
        let transcript = SessionLibrary.readTranscript(url: URL(fileURLWithPath: path), provider: .codex)
        #expect(transcript.error == nil)
        let file = try #require(transcript.entries.compactMap(\.tool).flatMap(\.outputs).first { $0.name == "codex-counter.html" })
        #expect(try await ClaudeOutputPreview.load(file).kind == "html")
        #expect(transcript.entries.contains { $0.tool?.type == "commandExecution" })
        #expect(transcript.state == "Last turn finished")
        #expect(transcript.entries.contains { $0.kind == "Assistant" && $0.text.contains("blue increment button") })
    }
    @Test func persistedCapitalizedTextBlocksRemainReadable() throws {
        let transcript = parse(#"""
        {"type":"event_msg","payload":{"type":"item_completed","turn_id":"t","item":{"type":"UserMessage","id":"user","content":[{"type":"Text","text":"Create a counter"}]}}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Created the counter"}]}}
        {"type":"event_msg","payload":{"type":"item_started","turn_id":"t","item":{"type":"AgentMessage","id":"answer","content":[]}}}
        {"type":"event_msg","payload":{"type":"item_completed","turn_id":"t","item":{"type":"AgentMessage","id":"answer","content":[{"type":"Text","text":"Created the counter"}]}}}
        """#)
        #expect(transcript.entries.map(\.text) == ["Create a counter", "Created the counter"])
        #expect(transcript.entries.allSatisfy { $0.tool == nil })
        let history = try AppServerHistory.transcript(["turns": [["id": "t", "items": [["id": "answer", "type": "AgentMessage", "content": [["type": "Text", "text": "Created the counter"]]]]]]], limit: 300)
        #expect(history.entries.first?.text == "Created the counter")
    }
    @Test func sourceErrorsAndPlanInputsRemainExplicit() throws {
        let failure = try #require(ToolResult(item: CodexOutputEvidence.wire(["type": "mcpToolCall", "status": "completed", "result": ["isError": true, "content": [["type": "text", "text": "Permission refused"]]]])))
        #expect(failure.status == "failed")
        let plan = try #require(ToolResult(item: CodexOutputEvidence.wire(["type": "functionCall", "name": "update_plan", "arguments": "{\"plan\":[{\"step\":\"Inspect\",\"status\":\"completed\"}]}"])))
        #expect(plan.planSteps.first?["step"].string == "Inspect")
    }
    @Test func nativeItemsExposeFilesCommandsAndDeduplicateMCP() throws {
        let transcript = parse(#"""
        {"type":"turn_context","payload":{"turn_id":"turn","cwd":"/tmp/example"}}
        {"type":"response_item","payload":{"type":"function_call","call_id":"mcp","name":"mcp__test","arguments":"{}"}}
        {"type":"response_item","payload":{"type":"function_call_output","call_id":"mcp","output":"Duplicate result"}}
        {"type":"event_msg","payload":{"type":"item_completed","turn_id":"turn","item":{"type":"McpToolCall","id":"mcp","server":"test","tool":"read","status":"completed","result":{"content":[{"type":"text","text":"Authoritative result"}]}}}}
        {"type":"event_msg","payload":{"type":"item_completed","turn_id":"turn","item":{"type":"CommandExecution","id":"command","command":"echo done","status":"completed","aggregated_output":"done","exit_code":0,"duration":{"secs":1,"nanos":500000000}}}}
        {"type":"event_msg","payload":{"type":"item_completed","turn_id":"turn","item":{"type":"FileChange","id":"patch","status":"completed","changes":{"page.html":{"type":"add","unified_diff":"+<html>fixture</html>"}}}}}
        """#)
        #expect(transcript.entries.count == 3)
        #expect(transcript.entries[0].tool?.output == "Authoritative result")
        #expect(transcript.entries[1].tool?.item["durationMs"].number == 1500)
        #expect(transcript.entries[2].tool?.outputs.first?.location == "/tmp/example/page.html")
        #expect(transcript.entries[2].tool?.item["changes"].array.first?["diff"].string == "+<html>fixture</html>")
    }
    @Test func callResultsUpdateSameCardWithoutLosingIdentity() throws {
        let call = #"{"type":"response_item","payload":{"type":"function_call","call_id":"call","name":"test","arguments":"{}"}}"#
        let result = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call","output":[{"type":"input_text","text":"A result"},{"type":"input_image","image_url":"data:image/png;base64,YWJj"}]}}"#
        let before = try #require(parse(call).entries.first)
        let after = try #require(parse(call + "\n" + result).entries.first)
        #expect(before.id == after.id)
        #expect(after.tool?.status == "Returned")
        #expect(after.tool?.output == "A result")
        #expect(after.tool?.outputs.first?.encoded == "YWJj")
        #expect(after.tool?.rawPreview.contains("YWJj") == false)
        #expect(parse(result).entries.first?.tool?.output == "A result")
    }
    @Test func sourceUpdatesAndTurnScopesRemainSeparate() throws {
        let rows = parse(#"""
        {"type":"event_msg","payload":{"type":"item_started","turn_id":"one","item":{"type":"CommandExecution","id":"same","command":"echo first","status":"inProgress"}}}
        {"type":"event_msg","payload":{"type":"item_completed","turn_id":"one","item":{"type":"CommandExecution","id":"same","command":"echo first","status":"completed","aggregated_output":"first"}}}
        {"type":"event_msg","payload":{"type":"item_completed","turn_id":"two","item":{"type":"CommandExecution","id":"same","command":"echo second","status":"failed","exit_code":1}}}
        """#)
        #expect(rows.entries.count == 2)
        #expect(rows.entries[0].tool?.status == "completed")
        #expect(rows.entries[1].tool?.status == "failed")
        #expect(rows.entries[0].id != rows.entries[1].id)
    }
    @Test func unsupportedItemsPreserveAppServerHistoryAndStableRows() throws {
        let known: [String: Any] = ["id": "message", "type": "agentMessage", "text": "Readable"]
        let unknown: [String: Any] = ["id": "future", "type": "futureFormat", "privateBody": "secret"]
        let a = try AppServerHistory.transcript(["turns": [["id": "t", "items": [known]]]], limit: 300)
        let b = try AppServerHistory.transcript(["turns": [["id": "t", "items": [unknown, known]]]], limit: 300)
        #expect(b.entries.last?.id == a.entries.first?.id)
        #expect(b.entries.last?.text == "Readable")
        #expect(b.unrecognizedTypes == ["item/futureFormat": 1])
        #expect(b.entries.first?.text.contains("secret") == false)
    }
    @Test func dynamicMixedOutputsAndReasoningRedaction() throws {
        let tool = try #require(ToolResult(item: CodexOutputEvidence.wire([
            "type": "dynamicToolCall", "id": "dynamic", "tool": "draw", "status": "completed",
            "contentItems": [["type": "inputText", "text": "Caption"], ["type": "inputImage", "imageUrl": "data:image/png;base64,YWJj"], ["type": "inputAudio", "audioUrl": "data:audio/wav;base64,YWJj"]]
        ])))
        #expect(tool.output == "Caption")
        #expect(tool.outputs.count == 2)
        #expect(tool.outputs.last?.kind == "unsupported")
        #expect(!tool.rawPreview.contains("YWJj"))
        let hidden = parse(#"""
        {"type":"response_item","payload":{"type":"reasoning","encrypted_content":"secret"}}
        {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"Reasoning","id":"hidden","raw_content":"secret"}}}
        """#)
        #expect(hidden.entries.isEmpty)
    }
    @Test func embeddedResourcesPreviewOnlyOnRequestAndFailedChangesHaveNoOutput() async throws {
        let tool = try #require(ToolResult(item: CodexOutputEvidence.wire(["type": "mcpToolCall", "id": "m", "server": "fixture", "tool": "page", "result": ["content": [["type": "resource", "resource": ["uri": "artifact://page", "mimeType": "text/html", "text": "<html><button>Click</button></html>"]]]]])))
        let output = try #require(tool.outputs.first)
        #expect(try await ClaudeOutputPreview.load(output).kind == "html")
        #expect(ClaudeOutputPreview.externalURL(output) == nil)
        let failed = try #require(ToolResult(item: CodexOutputEvidence.wire(["type": "fileChange", "status": "failed", "changes": [["path": "/tmp/x.html", "kind": ["type": "add"]]]])))
        #expect(failed.outputs.isEmpty)
    }
    @Test func inlineImageDataURIsAndOutputListsStayBounded() throws {
        let tool = try #require(ToolResult(item: CodexOutputEvidence.wire(["type": "imageGeneration", "id": "image", "result": "data:image/png;base64,YWJj"])))
        #expect(tool.outputs.first?.encoded == "YWJj")
        #expect(!tool.rawPreview.contains("YWJj"))
        let blocks = Array(repeating: CodexOutputEvidence.wire(["type": "resource_link", "name": "Output", "uri": "https://example.com"]), count: 101)
        let outputs = CodexOutputEvidence.outputs(blocks, id: "test")
        #expect(outputs.count == 101)
        #expect(outputs.last?.kind == "unsupported")
        #expect(outputs.last?.name == "Additional outputs omitted")
    }
    @Test func fallbackIDsUseByteOffsetsAndIgnoreIncompleteLines() {
        let first = #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":"First"}}"# + "\n"
        let second = #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":"Second"}}"#
        #expect(parse(first + second).entries.last?.id == parse(second, start: UInt64(first.utf8.count)).entries.first?.id)
        let incomplete = CodexTranscriptNormalizer.parse(Data(second.utf8), scope: "test", start: 0, limit: 300)
        #expect(incomplete.entries.isEmpty)
    }
}
