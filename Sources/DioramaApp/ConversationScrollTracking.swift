import SwiftUI
import AppKit

/// One owner for bottom-following. Viewport movement itself never requests a pin.
struct ConversationScrollTracking: NSViewRepresentable {
    var followsLatest: Bool
    var revealRevision = 0
    /// Glide to new rows instead of jumping (while the agent is working and writing).
    var animated = false
    var onOlderHistory: () -> Void = {}
    var onScrollBegan: () -> Void = {}
    var onUserScroll: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(onUserScroll: onUserScroll) }
    func updateNSView(_ view: Probe, context: Context) {
        view.onOlderHistory = onOlderHistory
        view.onScrollBegan = onScrollBegan
        view.onUserScroll = onUserScroll
        view.animatesPin = animated
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
        var animatesPin = false
        /// Where an animated pin is gliding to, so repeated pins don't restart it.
        private var glideTarget: CGFloat?
        private(set) var userIsScrolling = false
        private weak var observedScroll: NSScrollView?
        private var conversationScrollView: NSScrollView? {
            if let enclosingScrollView { return enclosingScrollView }
            if let observedScroll, observedScroll.window === window { return observedScroll }
            // List installs its native scroll view beside the background probe.
            func find(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = find(view) { return scroll }
                ancestor = view.superview
            }
            return nil
        }
        private var pinScheduled = false
        private var wheelMonitor: Any?
        private var scrollEnd: DispatchWorkItem?
        private var lifecycle = 0
        private var requestedOlderInRegion = false
        private var olderCheckScheduled = false
        init(onUserScroll: @escaping (Bool) -> Void) {
            self.onUserScroll = onUserScroll
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            startObserving()
        }
        override func viewDidHide() { super.viewDidHide(); stopObserving() }
        override func viewDidUnhide() { super.viewDidUnhide(); startObserving() }
        private func startObserving() {
            stopObserving()
            guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
            schedulePin()
            NotificationCenter.default.addObserver(self, selector: #selector(scrollBoundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: nil)
            for name in [NSScrollView.willStartLiveScrollNotification, NSScrollView.didLiveScrollNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(didScroll(_:)), name: name, object: nil)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(endedScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: nil)
            // Catch the first trackpad/mouse-wheel delta before layout can pin it back.
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, let scroll = self.conversationScrollView,
                      scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)),
                      event.scrollingDeltaY != 0 || !event.phase.isEmpty || !event.momentumPhase.isEmpty else { return event }
                self.beginUserScroll()
                self.scheduleOlderCheck()
                self.scheduleEndOfScroll()
                return event
            }
        }
        func stopObserving() {
            lifecycle += 1
            pinScheduled = false
            olderCheckScheduled = false
            requestedOlderInRegion = false
            NotificationCenter.default.removeObserver(self)
            observedScroll = nil
            scrollEnd?.cancel(); scrollEnd = nil
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor); self.wheelMonitor = nil }
            userIsScrolling = false
        }
        func schedulePin() {
            guard !pinScheduled else { return }
            pinScheduled = true
            settlePin(remaining: 2, lifecycle: lifecycle)
        }
        private func settlePin(remaining: Int, lifecycle token: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (remaining == 2 ? 0 : 0.06)) { [weak self] in
                guard let self, self.lifecycle == token else { return }
                defer {
                    if remaining > 0 && self.followsLatest && !self.userIsScrolling && self.window != nil {
                        self.settlePin(remaining: remaining - 1, lifecycle: token)
                    } else { self.pinScheduled = false }
                }
                guard self.window != nil, let scroll = self.conversationScrollView,
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
                let distance = abs(scroll.contentView.bounds.minY - bottom)
                guard distance > 0.5 else { return }
                // A short way (new rows while the agent works) glides; opening, sending or a long
                // way back jumps.
                if self.animatesPin, distance < scroll.contentView.bounds.height * 1.5, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    if let target = self.glideTarget, abs(target - bottom) < 0.5 { return }
                    self.glideTarget = bottom
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.3
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        context.allowsImplicitAnimation = true
                        scroll.contentView.animator().setBoundsOrigin(NSPoint(x: scroll.contentView.bounds.minX, y: bottom))
                    }, completionHandler: { [weak self] in
                        guard let self else { return }
                        self.glideTarget = nil
                        scroll.reflectScrolledClipView(scroll.contentView)
                        // Rows that arrived during the glide.
                        if self.followsLatest && !self.userIsScrolling { self.schedulePin() }
                    })
                } else {
                    self.glideTarget = nil
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
            let began = !userIsScrolling
            if began { requestedOlderInRegion = false }
            let detached = followsLatest
            // Stop native pinning immediately, but never publish SwiftUI state from
            // an AppKit scroll/layout notification. A callback can itself lay out rows.
            userIsScrolling = true
            followsLatest = false
            if glideTarget != nil, let clip = conversationScrollView?.contentView {
                glideTarget = nil
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    clip.animator().setBoundsOrigin(clip.bounds.origin)
                }
            }
            guard began || detached else { return }
            let token = lifecycle
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifecycle == token, self.window != nil else { return }
                if began { self.onScrollBegan() }
                if detached { self.onUserScroll(false) }
            }
        }
        @objc private func scrollBoundsChanged(_ notification: Notification) {
            guard userIsScrolling, let scroll = conversationScrollView,
                  notification.object as? NSClipView === scroll.contentView else { return }
            scheduleOlderCheck()
        }
        private func scheduleOlderCheck() {
            guard !olderCheckScheduled else { return }
            olderCheckScheduled = true
            let token = lifecycle
            // Defer out of AppKit's scroll/layout stack and coalesce momentum events.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifecycle == token else { return }
                self.olderCheckScheduled = false
                guard self.userIsScrolling, let scroll = self.conversationScrollView,
                      let document = scroll.documentView else { return }
                let distance = scroll.contentView.bounds.minY - document.bounds.minY
                if distance >= 500 { self.requestedOlderInRegion = false; return }
                guard !self.requestedOlderInRegion else { return }
                self.requestedOlderInRegion = true
                self.onOlderHistory()
            }
        }
        private func scheduleEndOfScroll() {
            scrollEnd?.cancel()
            let token = lifecycle
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.lifecycle == token, self.window != nil, let scroll = self.conversationScrollView, let document = scroll.documentView else { return }
                self.userIsScrolling = false
                let remaining = max(0, document.bounds.maxY - scroll.contentView.bounds.maxY)
                self.followsLatest = remaining <= 4
                self.onUserScroll(self.followsLatest)

            }
            scrollEnd = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        @objc private func didScroll(_ notification: Notification) {
            guard let scroll = notification.object as? NSScrollView, conversationScrollView === scroll else { return }
            beginUserScroll()
            scheduleOlderCheck()
            if notification.name == NSScrollView.didLiveScrollNotification { scheduleEndOfScroll() }
        }
        @objc private func endedScroll(_ notification: Notification) {
            guard let scroll = notification.object as? NSScrollView, conversationScrollView === scroll else { return }
            scheduleEndOfScroll()
        }
    }
}
