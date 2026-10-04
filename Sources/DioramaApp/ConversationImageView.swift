import SwiftUI
import ImageIO
import CryptoKit
import DioramaCore
import QuickLook
import UniformTypeIdentifiers

private struct ConversationImageBaseURLKey: EnvironmentKey { static let defaultValue: URL? = nil }
extension EnvironmentValues {
    var conversationImageBaseURL: URL? {
        get { self[ConversationImageBaseURLKey.self] }
        set { self[ConversationImageBaseURLKey.self] = newValue }
    }
}

enum ConversationImageSource {
    nonisolated static func isImage(_ output: ClaudeOutput) -> Bool {
        output.kind == "image" || output.mediaType?.hasPrefix("image/") == true ||
            ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"].contains(ClaudeOutputPreview.externalURL(output)?.pathExtension.lowercased() ?? "")
    }

    nonisolated static func output(_ url: URL?) -> ClaudeOutput {
        let resolved = url.flatMap { $0.scheme == nil && $0.path.hasPrefix("/") ? URL(fileURLWithPath: $0.path) : $0 }
        if let raw = resolved?.absoluteString, raw.hasPrefix("data:image/"), let comma = raw.firstIndex(of: ","), raw[..<comma].hasSuffix(";base64") {
            return ClaudeOutput(id: raw, name: "Image", kind: "image", encoded: String(raw[raw.index(after: comma)...]))
        }
        return ClaudeOutput(id: resolved?.absoluteString ?? "missing-image", name: resolved?.lastPathComponent ?? "Image", kind: "image", location: resolved?.absoluteString)
    }
}

actor ConversationImageLoader {
    private static let cache = ConversationImageLoader()
    private let bytes = NSCache<NSString, NSData>()
    private let thumbnails = NSCache<NSString, CGImage>()
    init() { bytes.totalCostLimit = 64 * 1024 * 1024; bytes.countLimit = 64; thumbnails.totalCostLimit = 64 * 1024 * 1024; thumbnails.countLimit = 64 }
    static func load(_ output: ClaudeOutput) async throws -> Data { try await cache.read(output) }
    private func read(_ output: ClaudeOutput) async throws -> Data {
        let url = ClaudeOutputPreview.externalURL(output)
        let stamp = url?.isFileURL == true ? (try? url?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.description ?? "" : ""
        let identity = (output.encoded ?? output.location ?? output.id) + stamp
        let key = SHA256.hash(data: Data(identity.utf8)).description as NSString
        if let cached = bytes.object(forKey: key) { return cached as Data }
        let data: Data
        if output.encoded == nil, let url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 20
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let (stream, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.expectedContentLength <= ClaudeOutputPreview.maximumBytes else { throw AppServerFailure("The image could not be downloaded or exceeds 16 MiB.") }
            var buffer = Data()
            for try await byte in stream {
                try Task.checkCancellation()
                guard buffer.count < ClaudeOutputPreview.maximumBytes else { throw AppServerFailure("The image exceeds 16 MiB.") }
                buffer.append(byte)
            }
            data = buffer
        } else { data = try await ClaudeOutputPreview.load(output).data }
        bytes.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }
    // Preview an immutable copy so Quick Look never edits the original attachment.
    static func previewFile(data: Data, name: String) async throws -> URL {
        try await cache.writePreview(data: data, name: name)
    }
    private func writePreview(data: Data, name: String) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let ext = UTType(identifier as String)?.preferredFilenameExtension else {
            throw AppServerFailure("The image data could not be decoded.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DioramaImagePreview-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let file = directory.appendingPathComponent(stem.isEmpty ? "Image" : stem).appendingPathExtension(ext)
        do { try data.write(to: file, options: .atomic); return file }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    nonisolated static func removePreview(_ url: URL?) {
        guard let url, url.deletingLastPathComponent().lastPathComponent.hasPrefix("DioramaImagePreview-") else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    nonisolated static func thumbnail(_ data: Data, pixels: Int = 1200) async throws -> NSImage {
        let cg = try await cache.thumbnailImage(data, pixels: pixels)
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    private func thumbnailImage(_ data: Data, pixels: Int) async throws -> CGImage {
        let key = (SHA256.hash(data: data).description + ":" + String(pixels)) as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        let cg = try await Task.detached {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels
                  ] as CFDictionary) else { throw AppServerFailure("The image data could not be decoded.") }
            return image
        }.value
        thumbnails.setObject(cg, forKey: key, cost: cg.bytesPerRow * cg.height)
        return cg
    }
}

struct ConversationImageView: View {
    let output: ClaudeOutput
    @State private var image: NSImage?
    @State private var data: Data?
    @State private var error: String?
    @State private var previewURL: URL?
    @State private var previewRequest = 0
    @State private var previewError: String?
    @State private var retry = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image {
                    Button { previewRequest += 1 } label: {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }.pointingHand().buttonStyle(.plain).accessibilityLabel("Enlarge image: " + output.name).help("Click to enlarge")
                } else if let error {
                    VStack(spacing: 8) {
                        Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        Button("Retry") { retry += 1 }.pointingHand()
                    }
                } else { ProgressView("Loading image…").controlSize(.small) }
            }
            // Reserve space while loading so arriving pixels do not shift history.
            .frame(maxWidth: .infinity).frame(height: 220)
            .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            Text(output.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .task(id: output) { await load() }
        .task(id: retry) { if retry > 0 { await load() } }
        .quickLookPreview($previewURL)
        .task(id: previewRequest) {
            guard previewRequest > 0, let data else { return }
            do {
                let file = try await ConversationImageLoader.previewFile(data: data, name: output.name)
                guard !Task.isCancelled else { ConversationImageLoader.removePreview(file); return }
                previewURL = file
            } catch { if !Task.isCancelled { previewError = error.localizedDescription } }
        }
        .onChange(of: previewURL) { old, new in
            if old != new { ConversationImageLoader.removePreview(old) }
        }
        .onDisappear {
            ConversationImageLoader.removePreview(previewURL)
            previewURL = nil
        }
        .alert("Unable to open image", isPresented: Binding(
            get: { previewError != nil }, set: { if !$0 { previewError = nil } }
        )) { Button("OK", role: .cancel) {}.pointingHand() } message: { Text(previewError ?? "") }
    }
    private func load() async {
        image = nil; error = nil; data = nil
        do {
            let bytes = try await ConversationImageLoader.load(output)
            let preview = try await ConversationImageLoader.thumbnail(bytes)
            try Task.checkCancellation()
            data = bytes; image = preview
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

