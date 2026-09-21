import Foundation
import Testing
@testable import DioramaCore

struct ActivityTests {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-activity-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func session(_ url: URL, id: String = "s", provider: Provider = .codex) -> Session {
        Session(id: provider.rawValue + ":" + id, provider: provider, url: url, sessionID: id, title: id,
                project: "/test", modified: Date(), bytes: 0, archived: false, parentID: nil)
    }
    func line(_ type: String, date: String = "2026-09-18T01:00:00Z") throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": date, "payload": ["type": type, "turn_id": "t"]])
        data.append(10); return data
    }
    func event(_ kind: String, state: ActivityState? = nil, second: Double, call: String? = nil, turn: String? = "t", agent: String? = nil) -> ActivityEvent {
        ActivityEvent(id: "\(kind)-\(second)", provider: "Codex", sessionID: "s", kind: kind, source: "test",
                      recordedAt: Date(timeIntervalSince1970: second), turnID: turn, callID: call, agentID: agent, state: state)
    }
    @Test func duplicatesLateEventsAndResumedTurns() {
        let started = event("started", state: .working, second: 20)
        let ended = event("finished", state: .finished, second: 10)
        let summary = ActivitySummary.merged([started, ended, started])
        #expect(summary.events.count == 2)
        #expect(summary.state == .working)
    }
    @Test func priorTurnCompletionCannotFinishResumedWork() {
        let old = event("started", state: .working, second: 1, turn: "old")
        let resumed = event("started", state: .working, second: 2, turn: "new")
        let lateEnd = event("finished", state: .finished, second: 3, turn: "old")
        #expect(ActivitySummary.merged([old, resumed, lateEnd]).state == .working)
    }
    @Test func attentionNeedsCorrelatedResolutionAndNoCrossAgentCompletion() {
        let request = event("approval", state: .approval, second: 10, call: "c", agent: "child")
        let parentEnd = event("finished", state: .finished, second: 20)
        #expect(ActivitySummary.merged([request, parentEnd]).attention.count == 1)
        let unrelated = event("toolFinished", second: 21, call: "other", agent: "child")
        #expect(ActivitySummary.merged([request, unrelated]).attention.count == 1)
        let matched = event("toolFinished", second: 22, call: "c", agent: "child")
        #expect(ActivitySummary.merged([request, matched]).attention.isEmpty)
        let interruption = event("interrupted", state: .interrupted, second: 23, agent: "child")
        #expect(ActivitySummary.merged([request, interruption]).attention.isEmpty)
        let unknown = event("approval", state: .approval, second: 24, turn: nil)
        #expect(ActivitySummary.merged([unknown, parentEnd]).attention.count == 1)
    }
    @Test func conflictsAndUnmatchedToolsRemainUncertain() {
        let a = event("started", state: .working, second: 10)
        let b = event("finished", state: .finished, second: 10)
        #expect(ActivitySummary.merged([a, b]).uncertain)
        let tool = event("toolStarted", second: 20, call: "x")
        #expect(ActivitySummary.merged([tool]).state == .unknown)
    }
    @Test func reporterAllowlistsAndLimitsSensitiveFields() throws {
        let raw: [String: Any] = ["session_id": "s", "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_use_id": "c",
                                 "prompt": "SECRET_PROMPT", "last_assistant_message": "SECRET_REPLY", "env": ["TOKEN": "SECRET_TOKEN"],
                                 "tool_input": ["command": String(repeating: "x", count: 2000), "unrelated": "SECRET_ARGUMENT"], "tool_response": "SECRET_OUTPUT"]
        let event = try #require(ActivityParser.hook(raw, provider: .codex))
        #expect(event.detail?.count == 1000)
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        #expect(!encoded.contains("SECRET"))
        #expect(event.state == .working)
        #expect(event.recordedAt == nil)
    }
    @Test func hookSemanticsDontInventCompletionOrBlocking() throws {
        func hook(_ name: String, _ extra: [String: Any] = [:], provider: Provider = .codex) -> ActivityEvent? {
            ActivityParser.hook(["session_id": "s", "hook_event_name": name].merging(extra) { _, new in new }, provider: provider)
        }
        #expect(hook("Stop")?.state == nil)
        #expect(hook("SessionStart")?.state == nil)
        #expect(hook("SubagentStop")?.state == nil)
        #expect(hook("PermissionRequest")?.state == .approval)
        #expect(hook("PostToolUseFailure", provider: .claude)?.state != .blocked)
        #expect(hook("Notification", ["notification_type": "idle_prompt"], provider: .claude)?.state == .idle)
        #expect(hook("Notification", ["notification_type": "elicitation_dialog"], provider: .claude)?.state == .input)
        #expect(hook("Unrecognized") == nil)
    }
    @Test func incrementalMultipleSessionsPartialWritesReplacementAndReconnect() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.jsonl"), b = root.appendingPathComponent("b.jsonl")
        try line("task_started").write(to: a); try line("task_complete").write(to: b)
        let sa = session(a, id: "a"), sb = session(b, id: "b")
        let library = ActivityLibrary()
        let first = await library.scan([sa, sb], hookDirectory: nil)
        #expect(first[sa.id]?.state == .working); #expect(first[sb.id]?.state == .finished)
        let complete = try line("task_complete", date: "2026-09-18T01:01:00Z")
        let handle = try FileHandle(forWritingTo: a); try handle.seekToEnd()
        try handle.write(contentsOf: complete.dropLast())
        #expect(await library.scan([sa, sb], hookDirectory: nil)[sa.id]?.state == .working)
        try handle.write(contentsOf: Data([10])); try handle.close()
        #expect(await library.scan([sa, sb], hookDirectory: nil)[sa.id]?.state == .finished)
        #expect(await ActivityLibrary().scan([sa], hookDirectory: nil)[sa.id]?.state == .finished)
        try line("turn_aborted", date: "2026-09-18T02:00:00Z").write(to: a, options: .atomic)
        let replaced = await library.scan([sa], hookDirectory: nil)
        #expect(replaced[sa.id]?.state == .interrupted)
        #expect(replaced[sa.id]?.events.count == 1)
        try FileManager.default.removeItem(at: a)
        #expect(await library.scan([sa], hookDirectory: nil)[sa.id]?.error != nil)
    }
    @Test func longRunningStateSurvivesTailAndEventLimits() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("long.jsonl")
        var data = try line("task_started")
        for index in 0..<600 {
            var tool = try JSONSerialization.data(withJSONObject: ["type": "response_item", "timestamp": "2026-09-18T01:01:00Z", "payload": ["type": "function_call", "call_id": "c-\(index)", "name": "Bash", "arguments": String(repeating: "x", count: 1000)]])
            tool.append(10); data.append(tool)
        }
        try data.write(to: file)
        let s = session(file), library = ActivityLibrary()
        let summary = try #require(await library.scan([s], hookDirectory: nil)[s.id])
        #expect(summary.state == .working)
        #expect(summary.events.count <= 500)
        #expect(await library.scan([s], hookDirectory: nil)[s.id]?.state == .working)
    }
    @Test func configMergeRemoveBackupAndConcurrentEdit() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let config = HookConfiguration(provider: .codex, configURL: root.appendingPathComponent("hooks.json"), base: root)
        let original = Data(#"{"other":true,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo existing"}]}]}}"#.utf8)
        try original.write(to: config.configURL)
        let updated = try config.preview(original: original, events: ["Stop", "PreToolUse"])
        let reporter = root.appendingPathComponent("binary"); try Data("test".utf8).write(to: reporter)
        try config.apply(expected: original, updated: updated, bundledReporter: reporter, remove: false)
        #expect(config.installed())
        #expect((try FileManager.default.contentsOfDirectory(atPath: root.path)).contains { $0.contains("diorama-backup") })
        #expect(throws: (any Error).self) { try config.apply(expected: original, updated: updated, bundledReporter: reporter, remove: false) }
        let removed = try config.preview(original: updated, events: [], remove: true)
        let text = String(decoding: removed, as: UTF8.self)
        #expect(text.contains("echo existing")); #expect(text.contains("other")); #expect(!text.contains("--diorama-reporter-v1"))
        try config.apply(expected: updated, updated: removed, bundledReporter: reporter, remove: true)
        #expect(!config.installed())
    }
    @Test func unknownVersionsCannotInstallAndMalformedSettingsAreNotOverwritten() {
        #expect(!HookCapability.profile(provider: .claude, version: "1.0.108").events.contains("PermissionRequest"))
        #expect(HookCapability.profile(provider: .claude, version: "1.0.108").canInstall)
        #expect(!HookCapability.profile(provider: .codex, version: "Unknown").canInstall)
        let config = HookConfiguration(provider: .claude)
        #expect(throws: (any Error).self) { try config.preview(original: Data("bad".utf8), events: ["Stop"]) }
    }
    @Test func hookRetentionAndClearDoNotTouchOtherFiles() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("keep".utf8).write(to: root.appendingPathComponent("keep.txt"))
        try HookStore.write(event("started", state: .working, second: 1), directory: root)
        #expect(HookStore.read(directory: root).count == 1)
        try HookStore.prune(directory: root, now: Date().addingTimeInterval(8 * 86400))
        #expect(HookStore.read(directory: root).isEmpty)
        try HookStore.write(event("started", state: .working, second: 2), directory: root)
        try HookStore.prune(directory: root, maxBytes: 0)
        #expect(HookStore.read(directory: root).isEmpty)
        try HookStore.clear(directory: root)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("keep.txt").path))
    }
}
