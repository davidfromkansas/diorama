import Foundation
import Testing
@testable import DioramaCore

private actor HistoryStub: AppServerReading {
    var replies: [Data]
    var calls: [(String, Data)] = []
    init(_ replies: [Data]) { self.replies = replies }
    func request(_ method: String, parameters: Data) throws -> Data {
        calls.append((method, parameters))
        if method == "thread/items/list", let first = replies.first, (try? JSONSerialization.jsonObject(with: first) as? [String: Any])?["data"] == nil { throw ExecutionRPCRejection("Paging not supported in legacy fixture") }
        guard !replies.isEmpty else { throw AppServerFailure("fixture disconnected") }
        return replies.removeFirst()
    }
}

struct AppServerHistoryTests {
    @Test func boundedItemPaginationLoadsOlderMessagesWithoutWholeThreadRead() async throws {
        let row: (String, String) -> [String: Any] = { id, text in ["turnId": "turn", "item": ["id": id, "type": "agentMessage", "text": text]] }
        let stub = HistoryStub(try [data(["data": [row("new", "Newest")], "nextCursor": "older"]), data(["data": [row("old", "Older")]])])
        let library = ImportedSessionLibrary(files: SessionLibrary(roots: []), server: stub)
        let session = try #require(AppServerHistory.session(task("fixture"), archived: false))
        let transcript = await library.transcript(for: session, limit: 2)
        #expect(transcript.entries.map(\.text) == ["Older", "Newest"])
        #expect(transcript.source.contains("paginated"))
        let calls = await stub.calls
        #expect(calls.map { $0.0 } == ["thread/items/list", "thread/items/list"])
        let second = try JSONSerialization.jsonObject(with: calls[1].1) as? [String: Any]
        #expect(second?["cursor"] as? String == "older")
    }
    @Test func expandingHistoryRetainsCursorButRefreshReadsNewest() async throws {
        let row: (String) -> [String: Any] = { ["turnId": "turn", "item": ["id": $0, "type": "agentMessage", "text": $0]] }
        let stub = HistoryStub(try [data(["data": [row("new")], "nextCursor": "older"]), data(["data": [row("old")]]), data(["data": [row("latest"), row("new")]])])
        let library = ImportedSessionLibrary(files: SessionLibrary(roots: []), server: stub)
        let session = try #require(AppServerHistory.session(task("fixture"), archived: false))
        _ = await library.transcript(for: session, limit: 1)
        let expanded = await library.transcript(for: session, limit: 2)
        #expect(expanded.entries.map(\.text) == ["old", "new"])
        let refreshed = await library.transcript(for: session, limit: 2)
        #expect(refreshed.entries.last?.text == "latest")
        let calls = await stub.calls
        #expect(calls.count == 3)
        let second = try JSONSerialization.jsonObject(with: calls[1].1) as? [String: Any]
        let third = try JSONSerialization.jsonObject(with: calls[2].1) as? [String: Any]
        #expect(second?["cursor"] as? String == "older")
        #expect(third?["cursor"] == nil)
    }
    @Test func boundedPageReportsOlderContentWithoutFetchingIt() async throws {
        let stub = HistoryStub(try [data(["data": [["turnId": "turn", "item": ["id": "new", "type": "agentMessage", "text": "Newest"]]], "nextCursor": "older"])])
        let library = ImportedSessionLibrary(files: SessionLibrary(roots: []), server: stub)
        let session = try #require(AppServerHistory.session(task("fixture"), archived: false))
        let transcript = await library.transcript(for: session, limit: 1)
        #expect(transcript.earlierContentOmitted)
        #expect(await stub.calls.count == 1)
    }
    @Test func currentProtocolItemsDoNotForceHistoryFallback() throws {
        let types = ["hookPrompt", "collabAgentToolCall", "subAgentActivity", "sleep", "imageGeneration"]
        let result = try AppServerHistory.transcript(["turns": [["id": "t", "items": types.map { ["id": $0, "type": $0] }]]], limit: 300)
        #expect(result.entries.count == types.count)
        #expect(result.entries.first?.category == .context)
    }
    @Test func imageViewKeepsStructuredReferenceAndRawDetails() throws {
        let result = try AppServerHistory.transcript(["turns": [["id": "t", "items": [
            ["type": "imageView", "id": "image", "path": "/tmp/My preview.png"],
            ["type": "imageView", "id": "missing"],
            ["type": "imageView", "id": "remote", "path": "https://example.com/image.png"],
            ["type": "commandExecution", "id": "command", "path": "/tmp/other.png"]
        ]]]], limit: 300)
        #expect(result.entries.count == 4)
        #expect(result.entries[0].image?.url.path == "/tmp/My preview.png")
        #expect(result.entries[0].text.contains("imageView"))
        #expect(result.entries.dropFirst().allSatisfy { $0.image == nil })
        #expect(TranscriptImage(itemType: "imageView", path: "relative.png") == nil)
        #expect(TranscriptImage(itemType: "imageView", path: "//server/image.png") == nil)
    }
    func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    func task(_ id: String, extra: [String: Any] = [:]) -> [String: Any] {
        ["id": id, "cwd": "/work/app", "preview": "Build **something**", "updatedAt": 1000, "threadSource": "user"].merging(extra) { _, new in new }
    }
    @Test func classificationAndIdentityDoNotDependOnFilesOrTitles() throws {
        let normal = try #require(AppServerHistory.session(task("normal", extra: ["name": "Internal approval review"]), archived: false))
        #expect(normal.classification == .conversation)
        #expect(normal.url == nil)
        #expect(normal.id == "Codex:normal")
        let internalTask = try #require(AppServerHistory.session(task("review", extra: ["threadSource": "guardian_review", "name": "Misleading title"]), archived: true))
        #expect(internalTask.classification == .internalReview)
        #expect(internalTask.title == "Internal approval review")
        let supplemented = try #require(AppServerHistory.session(["id": "review", "source": ["subAgent": ["other": "guardian"]], "parentThreadId": "normal"], archived: true, fallback: internalTask))
        #expect(supplemented.classification == .internalReview)
        #expect(supplemented.classificationEvidence.contains("supplement"))
        let child = try #require(AppServerHistory.session(["id": "child", "source": ["subAgent": ["thread_spawn": ["parent_thread_id": "normal"]]]], archived: false))
        #expect(child.parentID == "normal")
        #expect(child.classification == .subagent)
        let unknown = try #require(AppServerHistory.session(["id": "unknown", "source": "future-source"], archived: false))
        #expect(unknown.classification == .unknown)
        #expect(unknown.title == "Untitled conversation · unknown")
    }
    @Test func fullPaginationIncludesArchivesAndAllSources() async throws {
        let stub = HistoryStub(try [data(["data": [task("one")], "nextCursor": "page2"]), data(["data": [task("two")], "nextCursor": NSNull()]), data(["data": [task("archived")], "nextCursor": NSNull()])])
        let library = ImportedSessionLibrary(files: SessionLibrary(roots: []), server: stub)
        let result = await library.scan()
        #expect(result.sessions.count == 3)
        #expect(result.sessions.first { $0.sessionID == "archived" }?.archived == true)
        let calls = await stub.calls
        #expect(calls.map(\.0) == ["thread/list", "thread/list", "thread/list"])
        let params = try #require(JSONSerialization.jsonObject(with: calls[0].1) as? [String: Any])
        #expect(params["sourceKinds"] as? [String] == AppServerHistory.sourceKinds)
        #expect(params["useStateDbOnly"] as? Bool == true)
        // Failed reconciliation retains prior API-only sessions instead of dropping rows.
        let failed = await library.scan()
        #expect(failed.sessions.count == 3)
        #expect(failed.notices.contains { $0.contains("fallback") })
    }
    @Test func repeatedCursorFailsWithoutHidingLocalRecords() async throws {
        let repeated = try data(["data": [task("one")], "nextCursor": "same"])
        let library = ImportedSessionLibrary(files: SessionLibrary(roots: []), server: HistoryStub([repeated, repeated]))
        let result = await library.scan()
        #expect(result.notices.contains { $0.contains("repeated pagination") })
    }
    @Test func structuredHistoryPreservesMarkdownContextToolsAndExcludesReasoning() throws {
        let result = try AppServerHistory.transcript(["status": ["type": "idle"], "turns": [["id": "turn", "status": "completed", "items": [
            ["type": "userMessage", "id": "u", "content": [["type": "text", "text": "<environment_context><cwd>/work</cwd><shell>zsh</shell></environment_context>\nBuild **this**"]]],
            ["type": "agentMessage", "id": "a", "text": "# Heading\n\n| A | B |\n|---|---|\n| 1 | 2 |"],
            ["type": "commandExecution", "id": "tool", "command": "echo test", "aggregatedOutput": "test", "exitCode": 0],
            ["type": "reasoning", "id": "hidden", "content": "never display"]
        ]]]], limit: 300)
        #expect(result.entries.map(\.kind) == ["System context", "You", "Assistant", "Tool activity"])
        #expect(result.entries[1].text.trimmingCharacters(in: .whitespacesAndNewlines) == "Build **this**")
        #expect(!result.entries.contains { $0.text.contains("never display") })
        #expect(result.state == "Last turn finished")
        let empty = try AppServerHistory.transcript(["status": ["type": "idle"], "turns": []], limit: 300)
        #expect(empty.state == "Unknown")
    }
    @Test func emptyTurnTriggersFileFallbackAndPreservesLastGoodRead() async throws {
        let fixture = SessionLibraryTests()
        let root = try fixture.directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.jsonl")
        try fixture.write([fixture.meta, ["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": "Saved reply"]]], to: file)
        let files = SessionLibrary(roots: [.init(url: root, provider: .codex)])
        let session = try #require(await files.scan().sessions.first)
        let response = try data(["thread": ["id": session.sessionID, "turns": [["id": "empty", "items": [], "status": "completed"]]]])
        let library = ImportedSessionLibrary(files: files, server: HistoryStub([response]))
        let fallback = await library.transcript(for: session)
        #expect(fallback.source == "Local transcript fallback")
        #expect(fallback.entries.first?.text == "Saved reply")
        #expect(fallback.notice?.contains("without readable items") == true)
        try FileManager.default.removeItem(at: file)
        let cached = await library.transcript(for: session)
        #expect(cached.entries == fallback.entries)
        #expect(cached.notice?.contains("last successfully read") == true)
    }
    @Test func unavailableServerKeepsClaudeAndCodexAndSourceBytes() async throws {
        let fixture = SessionLibraryTests()
        let root = try fixture.directory(); defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let file = codex.appendingPathComponent("test.jsonl")
        try fixture.write([fixture.meta], to: file)
        let before = try Data(contentsOf: file)
        let claude = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try fixture.write([["sessionId": "claude-test", "cwd": "/test/project", "isSidechain": false, "type": "user", "message": ["content": "Claude prompt"]]], to: claude.appendingPathComponent("claude.jsonl"))
        let library = ImportedSessionLibrary(files: SessionLibrary(roots: [.init(url: codex, provider: .codex), .init(url: claude, provider: .claude)]), server: HistoryStub([]))
        let result = await library.scan()
        #expect(result.sessions.count == 2)
        let claudeSession = try #require(result.sessions.first { $0.provider == .claude })
        #expect(await library.transcript(for: claudeSession).entries.first?.text == "Claude prompt")
        #expect(result.sessions[0].historySource == "Local transcript")
        #expect(try Data(contentsOf: file) == before)
    }
    @Test func historyTransportRejectsExecutionWithoutLaunching() async throws {
        let connection = AppServerConnection(executable: URL(fileURLWithPath: "/does-not-exist"))
        do {
            _ = try await connection.request("thread/resume", parameters: data(["threadId": "test"]))
            Issue.record("Resume must not be allowed")
        } catch { #expect(error.localizedDescription.contains("Unsupported read-only")) }
    }
    @Test func fragmentedPipeResponseAndDisconnectAreBounded() async throws {
        let fixture = SessionLibraryTests()
        let root = try fixture.directory(); defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("server")
        let disconnected = root.appendingPathComponent("disconnected")
        let script = """
        #!/bin/sh
        IFS= read -r initialize
        printf '{"id":1,"result":{}}\\n'
        IFS= read -r initialized
        IFS= read -r request
        printf '{"id":2,"res'
        printf 'ult":{"thread":{"id":"test","turns":[]}}}\\n'
        exec 0<&-
        touch "\(disconnected.path)"
        sleep 2
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let connection = AppServerConnection(executable: executable, timeout: 2)
        let response = try await connection.request("thread/read", parameters: data(["threadId": "test"]))
        #expect(String(decoding: response, as: UTF8.self).contains("test"))
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: disconnected.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: disconnected.path))
        do {
            _ = try await connection.request("thread/read", parameters: data(["threadId": "test"]))
            Issue.record("Closed/restarted fixture cannot answer this request")
        } catch { #expect(!error.localizedDescription.isEmpty) }
    }
    @Test func largeHistoryFrameDoesNotRepeatedlyRescanBufferedBytes() async throws {
        let fixture = SessionLibraryTests()
        let root = try fixture.directory(); defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("large-server")
        let script = """
        #!/bin/sh
        IFS= read -r initialize
        printf '{"id":1,"result":{}}\\n'
        IFS= read -r initialized
        IFS= read -r request
        printf '{"id":2,"result":{"padding":"'
        head -c 4194304 /dev/zero | tr '\\000' x
        printf '"}}\\n'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let connection = AppServerConnection(executable: executable, timeout: 3)
        let response = try await connection.request("thread/read", parameters: data(["threadId": "fixture"]))
        #expect(response.count > 4 * 1024 * 1024)
    }
    @Test func missingRecentReplyFallsBackEvenWhenOtherItemsExist() async throws {
        let fixture = SessionLibraryTests()
        let root = try fixture.directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.jsonl")
        try fixture.write([fixture.meta, ["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": "Newest reply"]]], to: file)
        let files = SessionLibrary(roots: [.init(url: root, provider: .codex)])
        let session = try #require(await files.scan().sessions.first)
        let response = try data(["thread": ["id": session.sessionID, "turns": [["id": "partial", "items": [["id": "old", "type": "agentMessage", "text": "Older reply"]]]]]])
        let library = ImportedSessionLibrary(files: files, server: HistoryStub([response]))
        let result = await library.transcript(for: session)
        #expect(result.entries.first?.text == "Newest reply")
        #expect(result.notice?.contains("Latest recorded") == true)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_APPSERVER_PROBE"] == "1"))
    func designatedLiveHistoryAndDiscovery() async throws {
        let connection = AppServerConnection()
        // List metadata only; body reads are restricted to the disposable test conversation.
        let library = ImportedSessionLibrary(server: connection)
        let scan = await library.scan()
        #expect(scan.notices.contains { $0.contains("App Server connected") })
        let session = try #require(scan.sessions.first { $0.sessionID == "01a0b54c-d0a1-7f01-8866-0c2ae746a94e" })
        #expect(session.archived)
        let transcript = await library.transcript(for: session, limit: 500)
        #expect(transcript.error == nil)
        #expect(transcript.entries.contains { $0.text.contains("DESKTOP_ROUNDTRIP_DONE") })
        let main = try #require(scan.sessions.first { $0.sessionID == "01a0af95-959f-77e3-ab51-b0072fe66b37" })
        #expect(main.classification == .conversation)
        #expect(scan.sessions.contains { $0.project == main.project && $0.classification == .internalReview })
        print("APPSERVER_PROBE sessions=\(scan.sessions.count) archived=\(scan.sessions.filter(\.archived).count) api=\(scan.sessions.filter { $0.historySource == "Codex App Server" }.count) source=\(transcript.source) entries=\(transcript.entries.count) notice=\(transcript.notice ?? "none")")
    }
}
