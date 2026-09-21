import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ClipboardImageTests {
    @Test func pngAndTIFFPersistAfterClipboardChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for (type, format) in [(NSPasteboard.PasteboardType.png, NSBitmapImageRep.FileType.png), (.tiff, .tiff)] {
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            let data = try #require(bitmap.representation(using: format, properties: [:]))
            pasteboard.setData(data, forType: type)
            let saved = try ClipboardImageStore.attachment(from: pasteboard, directory: folder)
            let attachment = try #require(saved)
            pasteboard.clearContents()
            #expect(attachment.kind == .image)
            #expect(attachment.url.pathExtension == "png")
            let input = try ConversationAttachment.input(prompt: "", attachments: [attachment])
            #expect(input.first?["type"].string == "localImage")
        }
    }
    @Test func textAndFinderCopiesAreNotImageAttachments() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("ordinary text", forType: .string)
        #expect(try ClipboardImageStore.attachment(from: pasteboard) == nil)
        pasteboard.setData(Data("invalid image".utf8), forType: .png)
        #expect(throws: (any Error).self) { try ClipboardImageStore.attachment(from: pasteboard) }
        pasteboard.setString("file:///tmp/example.txt", forType: .fileURL)
        #expect(try ClipboardImageStore.attachment(from: pasteboard) == nil)
    }
    @Test func nativePasteActionAcceptsImageOnlyClipboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data(), forType: .png)
        let native = ComposerNSTextView()
        native.isEditable = true
        native.clipboard = { pasteboard }
        var received = false
        native.pasteImage = { board in received = board === pasteboard; return true }
        let item = NSMenuItem(title: "Paste", action: #selector(NSTextView.paste(_:)), keyEquivalent: "v")
        #expect(native.validateUserInterfaceItem(item))
        native.paste(nil)
        #expect(received)
        native.isEditable = false
        #expect(!native.validateUserInterfaceItem(item))
    }
    @Test func disabledComposerDoesNotPasteImages() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data(), forType: .png)
        let editor = ComposerTextEditor(text: .constant("draft"), attachments: .constant([]), error: .constant(nil), disabled: true)
        #expect(editor.makeCoordinator().pasteImage(pasteboard))
        let native = ComposerNSTextView()
        native.isEditable = false
        var called = false
        native.pasteImage = { _ in called = true; return true }
        native.paste(nil)
        #expect(!called)
    }
}
