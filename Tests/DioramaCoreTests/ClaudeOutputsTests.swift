import Foundation
import Testing
@testable import DioramaCore

struct ClaudeOutputsTests {
    private func parse(_ records: String) -> Transcript {
        ClaudeNormalizer.parse(Data((records + "\n").utf8), scope: "fixture")
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_ARTIFACT_TRANSCRIPT"] != nil))
    func readsRealArtifactTestTranscript() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["DIORAMA_ARTIFACT_TRANSCRIPT"])
        let transcript = SessionLibrary.readTranscript(url: URL(fileURLWithPath: path), provider: .claude)
        #expect(transcript.error == nil)
        let row = try #require(transcript.entries.first { $0.claude?.title == "Write" })
        #expect(row.claude?.status == "Completed")
        let output = try #require(row.claude?.outputs.first)
        #expect(output.name == "counter.html")
        let preview = try await ClaudeOutputPreview.load(output)
        #expect(preview.kind == "html")
        #expect(String(decoding: preview.data, as: UTF8.self).contains("<button"))
    }
    @Test func splitMessageUsageUpdatesOneCardWithoutDroppingContent() throws {
        let first = #"{"uuid":"a","type":"assistant","message":{"id":"msg1","usage":{"output_tokens":10},"content":[{"type":"text","text":"Checking file"}]}}"#
        let second = #"{"uuid":"b","type":"assistant","message":{"id":"msg1","usage":{"output_tokens":20},"content":[{"type":"tool_use","id":"read1","name":"Read","input":{}}]}}"#
        let initial = try #require(parse(first).entries.first { $0.claude?.category == "usage" })
        let after = parse(first + "\n" + second)
        let usage = after.entries.filter { $0.claude?.category == "usage" }
        #expect(usage.count == 1)
        #expect(usage.first?.id == initial.id)
        #expect(usage.first?.claude?.evidence?["usage"]["output_tokens"].number == 20)
        #expect(after.entries.contains { $0.text == "Checking file" })
        #expect(after.entries.contains { $0.claude?.callID == "read1" })
    }
    @Test func usageWithoutIdentityAndDifferentOwnersStaysSeparate() {
        let record = #"{"uuid":"a","type":"assistant","message":{"id":"shared","usage":{"output_tokens":10},"content":[]}}"#
        let other = record.replacingOccurrences(of: #""uuid":"a""#, with: #""uuid":"b","agentId":"child""#)
        let missing = record.replacingOccurrences(of: #""id":"shared",""#, with: "\"").replacingOccurrences(of: #""uuid":"a""#, with: #""uuid":"c""#)
        #expect(parse(record + "\n" + other + "\n" + missing).entries.filter { $0.claude?.category == "usage" }.count == 3)
    }
    @Test func correlatedArtifactGuidanceKeepsIdentityAndDoesNotBecomeArtifact() throws {
        let call = #"{"uuid":"a","type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Artifact","input":{"action":"quickstart"}}]}}"#
        let result = #"{"uuid":"b","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"Instructions to create a page"}]}}"#
        let before = try #require(parse(call).entries.first)
        let after = try #require(parse(call + "\n" + result + "\n" + result).entries.first)
        #expect(before.id == after.id)
        #expect(after.claude?.title == "Artifact · Quickstart")
        #expect(after.claude?.status == "Completed")
        #expect(after.text == "Instructions to create a page")
        #expect(after.claude?.outputs.isEmpty == true)
        #expect(parse(call + "\n" + result).entries.count == 1)
    }
    @Test func filesRequireSuccessfulStructuredToolEvidence() throws {
        let call = #"{"uuid":"a","cwd":"/tmp/example","type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Write","input":{"file_path":"demo.html"}}]}}"#
        let success = #"{"uuid":"b","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":"Saved"}]}}"#
        let output = try #require(parse(call + "\n" + success).entries.first?.claude?.outputs.first)
        #expect(output.location == "/tmp/example/demo.html")
        #expect(parse(call + "\n" + success.replacingOccurrences(of: "\"content\":\"Saved\"", with: "\"is_error\":true,\"content\":\"Failed\"")).entries.first?.claude?.outputs.isEmpty == true)
        #expect(parse(#"{"uuid":"x","type":"assistant","message":{"content":"I wrote /tmp/demo.html"}}"#).entries.first?.claude == nil)
    }
    @Test func desktopArtifactWithoutActionUsesExplicitFilePath() throws {
        let rows = parse(#"""
        {"uuid":"a","cwd":"/tmp/fixture","type":"assistant","message":{"content":[{"type":"tool_use","id":"artifact","name":"Artifact","input":{"file_path":"page.html","icon":"page","description":"Interactive page"}}]}}
        {"uuid":"b","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"artifact","content":"Published"}]}}
        """#)
        let row = try #require(rows.entries.first)
        #expect(row.claude?.status == "Completed")
        #expect(row.claude?.outputs.first?.location == "/tmp/fixture/page.html")
        #expect(row.claude?.outputs.first?.note == "Artifact · preview shows current file")
    }
    @Test func mixedContentAndOrphanResultsNeverExposeReasoningOrBase64() throws {
        let rows = parse(#"{"uuid":"r","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"missing","content":[{"type":"text","text":"Caption"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"YWJj"}},{"type":"thinking","thinking":"secret"},{"type":"resource_link","name":"Page","uri":"https://example.com/page"}]}]}}"#)
        let row = try #require(rows.entries.first)
        #expect(row.text == "Caption")
        #expect(row.claude?.outputs.count == 2)
        #expect(row.claude?.outputs.first?.encoded == "YWJj")
        #expect(row.claude?.detail.contains("outside") == true)
    }
    @Test func ownershipInterleavingAndUnknownDiagnostics() throws {
        let rows = parse(#"""
        {"uuid":"a","agentId":"one","type":"assistant","message":{"content":[{"type":"tool_use","id":"same","name":"Read","input":{}}]}}
        {"uuid":"b","agentId":"two","type":"assistant","message":{"content":[{"type":"tool_use","id":"same","name":"Write","input":{}}]}}
        {"uuid":"c","agentId":"two","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"same","content":"done"}]}}
        {"uuid":"d","type":"attachment","attachment":{"type":"prompt_snapshot","body":"secret"}}
        {"uuid":"e","type":"future_event","body":"private"}
        """#)
        #expect(rows.entries.count == 3)
        #expect(rows.entries.last?.claude?.category == "unknown")
        #expect(rows.entries[0].claude?.status == "Running")
        #expect(rows.entries[1].claude?.status == "Completed")
        #expect(rows.unrecognizedTypes == ["future_event/future_event": 1])
    }
    @Test func previewEmbedsOnlyBoundedCompanions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = "document.body.dataset.ready='yes'"
        try Data(script.utf8).write(to: root.appendingPathComponent("app.js"))
        let page = root.appendingPathComponent("page.html")
        try Data("<html><script src='app.js'></script><img src='https://example.invalid/a.png'></html>".utf8).write(to: page)
        let preview = try await ClaudeOutputPreview.load(.init(id: "p", name: "Page", kind: "file", location: page.path))
        #expect(preview.kind == "html")
        #expect(String(decoding: preview.data, as: UTF8.self).contains(script))
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("outside secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.js"), withDestinationURL: outside)
        #expect(throws: (any Error).self) { try ClaudeOutputPreview.embedAssets("<script src='escape.js'></script>", root: root) }
        let traversal = try ClaudeOutputPreview.embedAssets("<script src='../\(outside.lastPathComponent)'></script>", root: root)
        #expect(!traversal.contains("outside secret"))
        await #expect(throws: (any Error).self) { try await ClaudeOutputPreview.load(.init(id: "r", name: "Remote", kind: "resource", location: "https://example.invalid/page")) }
        #expect(ClaudeOutputPreview.externalURL(.init(id: "x", name: "x", kind: "resource", location: "javascript:alert(1)")) == nil)
    }
}
