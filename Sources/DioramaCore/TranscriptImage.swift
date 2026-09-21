import Foundation

/// A structured tool image reference, never inferred from arbitrary message text.
public struct TranscriptImage: Equatable, Sendable, Codable {
    public let url: URL

    public init?(itemType: String?, path: String?) {
        guard itemType == "imageView", let path,
              path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\0") else { return nil }
        url = URL(fileURLWithPath: path).standardizedFileURL
    }
}
