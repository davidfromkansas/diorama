import Testing
import Foundation
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct CanvasActivityTests {
    @Test func observedActivityExpiresAndNeverOverridesMissingEvidence() {
        let now = Date()
        var event = ActivityEvent(id: "start", provider: "Codex", sessionID: "observed", kind: "started", source: "history", recordedAt: now, state: .working)
        #expect(CanvasActivity.observedPhase(.init(events: [event]), now: now) == .working)
        #expect(CanvasActivity.observedPhase(.init(events: [event]), now: now.addingTimeInterval(91)) == nil)
        event.state = .finished
        #expect(CanvasActivity.observedPhase(.init(events: [event]), now: now) == .finished)
        event.recordedAt = nil
        #expect(CanvasActivity.observedPhase(.init(events: [event]), now: now) == nil)
        #expect(CanvasActivity.observedPhase(.init(events: [], error: "Read failed"), now: now) == nil)
    }
    @Test func onlyUnfinishedCallsInAttachedCurrentTurnAreLive() {
        var task = ExecutedTask(id: "task", title: "Task", folder: "/tmp", phase: .working, turnID: "current", attached: true)
        func event(_ id: String, _ kind: String, _ call: String, turn: String = "current") -> ActivityEvent {
            ActivityEvent(id: id, provider: "Codex", sessionID: "task", kind: kind, source: "test", turnID: turn, callID: call, tool: "commandExecution", detail: "swift test")
        }
        task.activity = [event("1", "toolStarted", "old", turn: "previous"), event("2", "toolStarted", "a"), event("3", "toolStarted", "b"), event("4", "toolFinished", "a")]
        #expect(CanvasActivity.current(task).map(\.id) == ["b"])
        task.activity.append(event("5", "toolFailed", "b"))
        #expect(CanvasActivity.current(task).isEmpty)
        task.activity.append(event("6", "toolStarted", "c"))
        task.phase = .approval
        #expect(CanvasActivity.current(task).isEmpty)
        task.phase = .working; task.attached = false
        #expect(CanvasActivity.current(task).isEmpty)
    }
}
