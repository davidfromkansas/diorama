import AppKit
import SwiftUI
import Testing
@testable import DioramaApp

@MainActor struct CursorRegionTests {
    @Test func regionsDoNotInterceptActionsAndRespectDisabledAndHiddenState() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let region = CursorRegionView(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        parent.addSubview(region)
        #expect(region.hitTest(NSPoint(x: 10, y: 10)) == nil)
        #expect(region.interactiveRect.width == 80)
        region.cursorEnabled = false
        #expect(region.interactiveRect.isEmpty)
        region.cursorEnabled = true
        parent.isHidden = true
        #expect(region.interactiveRect.isEmpty)
        parent.isHidden = false
        parent.alphaValue = 0
        #expect(region.interactiveRect.isEmpty)
    }
    @Test func regionsClipToVisibleRowsAndUpdateAfterReuse() {
        let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 300))
        clip.documentView = document
        let region = CursorRegionView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        document.addSubview(region)
        #expect(region.interactiveRect.height <= 30)
        region.setFrameOrigin(NSPoint(x: 0, y: 200))
        #expect(region.interactiveRect.isEmpty)
        region.setFrameOrigin(.zero)
        #expect(!region.interactiveRect.isEmpty)
    }
    @Test func modifierPreservesLayout() {
        let plain = NSHostingView(rootView: Text("Create"))
        let cursor = NSHostingView(rootView: Text("Create").pointingHand())
        #expect(plain.fittingSize == cursor.fittingSize)
    }
    @Test func nativeButtonCursorPreservesEnabledAndDisabledGeometry() {
        let plain = NSHostingView(rootView: Button("Create") {}.buttonStyle(.plain))
        let enabled = NSHostingView(rootView: Button("Create") {}.pointingHand().buttonStyle(.plain))
        let disabled = NSHostingView(rootView: Button("Create") {}.pointingHand().buttonStyle(.plain).disabled(true))
        #expect(plain.fittingSize == enabled.fittingSize)
        #expect(enabled.fittingSize == disabled.fittingSize)
    }
}
