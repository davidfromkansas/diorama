import Foundation
import UniformTypeIdentifiers
import ImageIO

/// Local references only; attaching a file never changes the provider's permissions.
public struct ConversationAttachment: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case image, file }
    public let url: URL
    public let kind: Kind
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL) throws {
        guard url.isFileURL else { throw AppServerFailure("Choose a local file, rather than a web link.") }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, FileManager.default.isReadableFile(atPath: resolved.path) else {
            throw AppServerFailure("Cannot attach \(url.lastPathComponent). Choose a readable file, rather than a folder.")
        }
        let ext = resolved.pathExtension.lowercased()
        let image = ["png", "jpg", "jpeg", "webp", "gif"].contains(ext)
        if !image, UTType(filenameExtension: ext)?.conforms(to: .image) == true {
            throw AppServerFailure("Convert \(url.lastPathComponent) to PNG or JPEG before attaching it.")
        }
        if image, (values.fileSize ?? 0) > 20 * 1024 * 1024 { throw AppServerFailure("Images must be 20 MiB or smaller.") }
        if image {
            guard let source = CGImageSourceCreateWithURL(resolved as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
                throw AppServerFailure("Cannot read image \(url.lastPathComponent).")
            }
        }
        self.url = resolved
        kind = image ? .image : .file
    }

    public static func input(prompt: String, attachments: [Self]) throws -> [WireValue] {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { throw AppServerFailure("Enter a message or attach a file.") }
        guard attachments.count <= 20 else { throw AppServerFailure("Attach up to 20 files per message.") }
        guard prompt.utf8.count <= 256 * 1024 else { throw AppServerFailure("Prompt exceeds 256 KiB") }
        // Revalidate immediately before submission, including retries after a writer conflict.
        let checked = try attachments.map { try Self(url: $0.url) }
        var text = prompt
        let files = checked.filter { $0.kind == .file }
        if !files.isEmpty {
            let paths = try files.map { String(decoding: try JSONEncoder().encode($0.url.path), as: UTF8.self) }.joined(separator: "\n")
            text += "\n\nAttached local file references (JSON-quoted paths; read using your tools as needed):\n" + paths
        }
        var input: [WireValue] = text.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(text)])]
        input += checked.filter { $0.kind == .image }.map { .object(["type": .string("localImage"), "path": .string($0.url.path)]) }
        return input
    }
}
