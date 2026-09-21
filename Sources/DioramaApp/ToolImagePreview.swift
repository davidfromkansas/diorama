import SwiftUI
import ImageIO
import DioramaCore

struct ToolImagePreview: View {
    let reference: TranscriptImage
    @State private var image: NSImage?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                ToolImageContent(image: image, reference: reference)
            } else if loaded {
                Label("Image unavailable · \(reference.url.lastPathComponent)", systemImage: "photo.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView("Loading image…").controlSize(.small)
            }
        }
        .task(id: reference.url) {
            image = nil; loaded = false
            image = Self.thumbnail(at: reference.url)
            loaded = true
        }
    }

    /// Decode a bounded thumbnail instead of retaining full-resolution tool screenshots.
    static func thumbnail(at url: URL) -> NSImage? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

struct ToolImageContent: View {
    let image: NSImage
    let reference: TranscriptImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { NSWorkspace.shared.open(reference.url) } label: {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 560, maxHeight: 420, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open image: \(reference.url.lastPathComponent)")
            .help("Open full-size image")
            HStack {
                Text(reference.url.lastPathComponent).lineLimit(1)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([reference.url]) }
                    .buttonStyle(.link)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
