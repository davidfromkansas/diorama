import SwiftUI
import DioramaCore

enum ConversationWorkingState: String {
    case sending = "Sending message"
    case working = "Agent is working"

    static func resolve(phase: ExecutionPhase?, attached: Bool, pending: Bool, blocked: Bool) -> Self? {
        guard !blocked else { return nil }
        if attached, phase == .approval || phase == .input || phase == .disconnected { return nil }
        if pending { return .sending }
        guard attached else { return nil }
        switch phase {
        case .submitting: return .sending
        case .working: return .working
        default: return nil
        }
    }
}

/// A small activity bubble, independent of transcript entries and provider wording.
struct ConversationWorkingIndicator: View {
    let state: ConversationWorkingState
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    private var animates: Bool { active && visible && !reducedMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { timeline in
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    let phase = timeline.date.timeIntervalSinceReferenceDate / 1.2 - Double(index) * 0.16
                    let pulse = animates ? (sin(phase * 2 * .pi) + 1) / 2 : 0.5
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + pulse * 0.55)
                        .offset(y: -pulse * 3)
                }
            }
            .frame(width: 43, height: 18)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottomLeading) {
                Circle().fill(Color.primary.opacity(0.07))
                    .frame(width: 7, height: 7).offset(x: 0, y: 3)
            }
        }
        .frame(height: 43, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.rawValue)
        .help(state.rawValue)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}
