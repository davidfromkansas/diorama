import SwiftUI
import ImageIO

struct AgentStatusIcon: NSViewRepresentable {
    let status: AgentSidebarStatus
    let animate: Bool
    static let images: [AgentSidebarStatus: NSImage] = Dictionary(uniqueKeysWithValues: AgentSidebarStatus.allCases.compactMap { status in
        guard let url = Bundle.dioramaResources?.url(forResource: status.label.lowercased(), withExtension: "png", subdirectory: "AgentStatus"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 90,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return (status, NSImage(cgImage: thumbnail, size: NSSize(width: 30, height: 30)))
    })
    func makeNSView(context: Context) -> Icon { Icon(frame: .init(x: 0,y: 0,width: 30,height: 30)) }
    func updateNSView(_ view: Icon, context: Context) { view.configure(status, image: Self.images[status], animate: animate) }
    static func dismantleNSView(_ view: Icon, coordinator: ()) { view.clear() }
    final class Icon: NSView {
        private var state: String?
        func clear() { layer?.sublayers?.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }; state = nil }
        func configure(_ status: AgentSidebarStatus, image: NSImage?, animate: Bool) {
            let next = "\(status)-\(animate)"; guard state != next else { return }
            clear(); state = next; wantsLayer = true
            guard let layer else { return }
            if status != .working { layer.contents = image; layer.contentsGravity = .resizeAspect; return }
            layer.contents = nil
            let grid = CALayer(); grid.frame = .init(x: 0,y: 0,width: 30,height: 30)
            grid.transform = CATransform3DConcat(CATransform3DMakeRotation(.pi/4,0,0,1), CATransform3DMakeScale(0.78,0.78,1)); layer.addSublayer(grid)
            // Native adaptation of Generative Loaders' MIT-licensed pixel-drift.
            for i in 0..<16 {
                let pixel = CALayer(); pixel.frame = .init(x: 2 + (i%4)*7, y: 2 + (i/4)*7, width: 5,height: 5)
                pixel.backgroundColor = NSColor.labelColor.cgColor; pixel.cornerRadius = 0.5; grid.addSublayer(pixel)
                guard animate else { continue }
                func animation(_ path: String, _ values: [Any]) -> CAKeyframeAnimation {
                    let a = CAKeyframeAnimation(keyPath: path); a.values = values; a.keyTimes = [0,0.42,0.72,1]
                    a.duration = 1.2; a.repeatCount = .infinity; a.beginTime = CACurrentMediaTime() - Double(i)*0.07
                    a.timingFunctions = (0..<3).map { _ in CAMediaTimingFunction(controlPoints: 0.4,0,0.2,1) }; return a
                }
                pixel.add(animation("opacity", [0.16,1,0.48,0.16]), forKey: "opacity")
                pixel.add(animation("transform.scale", [0.45,1,0.68,0.45]), forKey: "scale")
                pixel.add(animation("transform.translation.x", [-1.4,0,1.2,-1.4]), forKey: "x")
                pixel.add(animation("transform.translation.y", [-1.4,0,1.2,-1.4]), forKey: "y")
                pixel.add(animation("cornerRadius", [2.5,0.5,1.75,2.5]), forKey: "rounding")
            }
        }
    }
}

/// Native layer animation: only the hovered/focused realized cell animates.
struct AgentHoverTitle: NSViewRepresentable {
    let text: String
    let active: Bool
    let size: CGFloat
    let bold: Bool
    var secondary = false
    func makeNSView(context: Context) -> Marquee { Marquee() }
    func updateNSView(_ view: Marquee, context: Context) {
        view.configure(text: text, active: active, size: size, bold: bold, secondary: secondary)
    }
    static func dismantleNSView(_ view: Marquee, coordinator: ()) { view.label.layer?.removeAllAnimations() }
    final class Marquee: NSView {
        let label = NSTextField(labelWithString: "")
        private var active = false
        private var signature = ""
        override init(frame: NSRect) {
            super.init(frame: frame); wantsLayer = true; layer?.masksToBounds = true
            label.wantsLayer = true; label.maximumNumberOfLines = 1; label.lineBreakMode = .byClipping
            addSubview(label)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var intrinsicContentSize: NSSize { .init(width: NSView.noIntrinsicMetric, height: (label.font?.pointSize ?? 13) + 4) }
        func configure(text: String, active: Bool, size: CGFloat, bold: Bool, secondary: Bool = false) {
            let next = "\(text)|\(active)|\(size)|\(bold)|\(secondary)"
            guard signature != next else { return }; signature = next
            self.active = active; label.stringValue = text
            label.textColor = secondary ? .secondaryLabelColor : .labelColor
            label.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            toolTip = text; setAccessibilityLabel(text); invalidateIntrinsicContentSize(); needsLayout = true
        }
        override func layout() {
            super.layout()
            label.layer?.removeAnimation(forKey: "marquee")
            let width = ceil(label.intrinsicContentSize.width)
            // NSTextField has a two-point text inset; cancel it so its glyphs
            // share the same leading edge as adjacent SwiftUI Text labels.
            let height = label.intrinsicContentSize.height
            label.frame = NSRect(x: -2, y: (bounds.height - height) / 2, width: max(bounds.width + 4, width), height: height)
            guard active, width > bounds.width, bounds.width > 0 else { return }
            let overflow = width - bounds.width, travel = max(2, Double(overflow / 30)), duration = 2 * travel + 2
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, 0, -overflow, -overflow, 0]
            animation.keyTimes = [0, NSNumber(value: 1 / duration), NSNumber(value: (1 + travel) / duration), NSNumber(value: (2 + travel) / duration), 1]
            animation.duration = duration; animation.repeatCount = .infinity; animation.calculationMode = .linear
            label.layer?.add(animation, forKey: "marquee")
        }
    }
}
