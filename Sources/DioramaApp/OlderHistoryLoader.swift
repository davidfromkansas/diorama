import SwiftUI
import AppKit
import QuartzCore

/// Native adaptation of Generative Loaders' Dot pulse (MIT; license below).
/// Core Animation animates only these four layers, never the transcript layout.
struct OlderHistoryLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HStack(spacing: 8) {
            HistoryPulseDots(animated: !reducedMotion && scenePhase == .active)
                .frame(width: 24, height: 12).accessibilityHidden(true)
            Text("Loading older messages…").font(.caption).foregroundStyle(.secondary)
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading older messages")
    }
}

struct HistoryPulseDots: NSViewRepresentable {
    var animated: Bool
    func makeNSView(context: Context) -> DotView { DotView() }
    func updateNSView(_ view: DotView, context: Context) { view.animated = animated }
    static func dismantleNSView(_ view: DotView, coordinator: ()) { view.animated = false }

    final class DotView: NSView {
        var animated = false { didSet { updateAnimation() } }
        private let dots = (0..<4).map { _ in CALayer() }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for (index, dot) in dots.enumerated() {
                dot.frame = CGRect(x: CGFloat(index) * 6, y: 4, width: 4, height: 4)
                dot.cornerRadius = 2
                layer?.addSublayer(dot)
            }
            updateAnimation()
        }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }
        override func viewDidHide() { super.viewDidHide(); updateAnimation() }
        override func viewDidUnhide() { super.viewDidUnhide(); updateAnimation() }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAnimation() }
        private func updateAnimation() {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let running = animated && window != nil && !isHiddenOrHasHiddenAncestor
            for (index, dot) in dots.enumerated() {
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    dot.backgroundColor = NSColor.secondaryLabelColor.cgColor
                }
                dot.opacity = 0.6
                guard running else { dot.removeAllAnimations(); continue }
                guard dot.animation(forKey: "pulse") == nil else { continue }
                let curve = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
                func keyframes(_ key: String, _ values: [Double]) -> CAKeyframeAnimation {
                    let animation = CAKeyframeAnimation(keyPath: key)
                    animation.values = values
                    animation.keyTimes = [0, 0.38, 0.68, 1]
                    animation.timingFunctions = [curve, curve, curve]
                    animation.duration = 1.2
                    return animation
                }
                let group = CAAnimationGroup()
                group.animations = [keyframes("opacity", [0.24, 1, 0.52, 0.24]),
                                    keyframes("transform.scale", [0.62, 1, 0.78, 0.62]),
                                    keyframes("transform.translation.y", [0, 1.28, -0.4, 0])]
                group.duration = 1.2
                group.timeOffset = Double(3 - index) * 0.15 * 1.2
                group.repeatCount = .infinity
                dot.add(group, forKey: "pulse")
            }
        }
    }
}

/*
Dot pulse motion adapted from https://generativeloaders.com
https://github.com/kasturibuilds/generative-loaders
MIT License

Copyright (c) 2026 Kasturi Khanke and Generative Loaders contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/
