import SwiftUI
import Testing
@testable import DioramaApp

@MainActor private final class ToolbarProbe {
    var buttons: [NSButton] = []
}
private struct ToolbarProbeButton: NSViewRepresentable {
    let probe: ToolbarProbe
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Stable control", target: nil, action: nil)
        probe.buttons.append(button)
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) {}
}
@MainActor struct ComposerToolbarLayoutTests {
    @Test func resizingPreservesNativeControlIdentityAndAvoidsOverlap() async throws {
        let probe = ToolbarProbe()
        let host = NSHostingView(rootView: ComposerToolbarLayout {
            ToolbarProbeButton(probe: probe).frame(width: 210, height: 36)
            ToolbarProbeButton(probe: probe).frame(width: 210, height: 36)
        })
        // Native representables need a window-backed coordinate space on macOS 15.
        // Exercise the same hosting lifecycle as the actual composer.
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for width: CGFloat in [640, 300, 640, 300] {
            host.frame = CGRect(x: 0, y: 0, width: width, height: 100)
            window.setContentSize(CGSize(width: width, height: 100))
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            try #require(probe.buttons.count == 2)
            // AppKit's bezel/shadow can extend beyond its SwiftUI alignment area
            // (seven points on each side on macOS 15). Test layout, not shadow bounds.
            let frames = probe.buttons.map { $0.convert($0.alignmentRect(forFrame: $0.bounds), to: host) }
            #expect(!frames[0].intersects(frames[1]))
            #expect(frames.allSatisfy { $0.minX >= -1 && $0.maxX <= width + 1 }, "width=\(width), host=\(host.frame), controls=\(frames)")
        }
    }
}
