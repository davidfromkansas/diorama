import SwiftUI
import AppKit

/// One owner for bottom-following. Viewport movement itself never requests a pin.
struct ConversationScrollTracking: NSViewRepresentable {
    var followsLatest: Bool
    var revealRevision = 0
    var onOlderHistory: () -> Void = {}
    var onScrollBegan: () -> Void = {}
    var onUserScroll: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(onUserScroll: onUserScroll) }
    func updateNSView(_ view: Probe, context: Context) {
        view.onOlderHistory = onOlderHistory
        view.onScrollBegan = onScrollBegan
        view.onUserScroll = onUserScroll
        let resumed = (followsLatest && !view.followsLatest) || view.revealRevision != revealRevision
        view.revealRevision = revealRevision
        view.followsLatest = followsLatest && !view.userIsScrolling
        if resumed { view.schedulePin() }
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stopObserving() }

    final class Probe: NSView {
        var onOlderHistory: () -> Void = {}
        var onScrollBegan: () -> Void = {}
        var onUserScroll: (Bool) -> Void
        var followsLatest = true
        var revealRevision = 0
        private(set) var userIsScrolling = false
        private weak var observedScroll: NSScrollView?
        private var pinScheduled = false
        private var wheelMonitor: Any?
        private var scrollEnd: DispatchWorkItem?
        init(onUserScroll: @escaping (Bool) -> Void) {
            self.onUserScroll = onUserScroll
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            schedulePin()
            for name in [NSScrollView.willStartLiveScrollNotification, NSScrollView.didLiveScrollNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(didScroll(_:)), name: name, object: nil)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(endedScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: nil)
            // Catch the first trackpad/mouse-wheel delta before layout can pin it back.
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, let scroll = self.enclosingScrollView,
                      scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)),
                      event.scrollingDeltaY != 0 || !event.phase.isEmpty || !event.momentumPhase.isEmpty else { return event }
                self.beginUserScroll()
                self.scheduleEndOfScroll()
                return event
            }
        }
        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
            observedScroll = nil
            scrollEnd?.cancel(); scrollEnd = nil
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor); self.wheelMonitor = nil }
            userIsScrolling = false
        }
        func schedulePin() {
            guard !pinScheduled else { return }
            pinScheduled = true
            settlePin(remaining: 2)
        }
        private func settlePin(remaining: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (remaining == 2 ? 0 : 0.06)) { [weak self] in
                guard let self else { return }
                defer {
                    if remaining > 0 && self.followsLatest && !self.userIsScrolling && self.window != nil {
                        self.settlePin(remaining: remaining - 1)
                    } else { self.pinScheduled = false }
                }
                guard self.window != nil, let scroll = self.enclosingScrollView,
                      let document = scroll.documentView else { return }
                if self.observedScroll !== scroll {
                    self.observedScroll = scroll
                    document.postsFrameChangedNotifications = true
                    scroll.contentView.postsFrameChangedNotifications = true
                    NotificationCenter.default.addObserver(self, selector: #selector(self.contentChanged(_:)), name: NSView.frameDidChangeNotification, object: document)
                    NotificationCenter.default.addObserver(self, selector: #selector(self.contentChanged(_:)), name: NSView.frameDidChangeNotification, object: scroll.contentView)
                }
                guard self.followsLatest, !self.userIsScrolling else { return }
                let bottom = max(document.bounds.minY, document.bounds.maxY - scroll.contentView.bounds.height)
                if abs(scroll.contentView.bounds.minY - bottom) > 0.5 {
                    scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: bottom))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
        }
        @objc private func contentChanged(_ notification: Notification) {
            if followsLatest && !userIsScrolling { schedulePin() }
        }
        private func beginUserScroll() {
            scrollEnd?.cancel()
            if !userIsScrolling { onScrollBegan() }
            userIsScrolling = true
            if followsLatest { followsLatest = false; onUserScroll(false) }
        }
        private func scheduleEndOfScroll() {
            scrollEnd?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let scroll = self.enclosingScrollView, let document = scroll.documentView else { return }
                self.userIsScrolling = false
                let remaining = max(0, document.bounds.maxY - scroll.contentView.bounds.maxY)
                self.followsLatest = remaining <= 4
                self.onUserScroll(self.followsLatest)
                if scroll.contentView.bounds.minY < 500, !self.followsLatest { self.onOlderHistory() }
            }
            scrollEnd = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        @objc private func didScroll(_ notification: Notification) {
            guard let scroll = notification.object as? NSScrollView, enclosingScrollView === scroll else { return }
            beginUserScroll()
            if notification.name == NSScrollView.didLiveScrollNotification { scheduleEndOfScroll() }
        }
        @objc private func endedScroll(_ notification: Notification) {
            guard let scroll = notification.object as? NSScrollView, enclosingScrollView === scroll else { return }
            scheduleEndOfScroll()
        }
    }
}
