import AppKit

/// A small speech bubble over a chef in the break room: one emoji (💬 😂 ☕ 🎮 …) in a white
/// rounded bubble with a tail. It pops in, holds, then fades; the kitchen places it over the
/// chef's head each frame (`DioramaSceneView.placeBubbles`).
final class ChefBubbleView: NSView {
    static let size = NSSize(width: 38, height: 36)
    static let hold: Double = 2.6
    private let label = NSTextField(labelWithString: "")
    /// When it is done (fades out from here).
    private(set) var until: Double = 0

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: frame.origin, size: Self.size))
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        label.font = .systemFont(ofSize: 17)
        label.alignment = .center
        label.drawsBackground = false
        label.frame = NSRect(x: 0, y: 9, width: Self.size.width, height: 24)
        addSubview(label)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 2, y: 8, width: bounds.width - 4, height: bounds.height - 10)
        let path = NSBezierPath(roundedRect: body, xRadius: 11, yRadius: 11)
        // The tail, pointing down at the chef.
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.midX - 6, y: body.minY + 1))
        tail.line(to: NSPoint(x: bounds.midX - 1, y: 1))
        tail.line(to: NSPoint(x: bounds.midX + 5, y: body.minY + 1))
        tail.close()
        path.append(tail)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.set()
        NSColor.white.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.12).setStroke(); path.lineWidth = 0.75; path.stroke()
    }

    var emoji: String { label.stringValue }

    /// Shows `emoji` from `now` for `hold` seconds; a pop unless motion is reduced.
    func show(_ emoji: String, now: Double, reducedMotion: Bool) {
        label.stringValue = emoji
        until = now + Self.hold
        alphaValue = 1
        guard !reducedMotion, let layer else { return }
        // Grows from the tail (bottom centre); a view's layer scales about its corner otherwise.
        let w = bounds.width / 2
        let pop = CAKeyframeAnimation(keyPath: "transform")
        pop.values = [0.2, 1.15, 0.95, 1].map { (k: CGFloat) in
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-w, 0, 0), CATransform3DMakeScale(k, k, 1)),
                                                       CATransform3DMakeTranslation(w, 0, 0)))
        }
        pop.keyTimes = [0, 0.5, 0.8, 1]; pop.duration = 0.35
        layer.add(pop, forKey: "pop")
    }

    /// Fades over the last half second; false once it is gone.
    func update(now: Double) -> Bool {
        let left = until - now
        if left <= 0 { return false }
        alphaValue = CGFloat(min(1, left / 0.5))
        return true
    }
}
