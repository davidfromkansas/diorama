import SwiftUI

/// Changes only paint, keeping hit targets and layout stable during interaction.
struct HoverButtonStyle: ButtonStyle {
    var inset: CGFloat = 6
    var radius: CGFloat = 6
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, inset: inset, radius: radius, prominent: prominent)
    }
    private struct Content: View {
        let configuration: Configuration
        let inset: CGFloat
        let radius: CGFloat
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            let opacity = enabled ? (configuration.isPressed ? 0.12 : hovered ? 0.065 : 0) : 0
            configuration.label
                .padding(.horizontal, inset).padding(.vertical, inset == 0 ? 0 : 3)
                .background(prominent ? Color.clear : Color.primary.opacity(opacity), in: RoundedRectangle(cornerRadius: radius))
                .overlay {
                    if prominent { RoundedRectangle(cornerRadius: radius).fill(Color.black.opacity(opacity)).allowsHitTesting(false) }
                }
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .onHover { hovered = $0 }
        }
    }
}

struct HoverControlSurface: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.padding(4)
            .background(Color.primary.opacity(enabled && hovered ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovered = $0 }
    }
}
