import SwiftUI
import ImageIO
import QuickLook
import DioramaCore

/// Small decoded previews, independent of the full images sent to the provider.
actor ComposerThumbnailLoader {
    static let shared = ComposerThumbnailLoader()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.countLimit = 40; cache.totalCostLimit = 12 * 1024 * 1024 }
    func thumbnail(_ url: URL) -> CGImage? {
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.description ?? ""
        let key = (url.path + stamp) as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240
              ] as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}

struct ComposerAttachmentTray: View {
    @Binding var attachments: [ConversationAttachment]
    let disabled: Bool
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ComposerAttachmentTile(attachment: attachment, disabled: disabled) {
                        attachments.removeAll { $0.id == attachment.id }
                    }
                }
            }.padding(2)
        }.scrollIndicators(.hidden).frame(height: 100)
    }
}

private struct ComposerAttachmentTile: View {
    let attachment: ConversationAttachment
    let disabled: Bool
    let remove: () -> Void
    @State private var image: NSImage?
    @State private var preview: URL?
    var body: some View {
        Button { preview = attachment.url } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: attachment.kind == .image ? "photo" : "doc").font(.title3)
                        Text(attachment.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                    }.padding(8).foregroundStyle(.secondary)
                }
            }.frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).pointingHand().accessibilityLabel("Preview " + attachment.name)
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Color.black.opacity(0.65), in: Circle())
            }.buttonStyle(.plain).pointingHand().disabled(disabled)
                .accessibilityLabel("Remove " + attachment.name).padding(4)
        }
        .help(attachment.name)
        .quickLookPreview($preview)
        .task(id: attachment.id) {
            guard attachment.kind == .image else { return }
            let thumbnail = await ComposerThumbnailLoader.shared.thumbnail(attachment.url)
            guard !Task.isCancelled, let thumbnail else { return }
            image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        }
    }
}
