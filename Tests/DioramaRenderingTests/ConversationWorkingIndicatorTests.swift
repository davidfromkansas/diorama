import Testing
@testable import DioramaApp
import DioramaCore

@MainActor struct ConversationWorkingIndicatorTests {
    @Test func immediateSendingAndAcknowledgedWork() {
        #expect(ConversationWorkingState.resolve(phase: nil, attached: false, pending: true, blocked: false) == .sending)
        #expect(ConversationWorkingState.resolve(phase: .submitting, attached: true, pending: false, blocked: false) == .sending)
        #expect(ConversationWorkingState.resolve(phase: .working, attached: true, pending: false, blocked: false) == .working)
    }
    @Test(arguments: [ExecutionPhase.ready, .finished, .interrupted, .failed, .disconnected, .approval, .input])
    func inactiveOrWaitingDoesNotPretendToWork(_ phase: ExecutionPhase) {
        #expect(ConversationWorkingState.resolve(phase: phase, attached: true, pending: false, blocked: false) == nil)
    }
    @Test func observationsAndRequestsDoNotAnimate() {
        #expect(ConversationWorkingState.resolve(phase: .working, attached: false, pending: false, blocked: false) == nil)
        #expect(ConversationWorkingState.resolve(phase: .working, attached: true, pending: true, blocked: true) == nil)
        #expect(ConversationWorkingState.resolve(phase: .disconnected, attached: true, pending: true, blocked: false) == nil)
    }
}
