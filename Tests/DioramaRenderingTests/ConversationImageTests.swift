import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationImageTests {
    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<80 { for x in 0..<160 { bitmap.setColor(x < 80 ? NSColor(deviceRed: 0, green: 0.4, blue: 1, alpha: 1) : NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 1), atX: x, y: y) } }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
    @Test func fileAndEncodedImagesLoadWithoutPreviewAction() async throws {
        let data = try png()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + " image.png")
        defer { try? FileManager.default.removeItem(at: file) }
        try data.write(to: file)
        #expect(ConversationImageSource.isImage(.init(id: "file", name: "Screenshot", kind: "file", location: file.path)))
        #expect(ConversationImageSource.isImage(.init(id: "resource", name: "Screenshot", kind: "resource", mediaType: "image/png")))
        let local = try await ConversationImageLoader.load(ConversationImageSource.output(file))
        #expect(local == data)
        let encoded = ClaudeOutput(id: "inline", name: "Screenshot", kind: "image", encoded: data.base64EncodedString())
        #expect(try await ConversationImageLoader.load(encoded) == data)
        let preview = try await ConversationImageLoader.thumbnail(local, pixels: 100)
        #expect(preview.size.width <= 100)
        #expect(preview.size.height > 0)
        let dataURL = URL(string: "data:image/png;base64," + data.base64EncodedString())
        #expect(try await ConversationImageLoader.load(ConversationImageSource.output(dataURL)) == data)
    }
    @Test func quickLookReceivesOriginalImageAndCleansUp() async throws {
        let data = try png()
        let file = try await ConversationImageLoader.previewFile(data: data, name: "../../Screenshot.jpg")
        defer { ConversationImageLoader.removePreview(file) }
        #expect(file.pathExtension == "png")
        #expect(file.lastPathComponent == "Screenshot.png")
        #expect(try Data(contentsOf: file) == data)
        ConversationImageLoader.removePreview(file)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        await #expect(throws: (any Error).self) {
            try await ConversationImageLoader.previewFile(data: Data("invalid".utf8), name: "bad.png")
        }
    }
    @Test func missingAndInvalidImagesReportFailure() async {
        await #expect(throws: (any Error).self) { try await ConversationImageLoader.load(ConversationImageSource.output(URL(fileURLWithPath: "/tmp/absent-image-" + UUID().uuidString))) }
        await #expect(throws: (any Error).self) { try await ConversationImageLoader.thumbnail(Data("not an image".utf8)) }
        await #expect(throws: (any Error).self) { try await ConversationImageLoader.load(ConversationImageSource.output(URL(string: "javascript:alert(1)"))) }
    }
    @Test func imagesAreNotHiddenInWorkActivity() {
        var entry = Entry(id: "image-result", kind: "Tool", text: "", timestamp: nil)
        entry.claude = ClaudePresentation(title: "Screenshot", status: "Completed", callID: "call", outputs: [.init(id: "image", name: "Image", kind: "image", encoded: "abc")])
        #expect(!ConversationHistory.canGroup(entry))
    }
    @Test func markdownAndToolImagesRenderInline() async throws {
        let data = try png()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        try data.write(to: file)
        let host = NSHostingView(rootView: ScrollView {
            VStack {
                MarkdownText(text: "Here is the screenshot:\n\n![Screenshot](\(file.path))")
                ConversationOutputCards(outputs: [.init(id: "tool", name: "Tool screenshot", kind: "image", encoded: data.base64EncodedString())])
            }.padding(16)
        }.environment(\.colorScheme, .light).background(.white))
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<8 { try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded() }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-inline-images.png"))
        #expect(host.frame.width == 440)
    }
}
