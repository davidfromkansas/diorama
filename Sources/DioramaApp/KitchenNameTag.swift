import AppKit
import DioramaCore
import QuartzCore

/// What a chef's name tag shows (progressive disclosure: the task and one live icon here; the
/// rest is in the command bar when the chef is selected).
struct ChefTagContent: Equatable {
    enum Icon: String {
        case none, commentary, read, plan, edit, command, test, check, pantry, tool, help, ready
        var symbol: String? {
            switch self {
            case .none: nil
            case .commentary: "text.bubble.fill"
            case .read: "book.fill"
            case .plan: "list.clipboard.fill"
            case .edit: "scissors"
            case .command: "flame.fill"
            case .test: "testtube.2"
            case .check: "eye.fill"
            case .pantry: "cabinet.fill"
            case .tool: "wrench.and.screwdriver.fill"
            case .help: "hand.raised.fill"
            case .ready: "checkmark.circle.fill"
            }
        }
        var color: NSColor {
            switch self {
            case .help: .systemOrange
            case .ready: NSColor(red: 0.18, green: 0.7, blue: 0.42, alpha: 1)
            case .commentary: .systemBlue
            case .command: NSColor(red: 0.93, green: 0.45, blue: 0.16, alpha: 1)
            case .test, .check: .systemTeal
            case .pantry: .systemPurple
            default: NSColor(white: 0.3, alpha: 1)
            }
        }
    }
    var text: String
    var icon: Icon
    /// Checklist progress for the current turn, when the agent keeps one.
    var progress: Double?
    /// Last known rather than live: drawn faded.
    var stale: Bool
    /// Resting in the break room: shown only on hover.
    var resting: Bool

    /// Seconds a progress note keeps its speech-bubble icon before the tool icon returns.
    static let commentaryHold: TimeInterval = 3

    static func make(_ agent: SpatialAgent, review: KitchenReviews.State?, now: Date = Date()) -> ChefTagContent {
        let value = agent.value
        let work = KitchenLayout.work(for: value, review: review)
        let icon: Icon
        if agent.needsAttention || value.status == .failed || value.status == .waiting { icon = .help }
        else if work.area == "serving" { icon = .ready }
        else if value.status == .working {
            if let said = value.lastCommentaryAt, said >= (value.lastToolAt ?? .distantPast), now.timeIntervalSince(said) < commentaryHold { icon = .commentary }
            else {
                switch KitchenActivity.classify(tool: value.latestTool, detail: value.latestToolDetail) {
                case .researching: icon = value.latestTool.isEmpty ? .none : .read
                case .planning: icon = .plan
                case .editing: icon = .edit
                case .commands: icon = .command
                case .testing: icon = .test
                case .checking: icon = .check
                case .resources: icon = .pantry
                case .other: icon = value.latestTool.isEmpty ? .none : .tool
                }
            }
        } else { icon = .none }
        var progress: Double?
        if let plan = value.plan, plan.hasTasks, !plan.tasksPreviousTurn, !plan.checklist.isEmpty {
            progress = Double(plan.completedTaskCount) / Double(plan.checklist.count)
        }
        // The task's opening: its first line, up to the end of the first sentence.
        let firstLine = value.task.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let task = TaskTitle.full(firstLine).components(separatedBy: ". ").first ?? ""
        return ChefTagContent(text: task.isEmpty ? value.name : task, icon: icon, progress: progress,
                              stale: !agent.fresh, resting: work.area == "break")
    }
}

/// A chef's name tag: one live icon and the task, scrolling at a calm pace when it is too long,
/// with a thin checklist progress line underneath.
final class ChefTagView: NSView {
    static let maxTextWidth: CGFloat = 150
    static let scrollSpeed: CGFloat = 35 // points per second
    static let edgePause: CFTimeInterval = 1.5
    private let iconView = NSImageView()
    private let clip = NSView()
    private let label = NSTextField(labelWithString: "")
    private let track = CALayer(), fill = CALayer()
    private(set) var content: ChefTagContent?
    private var reducedMotion = false
    var text: String { label.stringValue }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        clip.wantsLayer = true; clip.layer?.masksToBounds = true
        addSubview(clip)
        label.font = .systemFont(ofSize: 10, weight: .semibold); label.textColor = NSColor(white: 0.18, alpha: 1)
        label.wantsLayer = true; label.lineBreakMode = .byClipping
        clip.addSubview(label)
        track.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        fill.backgroundColor = NSColor(red: 0.18, green: 0.7, blue: 0.42, alpha: 1).cgColor
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
        if track.superlayer !== layer { layer.addSublayer(track); layer.addSublayer(fill) }
        layoutTag()
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutTag() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var textWidth: CGFloat { ceil(label.attributedStringValue.size().width) }
    private var iconWidth: CGFloat { content?.icon.symbol == nil ? 0 : 15 }
    /// The tag's size for its current content.
    var tagSize: NSSize { NSSize(width: 8 + iconWidth + min(Self.maxTextWidth, textWidth) + 8, height: content?.progress == nil ? 17 : 19) }

    func update(_ content: ChefTagContent, reducedMotion: Bool) {
        guard content != self.content || reducedMotion != self.reducedMotion else { return }
        let textChanged = content.text != self.content?.text || reducedMotion != self.reducedMotion
        let iconChanged = content.icon != self.content?.icon
        self.content = content; self.reducedMotion = reducedMotion
        label.stringValue = content.text
        if iconChanged {
            if let symbol = content.icon.symbol {
                // Filled symbols (the check, the raised hand) draw their mark in white on the colour.
                let colors: [NSColor] = content.icon == .ready ? [.white, content.icon.color] : [content.icon.color]
                let config = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold).applying(.init(paletteColors: colors))
                iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: content.icon.rawValue)?.withSymbolConfiguration(config)
            } else { iconView.image = nil }
            // Needing you pulses until it's resolved.
            iconView.wantsLayer = true
            iconView.layer?.removeAnimation(forKey: "pulse")
            if content.icon == .help, !reducedMotion {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1; pulse.toValue = 0.35; pulse.duration = 0.7; pulse.autoreverses = true; pulse.repeatCount = .infinity
                iconView.layer?.add(pulse, forKey: "pulse")
            }
        }
        alphaValue = content.stale ? 0.6 : 1
        setAccessibilityLabel(content.text)
        layoutTag()
        if textChanged { restartMarquee() }
    }

    override func layout() { super.layout(); layoutTag() }

    private func layoutTag() {
        let height: CGFloat = 17
        iconView.frame = NSRect(x: 6, y: 3, width: 11, height: 11)
        iconView.isHidden = iconWidth == 0
        let visible = min(Self.maxTextWidth, textWidth)
        clip.frame = NSRect(x: 7 + iconWidth, y: 2, width: visible + 2, height: height - 3)
        label.frame = NSRect(x: 0, y: -1, width: textWidth + 4, height: height - 2)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let progress = content?.progress
        track.isHidden = progress == nil; fill.isHidden = progress == nil
        let inset: CGFloat = 6, width = bounds.width - inset * 2
        // Along the bottom edge (the view is flipped, and so is its backing layer).
        let y = bounds.height - 3.5
        track.frame = CGRect(x: inset, y: y, width: max(0, width), height: 2)
        fill.frame = CGRect(x: inset, y: y, width: max(2, width * CGFloat(progress ?? 0)), height: 2)
        CATransaction.commit()
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
