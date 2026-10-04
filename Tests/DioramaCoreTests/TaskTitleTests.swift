import Foundation
import Testing
@testable import DioramaCore

private actor TitleServer: AppServerReading {
    var replies: [Data]
    init(_ titles: [String?]) {
        replies = titles.flatMap { name -> [Data] in
            var thread: [String: Any] = ["id": "title-test", "cwd": "/project", "preview": "Please build a new writing page", "updatedAt": 1]
            if let name { thread["name"] = name }
            return [try! JSONSerialization.data(withJSONObject: ["data": [thread]]), Data("{\"data\":[]}".utf8)]
        }
    }
    func request(_ method: String, parameters: Data) throws -> Data {
        guard !replies.isEmpty else { throw AppServerFailure("offline") }
        return replies.removeFirst()
    }
}

struct TaskTitleTests {
    @Test func compactPresentationRetainsFullTitle() {
        #expect(TaskTitle.compact("**Add** a writing page with RSS import") == "Add a writing page with RSS…")
        #expect(TaskTitle.compact("Fix writing contrast") == "Fix writing contrast")
        #expect(TaskTitle.compact("Hello\n<diorama_html_view>hidden") == "Hello")
    }
    @Test func providerTitleWinsOverFallbackWithoutChangingIdentity() throws {
        let old = try #require(AppServerHistory.session(["id": "x", "name": "Add Writing Tab"], archived: false))
        let fallback = try #require(AppServerHistory.session(["id": "x", "preview": "new prompt"], archived: false))
        let retained = fallback.retainingTitle(from: old)
        #expect(retained.title == old.title)
        #expect(retained.id == fallback.id && retained.modified == fallback.modified)
        let renamed = try #require(AppServerHistory.session(["id": "x", "name": "Fix Contrast"], archived: false))
        #expect(renamed.retainingTitle(from: old).title == "Fix Contrast")
        #expect(renamed.titleSource == .provider)
    }
    @Test func claudeLateMetadataAndRefresh() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("session.jsonl")
        let first = "{\"type\":\"user\",\"sessionId\":\"c\",\"cwd\":\"/project\",\"message\":{\"content\":\"Please create a writing tab\"}}\n"
        try Data(first.utf8).write(to: file)
        let library = SessionLibrary(roots: [.init(url: dir, provider: .claude)])
        #expect(await library.scan().sessions.first?.titleSource == .prompt)
        let padding = String(repeating: "{\"type\":\"noop\"}\n", count: 80000)
        try Data((first + padding + "{\"type\":\"summary\",\"summary\":\"Add Writing Tab\"}\n").utf8).write(to: file)
        #expect(await library.scan().sessions.first?.title == "Add Writing Tab")
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"type\":\"custom-title\",\"customTitle\":\"My Writing Page\"}\n{\"type\":\"summary\",\"summary\":\"Ignore this summary\"}\n".utf8)); try handle.close()
        let updated = await library.scan().sessions.first
        #expect(updated?.title == "My Writing Page" && updated?.titleSource == .explicit)
        let read = try FileHandle(forReadingFrom: file); defer { try? read.close() }
        #expect(try SessionLibrary.metadataWindow(read).count <= 1024 * 1024)
    }
    @Test func cacheSurvivesMissingNameOfflineAndRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("titles.json")
        let server = TitleServer(["Add Writing Tab", nil, "Fix Contrast"])
        let library = ImportedSessionLibrary(files: SessionLibrary(roots: []), server: server, titleCacheURL: cache)
        #expect(await library.scan().sessions.first?.title == "Add Writing Tab")
        #expect(await library.scan().sessions.first?.title == "Add Writing Tab")
        #expect(await library.scan().sessions.first?.title == "Fix Contrast")
        #expect(await library.scan().sessions.first?.title == "Fix Contrast")
        let restarted = ImportedSessionLibrary(files: SessionLibrary(roots: []), server: TitleServer([nil]), titleCacheURL: cache)
        #expect(await restarted.scan().sessions.first?.title == "Fix Contrast")
    }
}

extension TaskTitleTests {
    @Test func inboxTitleOnlyUpdateKeepsReadStateAndTimestamp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectInboxStore(directory: dir)
        let update = InboxUpdate(id: "u", text: "Original output", date: Date(timeIntervalSince1970: 100))
        try await store.ingest(project: "p", conversation: "c", title: "Old", updates: [update], historicalBefore: .distantFuture)
        let before = try #require(await store.page(project: "p").rows.first)
        try await store.ingest(project: "p", conversation: "c", title: "New Provider Title", updates: [], historicalBefore: .distantFuture)
        let after = try #require(await store.page(project: "p").rows.first)
        #expect(after.title == "New Provider Title")
        #expect(after.date == before.date && after.unread == before.unread && after.excerpt == before.excerpt)
        #expect(try await store.detail("p:c").first?.text == "Original output")
    }
}

extension TaskTitleTests {
    @Test func indexedExistingClaudeTitleRefreshesWithoutTranscriptChange() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let transcript = dir.appendingPathComponent("c.jsonl")
        try Data("{\"type\":\"user\",\"sessionId\":\"c\",\"cwd\":\"/project\",\"message\":{\"content\":\"Please build a writing page\"}}\n".utf8).write(to: transcript)
        let index = dir.appendingPathComponent("sessions-index.json")
        func writeIndex(_ title: String) throws {
            try JSONSerialization.data(withJSONObject: ["entries": [["sessionId": "c", "summary": title]]]).write(to: index, options: .atomic)
        }
        try writeIndex("Add Writing Tab")
        let library = SessionLibrary(roots: [.init(url: dir, provider: .claude)])
        let first = try #require(await library.scan().sessions.first)
        #expect(first.title == "Add Writing Tab" && first.titleSource == .summary)
        try writeIndex("Fix Writing Page Contrast")
        let second = try #require(await library.scan().sessions.first)
        #expect(second.title == "Fix Writing Page Contrast" && second.modified == first.modified)
    }
    @Test func mergedConversationUsesActiveSourceTitleAndKeepsCanonicalIdentity() throws {
        let source = try #require(AppServerHistory.session(["id": "original", "name": "Original Task"], archived: false))
        var record = DioramaConversation(session: source, model: "fixture")
        record.segments.append(.init(nativeID: "destination", provider: .codex, model: "fixture"))
        let active = try #require(AppServerHistory.session(["id": "destination", "name": "Current Task"], archived: false))
        let merged = record.session(using: active)
        #expect(merged.id == source.id && merged.sessionID == active.sessionID)
        #expect(merged.title == "Current Task" && merged.titleSource == .provider)
    }
}
