import SwiftUI

/// A workbench pane fills its viewport; its transcript must never determine the
/// viewport's ideal size. Unlike ZStack, this layout does not recursively measure
/// retained (including invisible) panes to negotiate their intrinsic dimensions.
struct WorkspacePaneStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions()
        return CGSize(width: size.width.isFinite ? max(0, size.width) : 0,
                      height: size.height.isFinite ? max(0, size.height) : 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let viewport = ProposedViewSize(width: bounds.width, height: bounds.height)
        for pane in subviews { pane.place(at: bounds.origin, anchor: .topLeading, proposal: viewport) }
    }
}
