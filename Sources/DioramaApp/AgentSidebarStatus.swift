import SwiftUI
import DioramaCore

/// Sidebar-only presentation: provider lifecycle and office placement remain unchanged.
enum AgentSidebarStatus: Int, CaseIterable {
    case blocked, working, done, unknown, idle
    var label: String { ["Blocked", "Working", "Done", "Unknown", "Idle"][rawValue] }
    static func resolve(_ agent: WorkspaceAgent, viewed: Bool) -> Self {
        if agent.status == .waiting { return .blocked }
        if agent.status == .failed || agent.status == .stopped { return viewed ? .idle : .blocked }
        if agent.status == .done { return viewed ? .idle : .done }
        if agent.isWorking { return .working }
        if agent.status == .ready && ![.unavailable, .unverified].contains(agent.freshness) { return .idle }
        return .unknown
    }
}

@Observable @MainActor final class AgentCompletionViews {
    static let shared = AgentCompletionViews()
    private(set) var revision = 0
    private let defaults: UserDefaults
    private var viewed: [String: Bool]
    private var explicitlyViewed: Set<String>
    private(set) var confirmed: Set<String> = []
    struct Completion: Equatable { var id: String; var date: Date }
    private(set) var latest: [String: Completion] = [:]
    @ObservationIgnored private var saveQueued = false
    let baseline: Date
    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        let saved = defaults.double(forKey: "agentCompletionBaseline.v1")
        baseline = saved == 0 ? now : Date(timeIntervalSince1970: saved)
        defaults.set(baseline.timeIntervalSince1970, forKey: "agentCompletionBaseline.v1")
        explicitlyViewed = Set(defaults.stringArray(forKey: "agentExplicitViews.v1") ?? [])
        viewed = defaults.dictionary(forKey: "agentCompletionViews.v1") as? [String: Bool] ?? [:]
    }
    func isViewed(_ agent: WorkspaceAgent) -> Bool {
        guard [.done, .failed, .stopped].contains(agent.status), let key = agent.completionKey else { return agent.status != .failed && agent.status != .stopped }
        if let value = viewed[key] { return value }
        let evidenceTime = agent.meaningfulUpdatedAt ?? agent.observedAt
        let historical = evidenceTime.map { $0 < baseline } ?? (agent.freshness != .live)
        viewed[key] = historical
        persist(); return historical
    }
    func register(_ updates: [InboxUpdate], provider: String, session: String) {
        var changed = false
        let source = provider + ":" + session
        for update in updates {
            if confirmed.insert(update.id).inserted { changed = true }
            if latest[source] == nil || update.date >= latest[source]!.date {
                let value = Completion(id: update.id, date: update.date)
                if latest[source] != value { latest[source] = value; changed = true }
            }
        }
        if changed { revision += 1 }
    }
    func seed(_ key: String, unread: Bool, historicalUnread: Bool = false) {
        guard !explicitlyViewed.contains(key), viewed[key] != !unread else { return }
        // Inbox reading is not proof of viewport visibility; only unread evidence promotes.
        guard viewed[key] == nil || (unread && historicalUnread) else { return }
        viewed[key] = !unread; persist(); revision += 1
    }
    func mark(_ key: String) {
        guard !explicitlyViewed.contains(key) else { return }
        explicitlyViewed.insert(key); viewed[key] = true; persist(); revision += 1
    }
    private func persist() {
        guard !saveQueued else { return }; saveQueued = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }
    func flush() { saveQueued = false; defaults.set(viewed, forKey: "agentCompletionViews.v1"); defaults.set(Array(explicitlyViewed), forKey: "agentExplicitViews.v1") }
}

/// Checks actual native clipping, not LazyVStack prefetch/onAppear. No polling.
struct AgentCompletionVisibility: NSViewRepresentable {
    var key: String?
    var active: Bool
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.key = key; view.active = active; view.schedule() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }
    final class Probe: NSView {
        var key: String?
        var active = false
        private var tokens: [NSObjectProtocol] = []
        private var queued = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); observe(); schedule() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); observe(); schedule() }
        override func layout() { super.layout(); schedule() }
        func stop() { tokens.forEach(NotificationCenter.default.removeObserver); tokens = [] }
        private func observe() {
            stop()
            let observations: [(Notification.Name, AnyObject?)] = [(NSView.boundsDidChangeNotification, enclosingScrollView?.contentView), (NSWindow.didBecomeKeyNotification, window)]
            for (name, object) in observations where object != nil {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.schedule() }
                })
            }
        }
        func schedule() {
            guard !queued else { return }; queued = true
            DispatchQueue.main.async { [weak self] in self?.queued = false; self?.check() }
        }
        static func completionVisible(_ rect: NSRect, in clip: NSRect) -> Bool {
            rect.width > 0 && rect.height > 0 && rect.intersects(clip) && rect.maxY > clip.minY && rect.maxY <= clip.maxY + 1
        }
        private func check() {
            guard active, let key, let window, window.isKeyWindow, window.attachedSheet == nil,
                  !isHiddenOrHasHiddenAncestor, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let rect = convert(bounds, to: document), clip = scroll.contentView.bounds
            // Require the bottom of the completion to be visible, even for long messages.
            guard Self.completionVisible(rect, in: clip) else { return }
            AgentCompletionViews.shared.mark(key)
        }
    }
}
