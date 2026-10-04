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

extension ClipboardImageTests {
    @Test func finderImagesPasteAsAttachmentsWithoutReplacingText() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let urls = [folder.appendingPathComponent("one.png"), folder.appendingPathComponent("two.png")]
        for url in urls { try data.write(to: url) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects(urls as [NSURL])
        var attachments: [ConversationAttachment] = []
        var error: String?
        var text = "Keep my draft"
        let editor = ComposerTextEditor(text: Binding(get: { text }, set: { text = $0 }),
            attachments: Binding(get: { attachments }, set: { attachments = $0 }),
            error: Binding(get: { error }, set: { error = $0 }), disabled: false)
        let coordinator = editor.makeCoordinator()
        #expect(coordinator.pasteImage(board))
        #expect(attachments.count == 2 && attachments.allSatisfy { $0.kind == .image })
        #expect(text == "Keep my draft" && error == nil)
        #expect(coordinator.pasteImage(board))
        #expect(attachments.count == 2, "Finder copies should not duplicate the same files")
        let input = try ConversationAttachment.input(prompt: text, attachments: attachments)
        let claude = try ClaudeExecutionTransport.input(input)
        #expect(claude.filter { $0["type"].string == "image" }.count == 2)
        board.clearContents(); board.setString("ordinary text", forType: .string)
        #expect(!coordinator.pasteImage(board), "Plain text must remain normal text paste")
        board.clearContents(); board.writeObjects([folder as NSURL])
        #expect(coordinator.pasteImage(board))
        #expect(error != nil && attachments.count == 2, "Invalid files leave prior attachments intact")
    }
    @Test func composerShowsImagePreview() async throws {
        guard let path = ProcessInfo.processInfo.environment["DIORAMA_COMPOSER_IMAGE"] else { return }
        let attachment = try ConversationAttachment(url: URL(fileURLWithPath: path))
        let thumbnail = try #require(await ComposerThumbnailLoader.shared.thumbnail(attachment.url))
        #expect(max(thumbnail.width, thumbnail.height) <= 240)
        let view = ConversationComposer(controller: ExecutionController(), model: .constant(""), effort: .constant(""),
            prompt: .constant("Here’s the screenshot"), attachments: .constant([attachment]), approvalReview: .constant(.inherit),
            effectiveModel: "", sending: false, active: false, send: {})
            .padding(16).frame(width: 420).background(Color.white)
            .environment(\.avatarMessages, true).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 210)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300)); host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-image-composer.png"))
    }
}
