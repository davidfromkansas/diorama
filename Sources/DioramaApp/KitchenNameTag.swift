import AppKit
import DioramaCore
import QuartzCore

/// What a chef's name tag shows: a short task name. Checklist progress shows as a bar between the
/// tag and the chef (`ChefProgressView`); needing you, a dish ready, as an emote above it.
struct ChefTagContent: Equatable {
    var text: String
    /// The whole task, for the tooltip and accessibility.
    var fullText: String
    /// Checklist progress for the current turn, when the agent keeps one (drawn by the bar).
    var progress: Double?
    /// Last known rather than live: drawn faded.
    var stale: Bool
    /// Resting in the break room: shown only on hover.
    var resting: Bool
    /// Where its pull request stands, as a coloured badge after the name.
    var badge: Badge? = nil
    enum Badge: Equatable {
        case readyToMerge, needsFix, testing, other(String)
        var text: String {
            switch self { case .readyToMerge: "Ready to merge"; case .needsFix: "Needs a fix"; case .testing: "Testing…"; case .other(let text): text }
        }
        var colors: (fill: NSColor, text: NSColor) {
            switch self {
            case .readyToMerge: (NSColor(red: 0.85, green: 0.95, blue: 0.87, alpha: 1), NSColor(red: 0.08, green: 0.45, blue: 0.21, alpha: 1))
            case .needsFix: (NSColor(red: 0.99, green: 0.88, blue: 0.86, alpha: 1), NSColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 1))
            case .testing: (NSColor(red: 0.88, green: 0.92, blue: 1.0, alpha: 1), NSColor(red: 0.11, green: 0.36, blue: 0.82, alpha: 1))
            case .other: (NSColor(white: 0.92, alpha: 1), NSColor(white: 0.3, alpha: 1))
            }
        }
        static func make(_ review: KitchenReviews.State?, note: String?) -> Badge? {
            switch review {
            case .needsFix: return .needsFix
            case .checking: return .testing
            case .shipped: return note == nil || note == "Ready to merge" ? .readyToMerge : .other(note!)
            default: return nil
            }
        }
    }

    static func make(_ agent: SpatialAgent, review: KitchenReviews.State?, note: String? = nil, now: Date = Date(), labels: TaskLabels = .shared) -> ChefTagContent {
        let value = agent.value
        let work = KitchenLayout.work(for: value, review: review)
        // Only a list kept this turn fills the line; the tag stays quiet otherwise.
        var progress: Double?
        if case .steps = value.planProgress { progress = value.planProgress.fraction }
        // A four-word summary of what the chef works on now: the task, updated by each turn's request.
        let task = TaskTitle.full(value.task)
        let short = labels.label(agent: agent.id, for: task, latest: value.latestRequest, provider: value.provider.lowercased().contains("claude") ? .claude : .codex)
        return ChefTagContent(text: short.isEmpty ? value.name : short, fullText: task.isEmpty ? value.name : task,
                              progress: progress, stale: !agent.fresh, resting: work.area == "break",
                              badge: value.status == .working ? nil : Badge.make(review, note: note))
    }
}

/// A chef's name tag: the short task name (scrolling at a calm pace if it is still too long).
final class ChefTagView: NSView {
    static let maxTextWidth: CGFloat = 150
    static let scrollSpeed: CGFloat = 35 // points per second
    static let edgePause: CFTimeInterval = 1.5
    private let clip = NSView()
    private let label = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private(set) var content: ChefTagContent?
    private var reducedMotion = false
    var text: String { label.stringValue }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        clip.wantsLayer = true; clip.layer?.masksToBounds = true
        addSubview(clip)
        label.font = .systemFont(ofSize: 10, weight: .semibold); label.textColor = NSColor(white: 0.18, alpha: 1)
        label.wantsLayer = true; label.lineBreakMode = .byClipping
        clip.addSubview(label)
        badge.font = .systemFont(ofSize: 9, weight: .bold); badge.wantsLayer = true
        badge.alignment = .center; badge.isHidden = true
        addSubview(badge)
        needsDisplay = true
    }
    // The backing layer can be replaced when the tag joins the kitchen's view, so its look is
    // applied here rather than once at init.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 5
        layer.backgroundColor = NSColor.white.withAlphaComponent(0.93).cgColor
        layer.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor; layer.borderWidth = 0.5
        layoutTag()
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutTag() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var textWidth: CGFloat { ceil(label.attributedStringValue.size().width) }
    /// The tag's size for its current content.
    var tagSize: NSSize { NSSize(width: 8 + min(Self.maxTextWidth, textWidth) + 8 + badgeRoom, height: 17) }
    private var badgeWidth: CGFloat { badge.isHidden ? 0 : ceil(badge.attributedStringValue.size().width) + 10 }
    private var badgeRoom: CGFloat { badge.isHidden ? 0 : badgeWidth + 2 }

    func update(_ content: ChefTagContent, reducedMotion: Bool) {
        guard content != self.content || reducedMotion != self.reducedMotion else { return }
        let textChanged = content.text != self.content?.text || reducedMotion != self.reducedMotion
        self.content = content; self.reducedMotion = reducedMotion
        label.stringValue = content.text
        if let value = content.badge {
            badge.stringValue = value.text; badge.textColor = value.colors.text
            badge.layer?.backgroundColor = value.colors.fill.cgColor; badge.layer?.cornerRadius = 4
            badge.isHidden = false
        } else { badge.isHidden = true }
        alphaValue = content.stale ? 0.6 : 1
        let described = content.fullText + (content.badge.map { ". " + $0.text } ?? "")
        setAccessibilityLabel(described); toolTip = described
        layoutTag()
        if textChanged { restartMarquee() }
    }

    override func layout() { super.layout(); layoutTag() }

    private func layoutTag() {
        let height: CGFloat = 17
        let visible = min(Self.maxTextWidth, textWidth)
        clip.frame = NSRect(x: 7, y: 2, width: visible + 2, height: height - 3)
        label.frame = NSRect(x: 0, y: -1, width: textWidth + 4, height: height - 2)
        badge.frame = NSRect(x: 8 + visible + 6, y: 2.5, width: badgeWidth, height: height - 5)
    }

    /// Long tasks scroll to the end and back, pausing at each end (still under Reduce Motion).
    private func restartMarquee() {
        label.layer?.removeAnimation(forKey: "marquee")
        let overflow = textWidth - Self.maxTextWidth
        guard overflow > 1, !reducedMotion else { return }
        let travel = CFTimeInterval(overflow / Self.scrollSpeed), pause = Self.edgePause
        let total = pause + travel + pause + travel
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -overflow, -overflow, 0]
        scroll.keyTimes = [0, pause / total, (pause + travel) / total, (pause + travel + pause) / total, 1].map { NSNumber(value: $0) }
        scroll.duration = total; scroll.repeatCount = .infinity
        scroll.calculationMode = .linear
        label.layer?.add(scroll, forKey: "marquee")
    }
}

/// The checklist progress bar between a chef's name tag and its head: only while the agent keeps
/// a list this turn (hidden otherwise), filling as steps are done.
final class ChefProgressView: NSView {
    static let size = NSSize(width: 46, height: 6)
    private let track = BarSegment(color: NSColor(white: 0.1, alpha: 0.55)), fill = BarSegment(color: NSColor(red: 0.27, green: 0.85, blue: 0.5, alpha: 1))
    private(set) var fraction: Double?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: frame.origin, size: Self.size))
        wantsLayer = true
        // Views, not loose sublayers: inside the kitchen's layer tree, hand-added layers were scaled.
        addSubview(track); addSubview(fill)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ fraction: Double?) {
        guard fraction != self.fraction else { return }
        self.fraction = fraction
        setAccessibilityLabel(fraction.map { "\(Int(($0 * 100).rounded())) percent of the checklist done" })
        needsLayout = true
    }
    override func layout() {
        super.layout()
        track.frame = bounds.insetBy(dx: 0, dy: 1)
        let inner = track.frame.insetBy(dx: 1, dy: 1)
        fill.frame = CGRect(x: inner.minX, y: inner.minY, width: max(inner.height, inner.width * CGFloat(min(1, max(0, fraction ?? 0)))), height: inner.height)
        fill.isHidden = (fraction ?? 0) <= 0
    }
}

private final class BarSegment: NSView {
    let color: NSColor
    init(color: NSColor) { self.color = color; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = color.cgColor; layer?.cornerRadius = min(bounds.height, bounds.width) / 2 }
    override func layout() { super.layout(); needsDisplay = true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
