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
    @Test func resizingPreservesNativeControlIdentityAndAvoidsOverlap() throws {
        let probe = ToolbarProbe()
        let host = NSHostingView(rootView: ComposerToolbarLayout {
            ToolbarProbeButton(probe: probe).frame(width: 210, height: 36)
            ToolbarProbeButton(probe: probe).frame(width: 210, height: 36)
        })
        for width: CGFloat in [640, 300, 640, 300] {
            host.frame = CGRect(x: 0, y: 0, width: width, height: 100)
            host.layoutSubtreeIfNeeded()
            try #require(probe.buttons.count == 2)
            let frames = probe.buttons.map { $0.convert($0.bounds, to: host) }
            #expect(!frames[0].intersects(frames[1]))
            #expect(frames.allSatisfy { $0.minX >= -1 && $0.maxX <= width + 1 })
        }
    }
}
