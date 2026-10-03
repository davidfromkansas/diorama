import SwiftUI

/// Native skeleton treatment inspired by generativeloaders.com; no web runtime.
struct ConversationHistoryLoader: View {
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                if reducedMotion || scenePhase != .active {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading conversation history…").font(.callout.weight(.medium))
                    Text("Retrieving earlier messages and agent activity.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !compact {
                VStack(alignment: .leading, spacing: 24) {
                    HStack { Spacer(minLength: 60); skeleton(width: 0.65, lines: 2) }
                    skeleton(width: 0.9, lines: 3)
                    skeleton(width: 0.72, lines: 2)
                }.accessibilityHidden(true)
            }
        }
        .padding(compact ? 12 : 24)
        .frame(maxWidth: compact ? .infinity : 560, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversation history. Retrieving earlier messages and agent activity.")
    }

    private func skeleton(width: CGFloat, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<lines, id: \.self) { line in
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: geometry.size.width * (line == lines - 1 ? width * 0.7 : width))
                }.frame(height: 10)
            }
        }
    }
}
