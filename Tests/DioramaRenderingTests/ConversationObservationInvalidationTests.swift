import Foundation
import Observation
import Testing
@testable import DioramaApp
@testable import DioramaCore

private final class InvalidationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func mark() { lock.lock(); defer { lock.unlock() }; value = true }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor struct ConversationObservationInvalidationTests {
    private var session: Session {
        Session(id: "Codex:observed", provider: .codex, url: URL(fileURLWithPath: "/tmp/observed.jsonl"), sessionID: "observed", title: "Observed", project: "/tmp", modified: .distantPast, bytes: 0, archived: false, parentID: nil)
    }
    @Test func cachedHistoryDoesNotObserveBackgroundReadMarker() {
        let model = LibraryModel(execution: ExecutionController(transport: MessagesFixtureTransport()))
        model.transcriptSessionID = session.id
        model.transcript.entries = [Entry(id: "answer", kind: "Assistant", text: "Answer", timestamp: nil)]
        let invalidated = InvalidationFlag()
        withObservationTracking {
            #expect(!model.historyIsLoading(session))
        } onChange: { invalidated.mark() }
        model.readingTranscriptID = session.id
        model.readingTranscriptID = nil
        #expect(!invalidated.isSet)
    }
    @Test func unrelatedTranscriptChangesDoNotReadSelectedHistory() {
        #expect(!LibraryModel.affectsSelectedHistory(paths: ["/tmp/other.jsonl"], incoming: [], selected: session))
        #expect(LibraryModel.affectsSelectedHistory(paths: ["/tmp/observed.jsonl"], incoming: [], selected: session))
        let child = Session(id: "Codex:child", provider: .codex, url: nil, sessionID: "child", title: "Child", project: "/tmp", modified: .distantPast, bytes: 0, archived: false, parentID: session.sessionID)
        #expect(LibraryModel.affectsSelectedHistory(paths: ["/tmp/child.jsonl"], incoming: [child], selected: session))
        #expect(LibraryModel.affectsSelectedHistory(paths: ["/tmp"], incoming: [], selected: session))
    }
    @Test func unchangedActivityImportDoesNotPublishOrReplayEvents() async {
        let controller = ExecutionController(transport: MessagesFixtureTransport())
        var task = ExecutedTask(id: "observed", title: "Observed", folder: "/tmp", turnID: nil, attached: false)
        task.phase = .finished
        controller.tasks[task.id] = task
        let observed = task.session
        var transcript = Transcript()
        transcript.entries = [Entry(id: "plan", kind: "Proposed plan", text: "Inspect then verify", timestamp: nil)]
        await controller.importActivity(observed, transcript: transcript)
        let initial = controller.activitySnapshot(provider: .codex, id: task.id)
        #expect(!initial.records.isEmpty)
        let invalidated = InvalidationFlag()
        withObservationTracking {
            _ = controller.tasks
            _ = controller.recordedActivity
        } onChange: { invalidated.mark() }
        for _ in 0..<10 { await controller.importActivity(observed, transcript: transcript) }
        #expect(!invalidated.isSet)
        #expect(controller.activitySnapshot(provider: .codex, id: task.id) == initial)
        transcript.entries[0].text = "Updated proposal"
        await controller.importActivity(observed, transcript: transcript)
        #expect(invalidated.isSet)
        #expect(controller.activitySnapshot(provider: .codex, id: task.id).records.contains { $0.detail == "Updated proposal" })
    }
}
