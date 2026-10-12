import SwiftUI

/// Native skeleton treatment inspired by generativeloaders.com; no web runtime.
struct ConversationHistoryLoader: View {
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                if reducedMotion || scenePhase != .active {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading conversation history…").font(.callout.weight(.medium))
                    Text("Retrieving earlier messages and agent activity.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !compact {
                VStack(alignment: .leading, spacing: 24) {
                    HStack { Spacer(minLength: 60); skeleton(width: 0.65, lines: 2) }
                    skeleton(width: 0.9, lines: 3)
                    skeleton(width: 0.72, lines: 2)
                }.accessibilityHidden(true)
            }
        }
        .padding(compact ? 12 : 24)
        .frame(maxWidth: compact ? .infinity : 560, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversation history. Retrieving earlier messages and agent activity.")
    }

    private func skeleton(width: CGFloat, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<lines, id: \.self) { line in
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: geometry.size.width * (line == lines - 1 ? width * 0.7 : width))
                }.frame(height: 10)
            }
        }
    }
}

/// iMessage style, while a conversation loads (inspired by generativeloaders.com): bubble-shaped
/// ghosts where the messages will be, fading in one after another with a soft shimmer, under a
/// card with a rippling dot grid, a line saying what it's reading and a moving bar. Core Animation
/// only, so nothing re-lays-out while it runs; Reduce Motion holds it still.
struct AvatarConversationLoader: View {
    var agent: String?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    private var animated: Bool { !reducedMotion && scenePhase == .active }
    var body: some View {
        ZStack {
            GhostBubbles(animated: animated).padding(.horizontal, 14).padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                LoaderLayers(kind: .ripple, animated: animated).frame(width: 78, height: 30).accessibilityHidden(true)
                Text("Loading the conversation").font(.system(size: 14, weight: .semibold))
                Text("Reading earlier messages and \(agent.map { $0 + "’s" } ?? "the agent’s") activity…")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                LoaderLayers(kind: .bar, animated: animated).frame(height: 4).accessibilityHidden(true)
            }
            .padding(.horizontal, 18).padding(.vertical, 16).frame(width: 250)
            .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversation history. Retrieving earlier messages and agent activity.")
    }
}

/// The ghost bubbles: yours on the right (light blue), the agent's on the left (grey), in the
/// sizes real messages take.
struct GhostBubbles: NSViewRepresentable {
    var animated: Bool
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ view: View, context: Context) { view.animated = animated }
    static func dismantleNSView(_ view: View, coordinator: ()) { view.animated = false }

    final class View: NSView {
        var animated = false { didSet { if animated != oldValue { needsLayout = true } } }
        /// Width, height, mine.
        private let shapes: [(CGFloat, CGFloat, Bool)] = [(230, 38, true), (280, 56, false), (170, 38, false), (200, 38, true), (300, 74, false)]
        private lazy var bubbles: [CALayer] = shapes.map { _ in CALayer() }
        override var isFlipped: Bool { true }
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; bubbles.forEach { layer?.addSublayer($0) } }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
            var y: CGFloat = 0
            for (index, (shape, bubble)) in zip(shapes, bubbles).enumerated() {
                let width = min(shape.0, bounds.width * 0.75)
                bubble.frame = CGRect(x: shape.2 ? bounds.width - width : 0, y: y, width: width, height: shape.1)
                bubble.cornerRadius = 18
                bubble.backgroundColor = shape.2 ? NSColor(red: 0.81, green: 0.89, blue: 1, alpha: 1).cgColor : NSColor(white: 0.9, alpha: 1).cgColor
                y += shape.1 + 8
                bubble.removeAllAnimations()
                bubble.opacity = 1
                guard animated, window != nil else { continue }
                // Each fades in after the one before, holds, then they all start over.
                let arrive = CAKeyframeAnimation(keyPath: "opacity")
                arrive.values = [0, 0, 1, 1, 0]
                arrive.keyTimes = [0, NSNumber(value: Double(index) * 0.07), NSNumber(value: Double(index) * 0.07 + 0.1), 0.85, 1]
                arrive.duration = 4.8; arrive.repeatCount = .infinity
                bubble.add(arrive, forKey: "arrive")
                let shimmer = CABasicAnimation(keyPath: "backgroundColor")
                shimmer.fromValue = bubble.backgroundColor
                shimmer.toValue = shape.2 ? NSColor(red: 0.9, green: 0.95, blue: 1, alpha: 1).cgColor : NSColor(white: 0.95, alpha: 1).cgColor
                shimmer.duration = 0.8; shimmer.autoreverses = true; shimmer.repeatCount = .infinity
                shimmer.beginTime = CACurrentMediaTime() + Double(index) * 0.12
                bubble.add(shimmer, forKey: "shimmer")
            }
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); needsLayout = true }
    }
}

/// The card's moving parts: a 7×3 dot grid rippling out from the middle, or a bar sweeping.
struct LoaderLayers: NSViewRepresentable {
    enum Kind { case ripple, bar }
    let kind: Kind
    var animated: Bool
    func makeNSView(context: Context) -> View { View(kind: kind) }
    func updateNSView(_ view: View, context: Context) { view.animated = animated }
    static func dismantleNSView(_ view: View, coordinator: ()) { view.animated = false }

    final class View: NSView {
        let kind: Kind
        var animated = false { didSet { if animated != oldValue { needsLayout = true } } }
        private var parts: [CALayer] = []
        private let track = CALayer()
        override var isFlipped: Bool { true }
        init(kind: Kind) {
            self.kind = kind
            super.init(frame: .zero)
            wantsLayer = true
            if kind == .ripple { parts = (0..<21).map { _ in CALayer() } } else { parts = [CALayer()]; layer?.addSublayer(track) }
            parts.forEach { layer?.addSublayer($0) }
            layer?.masksToBounds = kind == .bar
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
            let blue = NSColor.systemBlue.cgColor
            let running = animated && window != nil
            switch kind {
            case .ripple:
                let gap = bounds.width / 7
                for (index, dot) in parts.enumerated() {
                    let row = index / 7, col = index % 7
                    dot.frame = CGRect(x: CGFloat(col) * gap + (gap - 6) / 2, y: CGFloat(row) * 10 + 2, width: 6, height: 6)
                    dot.cornerRadius = 3; dot.backgroundColor = blue
                    dot.removeAllAnimations(); dot.opacity = 0.7
                    guard running else { continue }
                    let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
                    pulse.values = [0.55, 1, 0.55]
                    let fade = CAKeyframeAnimation(keyPath: "opacity")
                    fade.values = [0.25, 1, 0.25]
                    let group = CAAnimationGroup()
                    group.animations = [pulse, fade]; group.duration = 1.4; group.repeatCount = .infinity
                    group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    group.beginTime = CACurrentMediaTime() + Double(row) * 0.12 + Double(abs(col - 3)) * 0.14
                    dot.add(group, forKey: "ripple")
                }
            case .bar:
                track.frame = bounds; track.cornerRadius = bounds.height / 2
                track.backgroundColor = NSColor(white: 0.92, alpha: 1).cgColor
                let fill = parts[0]
                fill.frame = CGRect(x: 0, y: 0, width: bounds.width * 0.35, height: bounds.height)
                fill.cornerRadius = bounds.height / 2; fill.backgroundColor = blue
                fill.removeAllAnimations()
                guard running else { fill.frame.origin.x = bounds.width * 0.3; return }
                let move = CABasicAnimation(keyPath: "transform.translation.x")
                move.fromValue = -bounds.width * 0.35; move.toValue = bounds.width
                move.duration = 1.4; move.repeatCount = .infinity
                move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                fill.add(move, forKey: "sweep")
            }
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); needsLayout = true }
    }
}
