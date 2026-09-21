import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ToolImagePreviewTests {
    @Test func thumbnailIsBoundedAndUnreadableFilesFallBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1600, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url)
        let image = try #require(ToolImagePreview.thumbnail(at: url))
        #expect(image.size == NSSize(width: 1200, height: 800))
        try Data("not an image".utf8).write(to: url)
        #expect(ToolImagePreview.thumbnail(at: url) == nil)
        #expect(ToolImagePreview.thumbnail(at: url.appendingPathExtension("missing")) == nil)
        #expect(ToolImagePreview.thumbnail(at: URL(string: "https://example.com/a.png")!) == nil)
    }

    @Test func renderInlineImageAtConversationWidths() throws {
        let image = NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            NSColor(white: 0.88, alpha: 1).setFill(); rect.fill()
            NSColor.darkGray.setFill()
            NSBezierPath(rect: NSRect(x: 220, y: 40, width: 160, height: 60)).fill()
            NSBezierPath(rect: NSRect(x: 250, y: 100, width: 100, height: 330)).fill()
            NSBezierPath(rect: NSRect(x: 275, y: 430, width: 50, height: 70)).fill()
            NSBezierPath(rect: NSRect(x: 298, y: 500, width: 4, height: 60)).fill()
            return true
        }
        let reference = try #require(TranscriptImage(itemType: "imageView", path: "/tmp/Empire State Building.png"))
        for width in [360.0, 800.0] {
            let view = VStack(alignment: .leading, spacing: 12) {
                Text("Assistant").font(.caption).foregroundStyle(.secondary)
                Text("The model is built. Here’s the preview.")
                ToolImageContent(image: image, reference: reference)
                DisclosureGroup("Image details") { Text("imageView metadata") }
            }.padding(24).frame(width: width).background(Color(white: 0.12)).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame.size = host.fittingSize; host.layoutSubtreeIfNeeded()
            #expect(abs(host.fittingSize.width - width) < 1)
            #expect(host.fittingSize.height < 650)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/diorama-image-preview-\(Int(width)).png"))
        }
    }
}
