import AppKit
import DioramaCore
import QuartzCore

/// What a chef's name tag shows: a short task name and the checklist progress line. What the
/// chef is doing (and needing you, a dish ready) shows as an emote above it (`KitchenEmote`).
struct ChefTagContent: Equatable {
    var text: String
    /// The whole task, for the tooltip and accessibility.
    var fullText: String
    /// Checklist progress for the current turn, when the agent keeps one.
    var progress: Double?
    /// Last known rather than live: drawn faded.
    var stale: Bool
    /// Resting in the break room: shown only on hover.
    var resting: Bool

    static let maxWords = 4

    static func make(_ agent: SpatialAgent, review: KitchenReviews.State?, now: Date = Date()) -> ChefTagContent {
        let value = agent.value
        let work = KitchenLayout.work(for: value, review: review)
        // Only a list kept this turn fills the line; the tag stays quiet otherwise.
        var progress: Double?
        if case .steps = value.planProgress { progress = value.planProgress.fraction }
        // The task's opening: its first line, up to the end of the first sentence.
        let firstLine = value.task.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let task = TaskTitle.full(firstLine).components(separatedBy: ". ").first ?? ""
        let short = shortTitle(task)
        return ChefTagContent(text: short.isEmpty ? value.name : short, fullText: task.isEmpty ? value.name : task,
                              progress: progress, stale: !agent.fresh, resting: work.area == "break")
    }

    /// At most `maxWords` words of the task, without a leading request ("can you…", "please…")
    /// and with "…" when words were cut.
    static func shortTitle(_ task: String) -> String {
        var text = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let requests = ["can you please", "could you please", "can you", "could you", "would you", "please", "i want you to", "i'd like you to", "let's", "lets", "help me", "go ahead and"]
        var stripped = true
        while stripped {
            stripped = false
            for request in requests where text.lowercased().hasPrefix(request + " ") {
                text = String(text.dropFirst(request.count)).trimmingCharacters(in: .whitespaces); stripped = true
            }
        }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return "" }
        var kept = words.prefix(maxWords).joined(separator: " ")
        while let last = kept.last, ".,;:!?—-".contains(last) { kept.removeLast() }
        if let first = kept.first, first.isLowercase { kept = first.uppercased() + kept.dropFirst() }
        return words.count > maxWords ? kept + "…" : kept
    }
}

/// A chef's name tag: the short task name (scrolling at a calm pace if it is still too long),
/// with a thin checklist progress line underneath.
final class ChefTagView: NSView {
    static let maxTextWidth: CGFloat = 150
    static let scrollSpeed: CGFloat = 35 // points per second
    static let edgePause: CFTimeInterval = 1.5
    private let clip = NSView()
    private let label = NSTextField(labelWithString: "")
    private let track = TagBar(color: NSColor.black.withAlphaComponent(0.08)), fill = TagBar(color: NSColor(red: 0.18, green: 0.7, blue: 0.42, alpha: 1))
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
        // Views, not loose sublayers: inside the kitchen's layer tree, hand-added layers were scaled.
        addSubview(track); addSubview(fill)
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
    var tagSize: NSSize { NSSize(width: 8 + min(Self.maxTextWidth, textWidth) + 8, height: content?.progress == nil ? 17 : 19) }

    func update(_ content: ChefTagContent, reducedMotion: Bool) {
        guard content != self.content || reducedMotion != self.reducedMotion else { return }
        let textChanged = content.text != self.content?.text || reducedMotion != self.reducedMotion
        self.content = content; self.reducedMotion = reducedMotion
        label.stringValue = content.text
        alphaValue = content.stale ? 0.6 : 1
        setAccessibilityLabel(content.fullText); toolTip = content.fullText
        layoutTag()
        if textChanged { restartMarquee() }
    }

    override func layout() { super.layout(); layoutTag() }

    private func layoutTag() {
        let height: CGFloat = 17
        let visible = min(Self.maxTextWidth, textWidth)
        clip.frame = NSRect(x: 7, y: 2, width: visible + 2, height: height - 3)
        label.frame = NSRect(x: 0, y: -1, width: textWidth + 4, height: height - 2)
        let progress = content?.progress
        track.isHidden = progress == nil; fill.isHidden = progress == nil
        let inset: CGFloat = 6, width = bounds.width - inset * 2
        // Along the bottom edge (the view is flipped, and so is its backing layer).
        let y = bounds.height - 3.5
        track.frame = CGRect(x: inset, y: y, width: max(0, width), height: 2)
        fill.frame = CGRect(x: inset, y: y, width: max(2, width * CGFloat(progress ?? 0)), height: 2)
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

/// One segment of a tag's progress line.
private final class TagBar: NSView {
    let color: NSColor
    init(color: NSColor) { self.color = color; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = color.cgColor; layer?.cornerRadius = 1 }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
