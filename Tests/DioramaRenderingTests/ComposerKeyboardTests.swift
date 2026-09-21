import AppKit
import SwiftUI
import Testing
@testable import DioramaApp

@MainActor struct ComposerKeyboardTests {
    private func key(_ flags: NSEvent.ModifierFlags = [], code: UInt16 = 36) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code)!
    }
    @Test func returnSendsButShiftReturnAndCompositionDoNot() {
        let editor = ComposerNSTextView()
        editor.isEditable = true; editor.string = "Hello"
        var sends = 0
        editor.sendMessage = { sends += 1 }
        editor.hasSendableContent = { !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        editor.keyDown(with: key())
        #expect(sends == 1)
        editor.keyDown(with: key(.command))
        editor.keyDown(with: key([], code: 76))
        #expect(sends == 3)
        editor.keyDown(with: key(.shift))
        #expect(sends == 3)
        editor.string = ""
        editor.keyDown(with: key())
        #expect(sends == 3)
        editor.setMarkedText("字", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.keyDown(with: key())
        #expect(sends == 3)
    }
    @Test func bubbleRendersWithTrailingTail() throws {
        let view = Text("Hello there").font(.body).foregroundStyle(.white).padding(16)
            .background(Color.blue, in: UserMessageBubble()).padding(20)
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize; host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-tail.png"))
    }
}
