import AppKit
import SwiftUI

extension View {
    /// Non-intercepting native cursor rect; does not alter layout or actions.
    func disclosurePointingHand() -> some View { modifier(DisclosurePointerModifier()) }
    func pointingHand() -> some View { modifier(PointingHandModifier()) }
}
private struct DisclosurePointerModifier: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(enabled ? .link : .default)
        } else {
            content.background(PointingHandRegion(enabled: enabled).padding(.leading, -20).accessibilityHidden(true))
        }
    }
}
private struct PointingHandModifier: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @ViewBuilder
    func body(content: Content) -> some View {
        // Participate in SwiftUI's own cursor arbitration. Background AppKit cursor
        // rectangles alone can be superseded by the hosting view's arrow cursor.
        if #available(macOS 15.0, *) {
            content.pointerStyle(enabled ? .link : .default)
        } else {
            content.background(PointingHandRegion(enabled: enabled).accessibilityHidden(true))
        }
    }
}
struct PointingHandRegion: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> CursorRegionView { CursorRegionView() }
    func updateNSView(_ view: CursorRegionView, context: Context) { view.cursorEnabled = enabled }
    static func dismantleNSView(_ view: CursorRegionView, coordinator: ()) { view.cursorEnabled = false; view.discardCursorRects() }
}
final class CursorRegionView: NSView {
    var cursorEnabled = true { didSet { if oldValue != cursorEnabled { invalidate() } } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var interactiveRect: NSRect {
        guard cursorEnabled, !isHiddenOrHasHiddenAncestor else { return .zero }
        var ancestor: NSView? = self
        while let view = ancestor {
            if view.alphaValue <= 0 || view.layer?.opacity == 0 { return .zero }
            ancestor = view.superview
        }
        return visibleRect.intersection(bounds)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        let rect = interactiveRect
        if !rect.isEmpty { addCursorRect(rect, cursor: .pointingHand) }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); invalidate() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); invalidate() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); invalidate() }
    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); invalidate() }
    private func invalidate() { window?.invalidateCursorRects(for: self) }
}
