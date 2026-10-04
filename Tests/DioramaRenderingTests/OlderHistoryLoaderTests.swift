import SwiftUI
import Testing
@testable import DioramaApp

@MainActor struct OlderHistoryLoaderTests {
    @Test func animationStopsWhenDisabledHiddenOrDetached() {
        let view = HistoryPulseDots.DotView()
        view.frame = NSRect(x: 0, y: 0, width: 24, height: 12)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil; window.orderOut(nil) }
        let dots = view.layer!.sublayers!
        #expect(dots.count == 4)
        view.animated = true
        #expect(dots.allSatisfy { $0.animation(forKey: "pulse") != nil })
        view.animated = false
        #expect(dots.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        view.animated = true
        view.isHidden = true
        #expect(dots.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        view.isHidden = false
        #expect(dots.allSatisfy { $0.animation(forKey: "pulse") != nil })
        window.contentView = nil
        #expect(dots.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    }
    @Test func staticPreview() async throws {
        let host = NSHostingView(rootView: OlderHistoryLoader()
            .frame(width: 360, height: 72).background(Color.white)
            .environment(\.colorScheme, .light).environment(\.scenePhase, .inactive))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 72)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-older-history-loader.png"))
    }
}
