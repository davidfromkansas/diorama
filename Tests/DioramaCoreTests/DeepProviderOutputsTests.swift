import Foundation
import Testing
@testable import DioramaCore

struct DeepCodexOutputTests {
    func parse(_ text: String) -> Transcript { CodexTranscriptNormalizer.parse(Data((text + "\n").utf8), scope: "fixture", start: 0, limit: 300) }
    @Test func dottedSearchAndUsageRemainInspectable() throws {
        let rows = parse(#"""
        {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"Extension","kind":"web.search","id":"search","query":"capybara anatomy","results":[{"url":"https://example.com","title":"Reference"}]}}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10},"total_token_usage":{"input_tokens":500,"output_tokens":80}}}}
        {"type":"event_msg","payload":{"type":"future_event","body":"visible evidence"}}
        """#)
        #expect(rows.entries[0].tool?.type == "webSearch")
        #expect(rows.entries[0].tool?.item["results"].array.count == 1)
        #expect(rows.entries[1].codex?.usage["input_tokens"].number == 100)
        #expect(rows.entries[1].codex?.cumulativeUsage["input_tokens"].number == 500)
        #expect(rows.entries[2].codex?.category == "unknown")
        #expect(rows.unrecognizedTypes["event/future_event"] == 1)
    }
    @Test func nativeMessagesDoNotEraseDistinctAssistantOutput() {
        let rows = parse(#"""
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Distinct commentary"}]}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Final answer"}]}}
        {"type":"event_msg","payload":{"type":"item_completed","item":{"type":"AgentMessage","id":"final","content":[{"type":"Text","text":"Final answer"}]}}}
        """#)
        #expect(rows.entries.map(\.text) == ["Distinct commentary", "Final answer"])
    }
    @Test func nativeHistoryNormalizesSearchAndCapitalizedUserText() throws {
        let result = try AppServerHistory.transcript(["turns": [["id": "t", "items": [["type": "Extension", "kind": "web.search", "id": "s", "query": "reference"], ["type": "UserMessage", "id": "u", "content": [["type": "Text", "text": "Question"]]]]]]], limit: 300)
        #expect(result.entries[0].codex?.category == "webSearch")
        #expect(result.entries.last?.text == "Question")
        #expect(result.entries.count == 2)
    }
}
struct DeepClaudeOutputTests {
    @Test func savedSessionUsageAndModeKeepNativeSemantics() {
        let text = #"""
        {"type":"mode","mode":"normal"}
        {"type":"cost-state","totalCostUSD":0.25,"totalDuration":7100,"totalAPIDuration":3200,"hasUnknownModelCost":true,"modelUsage":{"fixture-model":{"inputTokens":2,"outputTokens":23,"cacheReadInputTokens":100,"cacheCreationInputTokens":200}}}
        """# + "\n"
        let transcript = ClaudeNormalizer.parse(Data(text.utf8), scope: "fixture")
        #expect(transcript.unrecognizedTypes.isEmpty)
        #expect(transcript.entries.first?.text == "Reported mode: normal")
        let usage = transcript.entries.last?.claude
        #expect(usage?.category == "sessionUsage")
        #expect(usage?.evidence?["totalCostUSD"].number == 0.25)
        #expect(usage?.evidence?["modelUsage"]["fixture-model"]["cacheReadInputTokens"].number == 100)
        #expect(usage?.evidence?["usage"] == .null)
    }
    @Test func preservesProviderSpecificMetricsProgressAndAttachments() {
        let text = #"""
        {"type":"result","uuid":"r","usage":{"input_tokens":10,"cache_read_input_tokens":40,"cache_creation_input_tokens":5,"output_tokens":3},"total_cost_usd":0.01,"duration_ms":800}
        {"type":"progress","uuid":"p","data":{"type":"bash_progress","elapsedTimeSeconds":2,"output":"building"}}
        {"type":"attachment","uuid":"a","attachment":{"type":"future_artifact","name":"model"}}
        {"type":"attachment","uuid":"secret","attachment":{"type":"prompt_snapshot","body":"private"}}
        """# + "\n"
        let rows = ClaudeNormalizer.parse(Data(text.utf8), scope: "fixture")
        #expect(rows.entries.count == 3)
        #expect(rows.entries[0].claude?.evidence?["usage"]["cache_read_input_tokens"].number == 40)
        #expect(rows.entries[0].claude?.evidence?["total_cost_usd"].number == 0.01)
        #expect(rows.entries[1].claude?.category == "progress")
        #expect(rows.entries[2].claude?.outputs.isEmpty == true)
        #expect(rows.unrecognizedTypes["attachment/future_artifact"] == 1)
    }
    @Test func requestResultResolvesInsteadOfRemainingWaiting() {
        let text = #"""
        {"uuid":"q","type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{"questions":[]}}]}}
        {"uuid":"a","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q1","content":"GLB"}]}}
        """# + "\n"
        let rows = ClaudeNormalizer.parse(Data(text.utf8), scope: "fixture")
        #expect(rows.entries.first?.claude?.status == "Resolved")
        #expect(rows.entries.first?.text == "GLB")
    }
}
struct SourceRecordTests {
    @Test(arguments: [Provider.codex, .claude])
    func passiveObserverRetainsLoadableSourceAcrossAppends(_ provider: Provider) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let row = provider == .codex
            ? #"{"type":"response_item","payload":{"type":"message","id":"m","role":"assistant","content":[{"type":"output_text","text":"Source marker"}]}}"#
            : #"{"type":"assistant","uuid":"m","message":{"content":[{"type":"text","text":"Source marker"}]}}"#
        try Data(("\n\n" + row + "\n").utf8).write(to: url)
        let session = Session(id: "provider:source-test", provider: provider, url: url, sessionID: "source-test", title: "Fixture", project: url.deletingLastPathComponent().path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        let observer = ExternalSessionObserver()
        let first = await observer.read(session, hookDirectory: nil)
        let entry = try #require(first.transcript.entries.first)
        let source = try #require(entry.sourceRecords?.first)
        #expect(source.offset == 2)
        #expect(try await source.load(characterLimit: 4096).contains("Source marker"))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("\n".utf8)); try handle.close()
        let appended = await observer.read(session, hookDirectory: nil)
        #expect(appended.transcript.entries.first?.id == entry.id)
        #expect(try await source.load(characterLimit: 4096).contains("Source marker"))
    }
    @Test func loadsMoreAndRejectsReplacedSource() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try JSONSerialization.data(withJSONObject: ["type": "tool_result", "text": String(repeating: "a", count: 3000), "content": [["type": "thinking", "thinking": "private"], ["type": "image", "source": ["type": "base64", "data": "SECRET_MEDIA"]]]])
        try data.write(to: url)
        let reference = try #require(TranscriptSource(path: url.path, offset: 0, record: data))
        let small = try await reference.load(characterLimit: 1024)
        #expect(small.contains("More source content available"))
        let full = try await reference.load(characterLimit: 8000)
        #expect(!full.contains("More source content available"))
        #expect(!full.contains("SECRET_MEDIA")); #expect(!full.contains("private"))
        try Data("{}".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await reference.load(characterLimit: 8000) }
    }
    @Test func oldEntryDecodesWithoutNewProviderPayloads() throws {
        let entry = try JSONDecoder().decode(Entry.self, from: Data(#"{"id":"old","kind":"Assistant","text":"Readable"}"#.utf8))
        #expect(entry.codex == nil); #expect(entry.claude == nil); #expect(entry.sourceRecords == nil)
    }
}

struct NativeCodexActivityTests {
    @Test func nativeOutcomesWinAndTurnsSurviveIncrementalChunks() {
        let session = Session(id: "Codex:s", provider: .codex, url: nil, sessionID: "s", title: "Fixture", project: "/tmp", modified: .distantPast, bytes: 0, archived: false, parentID: nil)
        var state = SessionActivitySnapshot()
        func append(_ text: String) { SessionActivityHistory.append(Data((text + "\n").utf8), session: session, into: &state) }
        append(#"{"type":"turn_context","payload":{"turn_id":"one"}}"#)
        append(#"{"type":"event_msg","timestamp":"2026-09-27T00:00:00Z","payload":{"type":"item_completed","item":{"type":"CommandExecution","id":"call","status":"failed","exit_code":1}}}"#)
        append(#"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call","output":"returned"}}"#)
        #expect(state.records.first?.status == "failed")
        #expect(state.records.first?.recordedAt != nil)
        append(#"{"type":"turn_context","payload":{"turn_id":"two"}}"#)
        append(#"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call","output":"returned"}}"#)
        #expect(state.records.count == 2)
        #expect(state.records.last?.status == "Returned")
        #expect(state.records.last?.turnID == "two")
    }
}
