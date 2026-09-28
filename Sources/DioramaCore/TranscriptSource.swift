import Foundation
import CryptoKit

/// Reference to one immutable record, not the changing size/mtime of its containing log.
public struct TranscriptSource: Codable, Equatable, Sendable {
    public var path: String
    public var offset: UInt64
    public var length: Int
    public var digest: String
    public init?(path: String, offset: UInt64, record: Data) {
        guard path.hasPrefix("/"), record.count <= 16 * 1024 * 1024 else { return nil }
        self.path = path; self.offset = offset; self.length = record.count
        self.digest = Self.recordDigest(record)
    }
    // Source references are produced for every parsed row. Avoid 32 locale-aware
    // formatter calls per digest on the selected-conversation refresh path.
    private static func recordDigest(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for byte in SHA256.hash(data: data) {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 15)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    @concurrent public func load(characterLimit: Int) async throws -> String {
        guard length >= 0, length <= 16 * 1024 * 1024 else { throw AppServerFailure("Source record exceeds the inspection limit.") }
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? file.close() }
        try file.seek(toOffset: offset)
        let data = try file.read(upToCount: length) ?? Data()
        let current = Self.recordDigest(data)
        guard current == digest else { throw AppServerFailure("Source record changed or was replaced. Refresh the conversation before inspecting it.") }
        let value = try JSONDecoder().decode(WireValue.self, from: data)
        let text = Self.inspectable(value).pretty
        let limit = max(1024, min(characterLimit, 16 * 1024 * 1024))
        return text.count <= limit ? text : String(text.prefix(limit)) + "\n[More source content available]"
    }
    public static func inspectable(_ value: WireValue) -> WireValue {
        switch value {
        case .object(let fields):
            let type = fields["type"]?.string?.lowercased() ?? ""
            if ["reasoning", "thinking", "redacted_thinking", "prompt_snapshot", "last-prompt"].contains(type) { return .string("[Internal content omitted]") }
            var result: [String: WireValue] = [:]
            for (key, child) in fields where !["encrypted_content", "encryptedContent", "raw_content", "rawContent", "signature"].contains(key) {
                if key == "blob" || (key == "data" && ["image", "audio", "base64"].contains(type)) || (key == "result" && type == "imagegeneration") {
                    result[key] = .string("[Media payload: use output preview]")
                } else { result[key] = inspectable(child) }
            }
            return .object(result)
        case .array(let values): return .array(values.map(inspectable))
        case .string(let text): return text.hasPrefix("data:") ? .string("[Media payload: use output preview]") : value
        default: return value
        }
    }
}
