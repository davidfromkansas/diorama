import Foundation
import Testing
@testable import DioramaCore

struct SessionLibraryTests {
    @Test func groupingUsesFullWorkingPathAcrossProviders() {
        func session(_ id: String, _ provider: Provider, _ folder: String) -> Session {
            Session(id: id, provider: provider, url: URL(fileURLWithPath: "/test/\(id).jsonl"),
                    sessionID: id, title: id, project: folder, modified: .distantPast,
                    bytes: 0, archived: false, parentID: nil)
        }
        let sessions = [session("a", .codex, "/work/app/"), session("b", .claude, "/work/app"),
                        session("c", .codex, "/other/app"), session("d", .claude, ""),
                        session("e", .codex, "/work/app/subfolder"), session("f", .claude, "relative")]
        let folders = WorkingFolder.group(sessions)
        #expect(folders.count == 4)
        #expect(folders.first { $0.path == "/work/app" }?.sessions.count == 2)
        #expect(folders.first { $0.path == nil }?.sessions.count == 2)
        #expect(folders.filter { $0.name == "app" }.count == 2)
        #expect(folders.flatMap(\.sessions).count == sessions.count)
    }

    func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func write(_ records: [[String: Any]], to file: URL) throws {
        var data = Data()
        for record in records { data.append(try JSONSerialization.data(withJSONObject: record)); data.append(10) }
        try data.write(to: file)
    }
    let meta: [String: Any] = ["type": "session_meta", "payload": ["id": "test-session", "cwd": "/test/project"]]

    @Test func discoveryDeduplicationAndDeletion() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("current"); let archived = root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let file = current.appendingPathComponent("session.jsonl")
        let messages: [[String: Any]] = [meta, ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type":"input_text","text":"<environment_context><cwd>/test</cwd><shell>zsh</shell></environment_context>"]]]], ["type": "response_item", "payload": ["type": "message", "role": "user", "content": "Build a lunar base"]]]
        try write(messages, to: file)
        try write(messages, to: archived.appendingPathComponent("copy.jsonl"))
        let library = SessionLibrary(roots: [.init(url: current, provider: .codex), .init(url: archived, provider: .codex, archived: true)])
        let first = await library.scan()
        #expect(first.sessions.count == 1)
        #expect(first.sessions.first?.title == "Build a lunar base")
        #expect(first.sessions.first?.project == "/test/project")
        try FileManager.default.removeItem(at: file)
        #expect(await library.scan().sessions.count == 1)
        try FileManager.default.removeItem(at: archived.appendingPathComponent("copy.jsonl"))
        #expect(await library.scan().sessions.isEmpty)
    }

    @Test func transcriptFiltersHiddenContentAndReadsToolResults() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        try write([meta,
            ["type":"event_msg","payload":["type":"task_started"]],
            ["type":"response_item","payload":["type":"message","role":"system","content":"Injected instruction"]],
            ["type":"response_item","payload":["type":"reasoning","summary":"PRIVATE"]],
            ["type":"response_item","payload":["type":"function_call","name":"exec","arguments":"echo hi"]],
            ["type":"response_item","payload":["type":"function_call_output","output":"hi"]],
            ["type":"response_item","payload":["type":"message","role":"assistant","content":[["type":"output_text","text":"Hello"]]]],
            ["type":"event_msg","payload":["type":"task_complete"]]
        ], to:file)
        let result = SessionLibrary.readTranscript(url: file, provider: .codex)
        #expect(result.state == "Last turn finished")
        #expect(result.entries.count == 6)
        #expect(!result.entries.contains { $0.text.contains("PRIVATE") })
        #expect(result.entries.contains { $0.tool?.type == "functionCallOutput" && $0.tool?.output == "hi" })
    }

    @Test func partialWriteAndRefresh() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        let record: [String: Any] = ["type":"response_item","payload":["type":"message","role":"assistant","content":"Moon 月"]]
        var bytes = try JSONSerialization.data(withJSONObject: record)
        try bytes.write(to: file)
        #expect(SessionLibrary.readTranscript(url:file,provider:.codex).entries.isEmpty)
        bytes.append(10); try bytes.write(to:file)
        #expect(SessionLibrary.readTranscript(url:file,provider:.codex).entries.first?.text == "Moon 月")
        try Data("broken\n[]\n".utf8).write(to:file)
        #expect(SessionLibrary.readTranscript(url:file,provider:.codex).malformed == 2)
        #expect(SessionLibrary.readTranscript(url:file,provider:.codex).entries.isEmpty)
    }

    @Test func claudeSubagentAndNoInventedStatus() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("parent-session/subagents")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories:true)
        let file = child.appendingPathComponent("agent-abc.jsonl")
        try write([["type":"assistant","sessionId":"parent-session","parentUuid":"MESSAGE-NOT-AGENT","cwd":"/test","uuid":"one","message":["content":[["type":"text","text":"Done"],["type":"thinking","thinking":"PRIVATE"]]]]], to:file)
        let library = SessionLibrary(roots:[.init(url:root,provider:.claude)])
        let snapshot = await library.scan()
        #expect(snapshot.sessions.first?.parentID == "parent-session")
        #expect(snapshot.sessions.first?.id == "Claude Code:parent-session/agent-abc")
        let result = SessionLibrary.readTranscript(url:file,provider:.claude)
        #expect(result.state == "Unknown")
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.text == "Done")
    }

    @Test func boundedHistoryMissingSourcesAndSourceUnchanged() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        try write((0..<8).map { ["type":"user","sessionId":"c","message":["content":"Message \($0)"]] }, to:file)
        let before = try Data(contentsOf:file)
        let result = SessionLibrary.readTranscript(url:file,provider:.claude,limit:3)
        #expect(result.entries.count == 3)
        #expect(result.earlierContentOmitted)
        #expect(try Data(contentsOf:file) == before)
        let library = SessionLibrary(roots:[.init(url:root.appendingPathComponent("missing"),provider:.codex)])
        #expect(await library.scan().notices.count == 1)
        #expect(SessionLibrary.readTranscript(url:root.appendingPathComponent("missing.jsonl"),provider:.codex).error != nil)
    }
}
