import SwiftUI

/// Retain pane identity, but give every pane a concrete viewport before laying out
/// transcript content. A Layout's default alignment negotiation recursively asks
/// retained scroll views for their content dimensions, even when invisible.
struct WorkspacePaneStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .topLeading) {
                content()
                    .frame(width: max(0, viewport.size.width), height: max(0, viewport.size.height), alignment: .topLeading)
            }
            .frame(width: max(0, viewport.size.width), height: max(0, viewport.size.height), alignment: .topLeading)
            .clipped()
        }
    }
}
