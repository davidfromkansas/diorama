import Foundation
import Testing
@testable import DioramaCore

/// Opt-in checks of designated disposable source sessions. No source task execution.
struct LiveOutputAcceptanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_CLAUDE_OUTPUT_ACCEPTANCE"] != nil))
    func claudeThreeTurnsRetainToolsFilesAndSessionMetrics() async throws {
        let id = try #require(ProcessInfo.processInfo.environment["DIORAMA_CLAUDE_OUTPUT_ACCEPTANCE"])
        let sessions = await SessionLibrary().scan().sessions
        let session = try #require(sessions.first { $0.sessionID == id && $0.classification != .subagent })
        let observer = ExternalSessionObserver()
        let snapshot = await observer.read(session, limit: 1000, hookDirectory: nil)
        #expect(snapshot.error == nil)
        let entries = snapshot.transcript.entries
        #expect(entries.filter { $0.claude?.toolName == "Read" }.count >= 18)
        for turn in 1...3 {
            #expect(entries.contains { $0.claude?.outputs.contains(where: { $0.name.hasSuffix("\(turn).html") }) == true })
        }
        #expect(entries.contains { $0.claude?.category == "sessionUsage" })
        #expect(snapshot.transcript.unrecognizedTypes["cost-state/cost-state"] == nil)
        #expect(snapshot.transcript.unrecognizedTypes["mode/mode"] == nil)
        let tool = try #require(entries.first { ($0.sourceRecords?.count ?? 0) >= 2 })
        for reference in tool.sourceRecords ?? [] { _ = try await reference.load(characterLimit: 4096) }
        #expect(snapshot.activity.state == .finished)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_DESKTOP_OUTPUT_ACCEPTANCE"] != nil))
    func claudeDesktopThreeTurnsRetainCorrelatedOutputs() async throws {
        let id = try #require(ProcessInfo.processInfo.environment["DIORAMA_DESKTOP_OUTPUT_ACCEPTANCE"])
        let sessions = await SessionLibrary().scan().sessions
        let session = try #require(sessions.first { $0.sessionID == id && $0.classification != .subagent })
        let snapshot = await ExternalSessionObserver().read(session, limit: 1000, hookDirectory: nil)
        #expect(snapshot.error == nil)
        let entries = snapshot.transcript.entries
        #expect(entries.filter { $0.claude?.toolName == "Read" }.count >= 18)
        for turn in 1...3 {
            #expect(entries.contains { $0.kind == "Assistant" && $0.text.contains("VIEWER_V2_DESKTOP_T\(turn)_DONE") })
            let output = try #require(entries.first { $0.claude?.outputs.contains(where: { $0.name == "acceptance-desktop-\(turn).html" }) == true })
            #expect((output.sourceRecords?.count ?? 0) >= 2)
            for reference in output.sourceRecords ?? [] { _ = try await reference.load(characterLimit: 4096) }
        }
        #expect(snapshot.activity.state == .finished)
        // Desktop does not necessarily persist CLI cost-state records.
        // Never require one client's metric format to pass another client's gate.
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_CODEX_OUTPUT_ACCEPTANCE"] != nil))
    func codexThreeTurnsRetainNativeCommandsAndFiles() async throws {
        let id = try #require(ProcessInfo.processInfo.environment["DIORAMA_CODEX_OUTPUT_ACCEPTANCE"])
        let sessions = await SessionLibrary().scan().sessions
        let session = try #require(sessions.first { $0.sessionID == id && $0.classification != .subagent })
        let observer = ExternalSessionObserver()
        let snapshot = await observer.read(session, limit: 1000, hookDirectory: nil)
        #expect(snapshot.error == nil)
        let entries = snapshot.transcript.entries
        #expect(entries.filter { $0.tool?.type == "commandExecution" }.count >= 18)
        for turn in 1...3 {
            #expect(entries.contains { $0.text.contains("VIEWER_V2_CODEX_T\(turn)_DONE") })
        }
        #expect(entries.contains { $0.codex?.category == "usage" })
        let reference = try #require(entries.first(where: { $0.tool != nil })?.sourceRecords?.first)
        _ = try await reference.load(characterLimit: 4096)
        #expect(snapshot.activity.state == .finished)
    }
}
