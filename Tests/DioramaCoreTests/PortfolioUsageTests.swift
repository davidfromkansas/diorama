import Foundation
import Testing
@testable import DioramaCore

struct PortfolioUsageTests {
    private func wire(_ value: String) throws -> WireValue { try JSONDecoder().decode(WireValue.self, from: Data(value.utf8)) }
    private func source(_ url: URL, provider: Provider = .codex) -> Session {
        Session(id: provider.rawValue + ":usage-test", provider: provider, url: url, sessionID: "usage-test", title: "Usage test", project: url.deletingLastPathComponent().path, modified: Date(), bytes: 0, archived: false, parentID: nil)
    }
    @Test func cumulativeReportsReplaceAndCachedInputIsNotAddedAgain() throws {
        var ledger = PortfolioUsageLedger()
        let first = try wire(#"{"input_tokens":100,"output_tokens":20,"cached_input_tokens":90}"#)
        ledger.ingestCumulative(first, provider: .codex, at: nil)
        ledger.ingestCumulative(first, provider: .codex, at: nil)
        ledger.ingestResponse(first, id: "same", provider: .codex, at: nil)
        #expect(ledger.total == 120)
        ledger.ingestCumulative(try wire(#"{"totalTokens":180}"#), provider: .codex, at: nil)
        ledger.ingestCumulative(first, provider: .codex, at: nil)
        #expect(ledger.total == 180)
    }
    @Test func claudeMessageRevisionsAndAlternativeResultScopesDoNotDoubleCount() throws {
        var ledger = PortfolioUsageLedger()
        let row = try wire(#"{"type":"assistant","message":{"id":"msg-1","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":40}}}"#)
        ledger.ingest(row, provider: .claude); ledger.ingest(row, provider: .claude)
        #expect(ledger.total == 100)
        ledger.ingestResponse(try wire(#"{"input_tokens":10,"output_tokens":30}"#), id: "msg-2", provider: .claude, at: nil)
        #expect(ledger.total == 140)
        ledger.ingestResponse(try wire(#"{"input_tokens":100,"output_tokens":40}"#), id: "turn-1", provider: .claude, result: true, at: nil)
        #expect(ledger.total == 140)
        #expect(ledger.partial)
    }
    @Test func missingUsageIsNotZeroAndUnscopedResponsesAreNotInvented() throws {
        var ledger = PortfolioUsageLedger()
        #expect(ledger.total == nil)
        ledger.ingestResponse(try wire(#"{"input_tokens":1,"output_tokens":2}"#), id: nil, provider: .claude, at: nil)
        #expect(ledger.total == nil && ledger.partial)
        ledger.ingestCumulative(try wire(#"{"totalTokens":0}"#), provider: .codex, at: nil)
        #expect(ledger.total == 0)
    }
    @Test func indexFollowsAppendRebuildTruncationAndMissingFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("session.jsonl"), cache = root.appendingPathComponent("cache.json")
        let first = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":20}}}}"# + "\n"
        try Data(first.utf8).write(to: url)
        let session = source(url), key = PortfolioUsageIndex.identity(session)
        let index = PortfolioUsageIndex(cache: cache)
        let initial = await index.read([session])
        #expect(initial[key]?.ledger.total == 120)
        let append = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":240}}}}"# + "\n"
        let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd(); try handle.write(contentsOf: Data(append.utf8)); try handle.close()
        let updated = await index.read([session])
        #expect(updated[key]?.ledger.total == 240)
        let restored = await PortfolioUsageIndex(cache: cache).read([session])
        #expect(restored[key]?.ledger.total == 240)
        let rebuilt = await PortfolioUsageIndex().read([session])
        #expect(rebuilt[key]?.ledger.total == 240)
        try Data(first.utf8).write(to: url)
        let truncated = await index.read([session])
        #expect(truncated[key]?.ledger.total == 240)
        #expect(truncated[key]?.summary.coverage == .partial)
        try FileManager.default.removeItem(at: url)
        let missing = await index.read([session])
        #expect(missing[key]?.ledger.total == 240)
        #expect(missing[key]?.summary.coverage == .partial)
        let restarted = PortfolioUsageIndex(cache: cache)
        let restoredSessions = await restarted.cachedSessions()
        let missingAfterRestart = await restarted.read(restoredSessions)
        #expect(missingAfterRestart[key]?.ledger.total == 240)
        #expect(missingAfterRestart[key]?.summary.coverage == .partial)
    }
    @Test func oversizedArtifactLinesDoNotBlockLaterUsage() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let artifact = "{\"artifact\":\"" + String(repeating: "x", count: 9 * 1024 * 1024) + "\"}\n"
        let usage = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":250}}}}"# + "\n"
        try Data((artifact + usage).utf8).write(to: url)
        let session = source(url), key = PortfolioUsageIndex.identity(session), index = PortfolioUsageIndex()
        let first = await index.read([session])
        #expect(first[key]?.loading == true)
        let second = await index.read([session])
        #expect(second[key]?.ledger.total == 250)
        #expect(second[key]?.summary.coverage == .partial)
    }
    @Test func incompleteJSONIsRetriedAndClaudeChildrenHaveSeparateSourceIDs() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let prefix = #"{"type":"assistant","message":{"id":"msg-1","usage":{"input_tokens":10,"output_tokens":20}}}"#
        try Data(prefix.utf8).write(to: url)
        let session = source(url, provider: .claude), index = PortfolioUsageIndex()
        let key = PortfolioUsageIndex.identity(session)
        let before = await index.read([session]); #expect(before[key]?.ledger.total == nil)
        let file = try FileHandle(forWritingTo: url); try file.seekToEnd(); try file.write(contentsOf: Data("\n".utf8)); try file.close()
        let after = await index.read([session]); #expect(after[key]?.ledger.total == 30)
        var child = Session(id: "child", provider: .claude, url: url, sessionID: session.sessionID, title: "Child", project: session.project, modified: Date(), bytes: 0, archived: false, parentID: session.sessionID)
        child.classification = .subagent
        #expect(PortfolioUsageIndex.identity(child) != key)
    }
    @Test func recentDaysSplitInputAndOutputWithoutDoubleCounting() throws {
        let now = Date(), old = now.addingTimeInterval(-10 * 86_400), yesterday = now.addingTimeInterval(-86_400)
        var codex = PortfolioUsageLedger()
        codex.ingestCumulative(try wire(#"{"input_tokens":100,"cached_input_tokens":90,"output_tokens":10}"#), provider: .codex, at: old)
        codex.ingestCumulative(try wire(#"{"input_tokens":300,"cached_input_tokens":250,"output_tokens":40}"#), provider: .codex, at: yesterday)
        codex.ingestCumulative(try wire(#"{"input_tokens":300,"cached_input_tokens":250,"output_tokens":40}"#), provider: .codex, at: now)
        #expect(codex.recent(days: 7, now: now) == TokenSplit(input: 200, output: 30))
        #expect(codex.total == 340)
        var claude = PortfolioUsageLedger()
        let row = try wire("{\"timestamp\":\"\(ISO8601DateFormatter().string(from: now))\",\"type\":\"assistant\",\"message\":{\"id\":\"m\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20,\"cache_read_input_tokens\":30,\"cache_creation_input_tokens\":40}}}")
        claude.ingest(row, provider: .claude); claude.ingest(row, provider: .claude)
        #expect(claude.recent(days: 7, now: now) == TokenSplit(input: 80, output: 20))
        #expect(claude.recent(days: 1, now: now.addingTimeInterval(3 * 86_400)) == TokenSplit())
        #expect(claude.total == 100)
    }
}
