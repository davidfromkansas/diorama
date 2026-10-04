import Foundation
import Testing
@testable import DioramaCore

struct ProjectInboxTests {
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("InboxTests-" + UUID().uuidString) }
    func session(_ provider: Provider = .codex) -> Session {
        Session(id: provider.rawValue + ":s", provider: provider, url: nil, sessionID: "s", title: "Task", project: "/fixture", modified: Date(), bytes: 0, archived: false, parentID: nil)
    }
    @Test func threadingReplayPersistenceAndLateOutputs() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir), seed = Date(timeIntervalSince1970: 100)
        let first = InboxUpdate(id: "s:t1", text: "Done", date: seed.addingTimeInterval(-1))
        #expect(try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [first], historicalBefore: seed))
        #expect(try await store.page(project: "p").unread == 0)
        #expect(try await !store.ingest(project: "p", conversation: "s", title: "Task", updates: [first], historicalBefore: seed))
        var second = InboxUpdate(id: "s:t2", text: "Done again", date: seed.addingTimeInterval(1))
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [second], historicalBefore: seed)
        let page = try await store.page(project: "p")
        #expect(page.rows.count == 1 && page.unread == 1)
        try await store.act("p:s", .read)
        second.outputs = [.init(id: "o", name: "image", kind: "image", location: "/missing.png")]
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [second], historicalBefore: seed)
        #expect(try await store.page(project: "p").unread == 0)
        let restored = ProjectInboxStore(directory: dir)
        #expect(try await restored.detail("p:s").count == 2)
        #expect(try await restored.page(project: "p").rows.first?.attachments == 1)
        // Offline arrivals after first seeding remain unread on a later launch.
        try await restored.ingest(project: "p", conversation: "s", title: "Task", updates: [.init(id: "s:t3", text: "Offline", date: seed.addingTimeInterval(10))], historicalBefore: seed.addingTimeInterval(20))
        #expect(try await restored.page(project: "p").unread == 1)
    }
    @Test func archiveRejectionAndViewedWatermark() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir)
        func update(_ i: Int) -> InboxUpdate { .init(id: "u\(i)", text: "Update", date: Date(timeIntervalSince1970: Double(i))) }
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [update(1)], historicalBefore: .distantPast)
        try await store.act("p:s", .archive)
        #expect(try await store.page(project: "p").rows.isEmpty)
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [update(2)], historicalBefore: .distantPast)
        #expect(try await store.page(project: "p").unread == 1)
        try await store.act("p:s", .read, viewed: ["u1"])
        #expect(try await store.page(project: "p").unread == 1)
        try await store.act("p:s", .reject)
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [update(3)], historicalBefore: .distantPast)
        #expect(try await store.page(project: "p").rows.isEmpty)
        #expect(try await store.page(project: "p", filter: .rejected).rows.count == 1)
        try await store.act("p:s", .restore)
        #expect(try await store.page(project: "p").rows.count == 1)
    }
    @Test func pagingTenThousandSummaries() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir)
        for i in 0..<10_000 {
            try await store.ingest(project: "p", conversation: "s\(i)", title: "Task \(i)", updates: [.init(id: "u\(i)", text: "Fixture output", date: Date(timeIntervalSince1970: Double(i)))], historicalBefore: .distantFuture)
        }
        let start = ContinuousClock.now
        let first = try await store.page(project: "p")
        let elapsed = start.duration(to: .now)
        #expect(first.rows.count == 50 && first.rows.first?.conversation == "s9999")
        let second = try await store.page(project: "p", after: first.next)
        #expect(Set(first.rows.map(\.id)).isDisjoint(with: second.rows.map(\.id)))
        #expect(second.rows.first?.conversation == "s9949")
        print("Inbox 10,000-summary page query: \(elapsed)")
    }
    @Test func codexRequiresTerminalEvidence() throws {
        let data = Data("""
        {"timestamp":"2026-10-01T10:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t"}}
        {"timestamp":"2026-10-01T10:00:01Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello"}]}}
        """.utf8) + Data([10])
        #expect(ProjectInboxHistory.parse(data, session: session()).updates.isEmpty)
        let done = data + Data("{\"timestamp\":\"2026-10-01T10:00:02Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"t\"}}\n".utf8)
        let updates = ProjectInboxHistory.parse(done, session: session()).updates
        #expect(updates.count == 1 && updates.first?.text == "Hello")
        #expect(updates.first?.id == "Codex:s:t")
    }
    @Test func claudeToolUseIsNotCompletion() {
        let lines = """
        {"type":"user","uuid":"u","message":{"content":[{"type":"text","text":"Hi"}]}}
        {"type":"assistant","uuid":"a","timestamp":"2026-10-01T10:00:00Z","message":{"id":"m","stop_reason":"tool_use","content":[{"type":"text","text":"Working"}]}}
        """ + "\n"
        #expect(ProjectInboxHistory.parse(Data(lines.utf8), session: session(.claude)).updates.isEmpty)
        let final = "{\"type\":\"assistant\",\"uuid\":\"b\",\"timestamp\":\"2026-10-01T10:00:02Z\",\"message\":{\"id\":\"n\",\"stop_reason\":\"end_turn\",\"content\":[{\"type\":\"text\",\"text\":\"Done\"}]}}\n"
        let updates = ProjectInboxHistory.parse(Data((lines + final).utf8), session: session(.claude)).updates
        #expect(updates.count == 1)
        #expect(updates.first?.id == "Claude Code:s:n")
        #expect(updates.first?.text.contains("Done") == true)
    }
}

extension ProjectInboxTests {
    @Test func mergedProviderSegmentsAndReadBoundary() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir)
        for (conversation, id) in [("Codex:s", "c"), ("Claude Code:d", "d")] {
            try await store.ingest(project: "p", conversation: conversation, title: "Task", updates: [.init(id: id, text: id, date: Date())], historicalBefore: .distantPast)
        }
        #expect(try await store.merge(project: "p", conversation: "logical", previous: ["Codex:s", "Claude Code:d"]))
        #expect(try await store.page(project: "p").rows.count == 1)
        let detail = try await store.detail("p:logical")
        #expect(detail.count == 2)
        try await store.act("p:logical", .read, through: detail.first?.id)
        #expect(try await store.page(project: "p").unread == 1)
        try await store.act("p:logical", .read, through: detail.last?.id)
        #expect(try await store.page(project: "p").unread == 0)
        #expect(try await ProjectInboxStore(directory: dir).page(project: "p").rows.count == 1)
    }
    @Test func missingTimestampRetainsReceiptAndHistoricalReadState() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir), seed = Date(timeIntervalSince1970: 100)
        let update = InboxUpdate(id: "u", text: "Hello", date: seed.addingTimeInterval(1), received: true)
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [update], historicalBefore: seed, sourceModified: seed.addingTimeInterval(-1))
        #expect(try await store.page(project: "p").unread == 0)
        var replay = update; replay.date = seed.addingTimeInterval(20)
        #expect(try await !store.ingest(project: "p", conversation: "s", title: "Task", updates: [replay], historicalBefore: seed))
        #expect(try await store.page(project: "p").rows.first?.date == update.date)
    }
    @Test func saveFailureDoesNotPretendSuccess() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data("Not a directory".utf8).write(to: dir)
        let store = ProjectInboxStore(directory: dir)
        await #expect(throws: (any Error).self) {
            try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [.init(id: "u", text: "Hello", date: Date())], historicalBefore: .distantPast)
        }
    }
    @Test func failedCallsAndChildContentExcluded() {
        let entry = Entry(id: "failed", kind: "Tool result", text: "Error", timestamp: nil,
                          claude: .init(title: "Write", status: "Failed", outputs: [.init(id: "o", name: "missing", kind: "file")]))
        #expect(InboxUpdate.make(session: session(.claude), turn: "t", entries: [entry], outcome: "failed", date: nil) == nil)
        let child = Entry(id: "child", kind: "Assistant", text: "Child", timestamp: nil, claude: .init(title: "Child", status: "Completed", agentID: "child"))
        #expect(InboxUpdate.make(session: session(.claude), turn: "t", entries: [child], outcome: "completed", date: nil) == nil)
    }
    @Test func sourceTruncationAndStreamingReads() async throws {
        let dir = directory(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.jsonl")
        let records = """
        {"type":"event_msg","payload":{"type":"task_started","turn_id":"t"}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done"}]}}
        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"t"}}
        """ + "\n"
        try Data(records.utf8).write(to: url)
        let source = Session(id: "s", provider: .codex, url: url, sessionID: "s", title: "Fixture", project: "/fixture", modified: Date(), bytes: records.utf8.count, archived: true, parentID: nil)
        let reader = ProjectInboxHistoryReader()
        #expect(await reader.read(source).updates.count == 1)
        #expect(await reader.read(source).updates.isEmpty)
        let shortened = records.replacingOccurrences(of: "Done", with: "D")
        try Data(shortened.utf8).write(to: url)
        #expect(await reader.read(source).updates.first?.text == "D")
    }
}

extension ProjectInboxTests {
    @Test func detailPaginationAndArrivalDuringPaging() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir)
        let updates = (0..<65).map { InboxUpdate(id: "u\($0)", text: "Update \($0)", date: Date(timeIntervalSince1970: Double($0))) }
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: updates, historicalBefore: .distantFuture)
        let page = try await store.detail("p:s")
        #expect(page.count == 20 && page.first?.id == "u45" && page.last?.id == "u64")
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [.init(id: "new", text: "New", date: Date(timeIntervalSince1970: 100))], historicalBefore: .distantFuture)
        let older = try await store.detail("p:s", before: page.first?.id)
        #expect(older.count == 20 && older.last?.id == "u44")
        #expect(try await store.page(project: "p").rows.first?.updates.count == 1)
        #expect(try await store.detail("p:s").last?.id == "new")
    }
    @Test func outputOnlyTerminalTurnAndProviderIdentity() {
        let output = ClaudeOutput(id: "o", name: "report.md", kind: "file", location: "/tmp/report.md")
        let entry = Entry(id: "tool", kind: "Tool result", text: "", timestamp: nil, claude: .init(title: "Write", status: "Completed", outputs: [output]))
        let claude = InboxUpdate.make(session: session(.claude), turn: "same", entries: [entry], outcome: "failed", date: nil)
        let codex = InboxUpdate.make(session: session(), turn: "same", entries: [entry], outcome: "interrupted", date: nil)
        #expect(claude?.text == "" && claude?.outputs.count == 1 && claude?.outcome == "failed")
        #expect(claude?.id != codex?.id && codex?.outcome == "interrupted")
    }
}

extension ProjectInboxTests {
    @Test func savedHistoryCannotReplaceConfirmedInterruptedOutcome() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir)
        var live = InboxUpdate(id: "u", text: "Partial result", date: Date(), outcome: "interrupted")
        live.runtimeOutcome = true
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [live], historicalBefore: .distantPast)
        var saved = live; saved.runtimeOutcome = nil; saved.outcome = "completed"
        saved.outputs = [.init(id: "f", name: "report.md", kind: "file")]
        try await store.ingest(project: "p", conversation: "s", title: "Task", updates: [saved], historicalBefore: .distantPast)
        let detail = try await store.detail("p:s")
        #expect(detail.first?.outcome == "interrupted" && detail.first?.outputs.count == 1)
    }
}

extension ProjectInboxTests {
    @Test func restoreAroundOlderThreadAndUpdateUsesBoundedPages() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir)
        for i in 0..<120 {
            try await store.ingest(project: "p", conversation: "s\(i)", title: "Task", updates: [.init(id: "u\(i)", text: "Output", date: Date(timeIntervalSince1970: Double(i)))], historicalBefore: .distantFuture)
        }
        let restored = try await store.page(project: "p", around: "p:s20")
        #expect(restored.rows.contains { $0.id == "p:s20" })
        #expect(restored.rows.count <= 50)
        let updates = (0..<100).map { InboxUpdate(id: "history-\($0)", text: "Update", date: Date(timeIntervalSince1970: Double($0))) }
        try await store.ingest(project: "p", conversation: "history", title: "History", updates: updates, historicalBefore: .distantFuture)
        let page = try await store.detail("p:history", around: "history-30")
        #expect(page.count <= 20)
        #expect(page.contains { $0.id == "history-30" })
    }
}
