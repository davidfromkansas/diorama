import Foundation
import Testing
@testable import DioramaCore

struct ClaudeDesktopHistoryTests {
    let id = "A1111111-1111-4111-8111-111111111111"
    let desktopID = "local_B2222222-2222-4222-8222-222222222222"
    func fixture() throws -> ClaudeDesktopPaths {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = ClaudeDesktopPaths(metadata: base.appendingPathComponent("Desktop"), transcripts: base.appendingPathComponent("projects"), registry: base.appendingPathComponent("ClaudeSessions"))
        for url in [paths.metadata, paths.transcripts] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return paths
    }
    func writeMetadata(_ paths: ClaudeDesktopPaths, changes: [String: Any] = [:]) throws {
        var value: [String: Any] = ["sessionId": desktopID, "cliSessionId": id, "cwd": "/work/worktree", "originCwd": "/work/repository", "title": "Desktop fixture", "isArchived": false, "lastActivityAt": 1_700_000_000_000]
        value.merge(changes) { _, new in new }
        try JSONSerialization.data(withJSONObject: value).write(to: paths.metadata.appendingPathComponent(desktopID + ".json"))
    }
    func writeTranscript(_ paths: ClaudeDesktopPaths, id: String? = nil) throws -> URL {
        let file = paths.transcripts.appendingPathComponent("transcript.jsonl")
        let record: [String: Any] = ["sessionId": id ?? self.id, "cwd": "/work/worktree", "isSidechain": false, "type": "user", "uuid": "u1", "message": ["role": "user", "content": "Synthetic fixture prompt"]]
        var data = try JSONSerialization.data(withJSONObject: record); data.append(10)
        try data.write(to: file)
        return file
    }
    func library(_ paths: ClaudeDesktopPaths) -> SessionLibrary {
        .init(roots: [.init(url: paths.transcripts, provider: .claude)], desktop: .init(paths: paths))
    }
    @Test func discoversOlderHistoryWithoutHooksAndKeepsIdentityAndWorktree() async throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        try writeMetadata(paths); let file = try writeTranscript(paths)
        let lib = library(paths)
        let result = await lib.scan()
        let session = try #require(result.sessions.first)
        #expect(result.sessions.count == 1)
        #expect(session.id == "Claude Code:" + id)
        #expect(session.origin == .claudeDesktop)
        #expect(session.desktopSessionID == desktopID)
        #expect(session.project == "/work/worktree")
        #expect(session.url?.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
        #expect(session.observationOnly)
        #expect(await lib.transcript(for: session).entries.first?.text == "Synthetic fixture prompt")
        #expect(await ExecutionController.resumeUnavailableReason(session)?.contains("View-only") == true)
        #expect(await library(paths).scan().sessions.first?.origin == .claudeDesktop)
    }
    @Test func missingAndMismatchedTranscriptsStayUnavailable() async throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        try writeMetadata(paths)
        let lib = library(paths)
        #expect(await lib.scan().sessions.first?.url == nil)
        _ = try writeTranscript(paths, id: UUID().uuidString)
        let result = await lib.scan()
        #expect(result.sessions.first(where: { $0.origin == .claudeDesktop })?.url == nil)
        #expect(result.notices.contains { $0.contains("no readable") })
    }
    @Test func liveAppendPartialWriteAndDeletedTranscript() async throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        try writeMetadata(paths); let file = try writeTranscript(paths)
        let lib = library(paths); let session = try #require(await lib.scan().sessions.first)
        let record: [String: Any] = ["sessionId": id, "type": "assistant", "uuid": "a1", "message": ["role": "assistant", "content": "New Desktop reply"]]
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: record))
        #expect(await lib.transcript(for: session).entries.count == 1)
        try handle.write(contentsOf: Data([10])); try handle.close()
        #expect(await lib.transcript(for: session).entries.last?.text == "New Desktop reply")
        try FileManager.default.removeItem(at: file)
        #expect(await lib.scan().sessions.first?.url == nil)
    }
    @Test func registrySurvivesActivityClearingAndRejectsEscapesAndWrongIdentity() async throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        let file = try writeTranscript(paths)
        let record: [String: Any] = ["session_id": id, "cwd": "/work/worktree", "transcript_path": file.path]
        let ref = try #require(ClaudeSessionReference.hook(record, environment: [:]))
        try ref.write(paths: paths)
        try HookStore.clear(directory: paths.registry.deletingLastPathComponent().appendingPathComponent("Activity"))
        let result = ClaudeDesktopHistory(paths: paths).merging([])
        #expect(result.sessions.count == 1)
        #expect(result.sessions.first?.lastObservedHook != nil)
        #expect(result.sessions.first?.origin == .unknown)
        #expect(ClaudeSessionReference.hook(record, environment: ["CLAUDE_CODE_REMOTE": "true"]) == nil)
        #expect(ClaudeSessionReference.hook(record, environment: ["SSH_CONNECTION": "host"]) == nil)
        #expect(!paths.permitsTranscript(paths.transcripts.deletingLastPathComponent().appendingPathComponent("outside.jsonl")))
        _ = try writeTranscript(paths, id: UUID().uuidString)
        #expect(ClaudeDesktopHistory(paths: paths).merging([]).sessions.isEmpty)
    }
    @Test func unsupportedRemoteAndMalformedMetadata() async throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        try writeMetadata(paths, changes: ["sshHost": "example.test"])
        #expect(await library(paths).scan().sessions.isEmpty)
        try writeMetadata(paths, changes: ["cliSessionId": "../escape"])
        let result = await library(paths).scan()
        #expect(result.sessions.isEmpty)
        #expect(result.notices.contains { $0.contains("unsupported") })
    }
    @Test func hookConfigurationIsSharedIdempotentAndVersionIndependent() throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        let config = HookConfiguration(provider: .claude, base: paths.registry)
        let original = Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"other-reporter"}]}]},"theme":"dark"}"#.utf8)
        let cli = try config.preview(original: original, events: ["SubagentStart", "Stop"])
        let profile = HookCapability.desktopProfile(version: "2.7032.0")
        #expect(profile.canInstall)
        #expect(!HookCapability.desktopProfile(version: "unknown").canInstall)
        let desktop = try config.preview(original: cli, events: profile.events)
        #expect(try config.preview(original: desktop, events: profile.events) == desktop)
        let text = String(decoding: desktop, as: UTF8.self)
        #expect(text.contains("SubagentStart")); #expect(text.contains("other-reporter")); #expect(text.contains("dark"))
        let removed = try config.preview(original: desktop, events: [], remove: true)
        #expect(!String(decoding: removed, as: UTF8.self).contains("--diorama-reporter"))
        #expect(String(decoding: removed, as: UTF8.self).contains("other-reporter"))
        let displayed = try config.displayPreview(desktop)
        #expect(displayed.contains("DioramaReporter"))
        #expect(!displayed.contains("other-reporter"))
        #expect(!displayed.contains("theme"))
        let secretConfig = Data(#"{"hooks":{},"mcpServers":{"private":{"env":{"API_KEY":"DO_NOT_DISPLAY"}}}}"#.utf8)
        let secretPreview = try config.preview(original: secretConfig, events: ["Stop"])
        #expect(try !config.displayPreview(secretPreview).contains("DO_NOT_DISPLAY"))
        #expect(String(decoding: secretPreview, as: UTF8.self).contains("DO_NOT_DISPLAY"))
    }
}

private actor DesktopNoExecutionTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    var calls = 0
    func connect() { calls += 1 }
    func request(_ method: String, _ params: WireValue) throws -> WireValue { calls += 1; throw AppServerFailure("Unexpected execution") }
    func respond(id: WireValue, result: WireValue) { calls += 1 }
    func reject(id: WireValue, message: String) { calls += 1 }
    func shutdown() {}
}

extension ClaudeDesktopHistoryTests {
    @MainActor @Test func desktopExecutionIsRejectedBeforeTransportEvenForJournaledIDs() async throws {
        let transport = DesktopNoExecutionTransport()
        let controller = ExecutionController(transport: transport)
        var session = Session(id: "Claude Code:" + id, provider: .claude, url: nil, sessionID: id, title: "Desktop", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        session.origin = .claudeDesktop
        do { try await controller.resumeImported(session); Issue.record("Desktop resume allowed") } catch { #expect(error.localizedDescription.contains("View-only")) }
        do { try await controller.send(in: session, prompt: "Never send"); Issue.record("Desktop send allowed") } catch { #expect(error.localizedDescription.contains("View-only")) }
        controller.observeDesktopSessions([session])
        var old = session; old.origin = .unknown
        do { try await controller.resumeImported(old); Issue.record("Stale session resumed") } catch { #expect(error.localizedDescription.contains("View-only")) }
        do { try await controller.send(id: id, prompt: "Never send"); Issue.record("ID send allowed") } catch { #expect(error.localizedDescription.contains("View-only")) }
        #expect(await transport.calls == 0)
    }
    @Test func symlinkOutsideTranscriptRootsIsRejected() throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        let outside = paths.metadata.deletingLastPathComponent().appendingPathComponent("outside.jsonl")
        try Data("private".utf8).write(to: outside)
        let link = paths.transcripts.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(!paths.permitsTranscript(link))
        let ref = ClaudeSessionReference(sessionID: id, transcriptPath: link.path, workingDirectory: "/tmp", observedAt: Date(), origin: .unknown)
        try ref.write(paths: paths)
        #expect(ClaudeSessionReference.read(paths: paths).isEmpty)
    }
    @Test func newestMetadataWinsWithoutDuplicatingCLIAndKeepsArchiveState() async throws {
        let paths = try fixture(); defer { try? FileManager.default.removeItem(at: paths.metadata.deletingLastPathComponent()) }
        try writeMetadata(paths); _ = try writeTranscript(paths)
        let newerID = "local_C3333333-3333-4333-8333-333333333333"
        let newer: [String: Any] = ["sessionId": newerID, "cliSessionId": id, "cwd": "/other/worktree", "title": "Renamed", "isArchived": true, "lastActivityAt": 1_800_000_000_000]
        try JSONSerialization.data(withJSONObject: newer).write(to: paths.metadata.appendingPathComponent(newerID + ".json"))
        let result = await library(paths).scan()
        #expect(result.sessions.count == 1)
        #expect(result.sessions.first?.title == "Renamed")
        #expect(result.sessions.first?.archived == true)
        #expect(result.sessions.first?.project == "/other/worktree")
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_DESKTOP_READ_PROBE"] == "1"))
    func localDiscoveryProbe() async throws {
        let result = await SessionLibrary().scan()
        let desktop = result.sessions.filter { $0.origin == .claudeDesktop }
        #expect(!desktop.isEmpty)
        #expect(Set(result.sessions.map(\.id)).count == result.sessions.count)
        print("Desktop read-only probe: \(desktop.count) sessions; \(desktop.filter { $0.url != nil }.count) readable transcripts; \(result.notices.filter { $0.hasPrefix("Claude Code Desktop") }.count) diagnostic notices")
        if let designated = desktop.first(where: { $0.project == "/private/tmp/diorama-desktop-probe" }) {
            let transcript = SessionLibrary.readTranscript(url: try #require(designated.url), provider: .claude)
            #expect(transcript.entries.contains { $0.text.contains("DIORAMA_DESKTOP_PROBE_1_DONE") })
            print("Designated Desktop transcript marker verified")
        }
    }
}
