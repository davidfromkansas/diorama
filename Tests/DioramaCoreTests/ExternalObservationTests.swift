import Foundation
import Testing
@testable import DioramaCore

struct ExternalObservationTests {
    private func fixture() throws -> (URL, Session) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try Data().write(to: url)
        return (url, Session(id: "Codex:external", provider: .codex, url: url, sessionID: "external", title: "External", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil))
    }
    private func append(_ text: String, to url: URL) throws {
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
        try file.seekToEnd(); try file.write(contentsOf: Data(text.utf8))
    }
    @Test func appendPartialReplacementAndMissingFilePreserveHistory() async throws {
        let (url, session) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let observer = ExternalSessionObserver()
        let message = #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"first"}]}}"# + "\n"
        try append(message, to: url)
        let first = await observer.read(session, hookDirectory: nil)
        #expect(first.transcript.entries.contains { $0.text == "first" })
        try append(String(message.dropLast()), to: url)
        let partial = await observer.read(session, hookDirectory: nil)
        #expect(partial.transcript.entries == first.transcript.entries)
        try append("\n", to: url)
        let complete = await observer.read(session, hookDirectory: nil)
        #expect(complete.transcript.entries.count == first.transcript.entries.count + 1)
        try Data(message.replacingOccurrences(of: "first", with: "replacement").utf8).write(to: url, options: .atomic)
        let replaced = await observer.read(session, hookDirectory: nil)
        #expect(replaced.transcript.entries.count == 1)
        #expect(replaced.transcript.entries.first?.text == "replacement")
        try FileManager.default.removeItem(at: url)
        let missing = await observer.read(session, hookDirectory: nil)
        #expect(missing.error != nil)
        #expect(missing.transcript.entries == replaced.transcript.entries)
        #expect(missing.lastSuccessfulSynchronization == replaced.lastSuccessfulSynchronization)
    }
    @Test func freshnessUsesSourceTimeAndExpiresWithoutNewReads() async throws {
        let (url, session) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = ISO8601DateFormatter().string(from: now)
        try append("{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"a\"}}\n", to: url)
        let observer = ExternalSessionObserver()
        let first = await observer.read(session, now: now, hookDirectory: nil)
        #expect(first.activity.state == .working)
        #expect(first.isRecent(at: now.addingTimeInterval(29)))
        #expect(!first.isRecent(at: now.addingTimeInterval(30)))
        let reread = await observer.read(session, now: now.addingTimeInterval(60), hookDirectory: nil)
        #expect(!reread.isRecent(at: now.addingTimeInterval(60)))
    }
    @Test func delayedOldTurnToolCannotReviveFinishedCurrentTurn() {
        let now = Date()
        func event(_ id: String, _ kind: String, _ turn: String, _ state: ActivityState, _ offset: Double) -> ActivityEvent {
            .init(id: id, provider: "Codex", sessionID: "s", kind: kind, source: "Fixture", recordedAt: now.addingTimeInterval(offset), turnID: turn, state: state)
        }
        let summary = ActivitySummary.merged([
            event("1", "started", "old", .working, 0), event("2", "started", "current", .working, 1),
            event("3", "finished", "current", .finished, 2), event("4", "toolStarted", "old", .working, 3)
        ])
        #expect(summary.state == .finished)
    }

    @Test func structuredActivityRefreshesAfterFirstRead() async throws {
        let (url, base) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let session = Session(id: "Claude Code:external", provider: .claude, url: url, sessionID: base.sessionID, title: base.title, project: base.project, modified: Date(), bytes: 0, archived: false, parentID: nil)
        let observer = ExternalSessionObserver()
        _ = await observer.read(session, hookDirectory: nil)
        try append(#"{"type":"assistant","timestamp":"2026-09-26T10:00:00Z","message":{"content":[{"type":"tool_use","id":"read1","name":"Read","input":{"file_path":"README.md"}}]}}"# + "\n", to: url)
        let started = await observer.read(session, hookDirectory: nil)
        #expect(started.structured.records.contains { $0.nativeID == "read1" && $0.status == "running" })
        try append(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"read1","content":"done"}]}}"# + "\n", to: url)
        let ended = await observer.read(session, hookDirectory: nil)
        #expect(ended.structured.records.contains { $0.nativeID == "read1" && $0.status == "completed" })
    }
    @Test func parentLifecycleSurvivesChildReadsAndLargeQuietTail() async throws {
        let (url, base) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let childURL = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".jsonl")
        try Data().write(to: childURL); defer { try? FileManager.default.removeItem(at: childURL) }
        let parent = Session(id: "Claude:parent", provider: .claude, url: url, sessionID: "parent", title: "Parent", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let child = Session(id: "Claude:child", provider: .claude, url: childURL, sessionID: base.sessionID, title: "Child", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: "parent")
        let observer = ExternalSessionObserver()
        try append(#"{"type":"user","message":{"content":"Start"}}"# + "\n", to: url)
        let started = await observer.read(parent, hookDirectory: nil)
        #expect(started.activity.state == .working)
        let quietLine = #"{"type":"progress","padding":""# + String(repeating: "x", count: 2048) + #""}"# + "\n"
        try append(String(repeating: quietLine, count: 350), to: url)
        _ = await observer.read(child, hookDirectory: nil)
        let reread = await observer.read(parent, hookDirectory: nil)
        #expect(reread.activity.state == .working)
        #expect(reread.activity.latestState?.id == started.activity.latestState?.id)
    }

    @Test func largeHistoryAppendLatencyAndStableEntries() async throws {
        let (url, session) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let line = #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":""# + String(repeating: "history ", count: 100) + #""}]}}"# + "\n"
        try append(String(repeating: line, count: 8000), to: url)
        let observer = ExternalSessionObserver()
        let initial = await observer.read(session, hookDirectory: nil)
        var timings: [Double] = []
        for _ in 0..<5 {
            try append(line, to: url)
            let start = Date()
            let updated = await observer.read(session, hookDirectory: nil)
            timings.append(Date().timeIntervalSince(start))
            #expect(updated.transcript.entries.count == 300)
            #expect(updated.transcript.entries.last?.id != initial.transcript.entries.last?.id)
        }
        print("VIEWER_LONG_HISTORY append_max_ms=\(timings.max()! * 1000)")
        #expect(timings.max()! < 0.5, "Observer parsing must leave time for presentation within 500ms")
    }

    @Test func claudeQuestionAndAnswerWorkWithoutHooks() async throws {
        let (url, base) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let session = Session(id: "Claude:question", provider: .claude, url: url, sessionID: base.sessionID, title: "Question", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let observer = ExternalSessionObserver()
        try append(#"{"type":"assistant","timestamp":"2026-09-26T13:00:00Z","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}"# + "\n", to: url)
        let waiting = await observer.read(session, hookDirectory: nil)
        #expect(waiting.activity.state == .input)
        #expect(waiting.activity.attention.count == 1)
        let generic = ActivityEvent(id: "notification", provider: "Claude Code", sessionID: base.sessionID, kind: "approval", source: "Hook", recordedAt: ActivityParser.date("2026-09-26T13:00:00.500Z"), state: .approval)
        #expect(ActivitySummary.merged(waiting.activity.events + [generic]).state == .input)
        let ended = ActivityEvent(id: "end", provider: "Claude Code", sessionID: base.sessionID, kind: "finished", source: "Transcript", recordedAt: ActivityParser.date("2026-09-26T13:00:02Z"), state: .finished)
        #expect(ActivitySummary.merged(waiting.activity.events + [generic, ended]).attention.isEmpty)

        try append(#"{"type":"user","timestamp":"2026-09-26T13:00:01Z","message":{"content":[{"type":"tool_result","tool_use_id":"q1","content":"Continue"}]}}"# + "\n", to: url)
        let resumed = await observer.read(session, hookDirectory: nil)
        #expect(resumed.activity.state == .working)
        #expect(resumed.activity.attention.isEmpty)
    }

    @Test func claudeCancellationStopsWorkingAndNextTurnRecovers() async throws {
        let (url, base) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let session = Session(id: "Claude:cancel", provider: .claude, url: url, sessionID: base.sessionID, title: "Cancellation", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let observer = ExternalSessionObserver()
        try append(#"{"type":"assistant","timestamp":"2026-09-26T14:10:49.430Z","message":{"content":[{"type":"tool_use","id":"read1","name":"Bash","input":{"command":"cat README.md"}}]}}"# + "\n", to: url)
        #expect(await observer.read(session, hookDirectory: nil).activity.state == .working)
        try append(#"{"type":"user","timestamp":"2026-09-26T14:10:49.461Z","message":{"content":[{"type":"tool_result","tool_use_id":"read1","is_error":true,"content":"The tool use was rejected"}]}}"# + "\n", to: url)
        try append(#"{"type":"user","timestamp":"2026-09-26T14:10:49.463Z","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"# + "\n", to: url)
        let cancelled = await observer.read(session, hookDirectory: nil)
        #expect(cancelled.activity.state == .interrupted)
        #expect(cancelled.structured.records.contains { $0.nativeID == "read1" && $0.status == "failed" })
        try append(#"{"type":"user","timestamp":"2026-09-26T14:11:00Z","message":{"content":"Continue with a new task"}}"# + "\n", to: url)
        #expect(await observer.read(session, hookDirectory: nil).activity.state == .working)
        try append(#"{"type":"user","timestamp":"2026-09-26T14:11:01Z","message":{"content":"[Request interrupted by user]"}}"# + "\n", to: url)
        #expect(await observer.read(session, hookDirectory: nil).activity.state == .interrupted)
        try append(#"{"type":"user","timestamp":"2026-09-26T14:11:02Z","message":{"content":"Explain [Request interrupted by user] please"}}"# + "\n", to: url)
        #expect(await observer.read(session, hookDirectory: nil).activity.state == .working)
    }

}
