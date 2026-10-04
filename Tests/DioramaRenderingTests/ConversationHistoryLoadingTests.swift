import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationHistoryLoadingTests {
    private var session: Session {
        Session(id: "Codex:test", provider: .codex, url: nil, sessionID: "test", title: "History", project: "/tmp", modified: .distantPast, bytes: 0, archived: false, parentID: nil)
    }
    @Test func initialLoadRetryFailureAndEmptySuccessAreDistinct() {
        let model = LibraryModel()
        #expect(model.historyIsLoading(session))
        model.transcriptSessionID = session.id
        model.readingTranscriptID = session.id
        #expect(model.historyIsLoading(session))
        model.transcript.error = "No local transcript available"
        #expect(model.historyIsLoading(session))
        model.readingTranscriptID = nil
        #expect(!model.historyIsLoading(session))
        model.transcript.error = nil
        #expect(!model.historyIsLoading(session))
    }
    @Test func cachedHistoryDoesNotFlashLoaderDuringRefreshAndPauseStopsIt() {
        let model = LibraryModel()
        model.transcriptSessionID = session.id
        model.transcript.entries = [Entry(id: "message", kind: "Assistant", text: "Saved answer", timestamp: nil)]
        model.readingTranscriptID = session.id
        #expect(!model.historyIsLoading(session))
        model.transcriptSessionID = "another-session"
        #expect(model.historyIsLoading(session))
        model.paused = true
        #expect(!model.historyIsLoading(session))
    }
}
