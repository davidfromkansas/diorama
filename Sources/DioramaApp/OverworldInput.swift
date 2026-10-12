import AppKit
import SwiftUI

/// Scroll and pinch over the city map. SwiftUI on macOS 14 has no scroll-wheel modifier, so a
/// local event monitor catches them while the pointer is over the map and lets everything else
/// through. Clicks pass straight through this view.
struct OverworldInput: NSViewRepresentable {
    /// Two-finger scroll: pan by the delta. Mouse wheel or ⌘-scroll: zoom by the factor.
    var pan: (CGSize) -> Void
    var zoom: (Double, CGPoint) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.pan = pan; view.zoom = zoom
        return view
    }
    func updateNSView(_ view: InputView, context: Context) {
        view.pan = pan; view.zoom = zoom
    }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.stop() }

    final class InputView: NSView {
        var pan: (CGSize) -> Void = { _ in }
        var zoom: (Double, CGPoint) -> Void = { _, _ in }
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        private func handle(_ event: NSEvent) -> NSEvent? {
            // Popovers and sheets are their own windows, so their scrolling is never taken.
            guard let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }
            switch event.type {
            case .magnify:
                zoom(1 + event.magnification, location)
            case .scrollWheel where event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas:
                let step = event.hasPreciseScrollingDeltas ? 0.01 : 0.08
                zoom(exp(event.scrollingDeltaY * step), location)
            case .scrollWheel:
                pan(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
            default:
                return event
            }
            return nil
        }
    }
}
