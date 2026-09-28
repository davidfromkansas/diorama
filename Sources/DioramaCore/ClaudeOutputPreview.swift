import Foundation

public struct ClaudePreview: Sendable {
    public var kind: String
    public var data: Data
    public var notice: String?
}

public enum ClaudeOutputPreview {
    public static let maximumBytes = 16 * 1024 * 1024
    public static func externalURL(_ output: ClaudeOutput) -> URL? {
        guard let location = output.location else { return nil }
        if location.hasPrefix("/") { return URL(fileURLWithPath: location) }
        guard let url = URL(string: location), ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    public static func load(_ output: ClaudeOutput) async throws -> ClaudePreview {
        try await Task.detached { try read(output) }.value
    }
    private static func bytes(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= maximumBytes else { throw AppServerFailure("Preview requires a regular file smaller than 16 MiB.") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw AppServerFailure("Preview exceeds 16 MiB.") }
        return data
    }
    private static func read(_ output: ClaudeOutput) throws -> ClaudePreview {
        let url = externalURL(output)
        let data: Data
        if let encoded = output.encoded {
            guard encoded.utf8.count <= 8 * 1024 * 1024, let decoded = Data(base64Encoded: encoded) else { throw AppServerFailure("Inline preview is unavailable or too large.") }
            data = decoded
        } else {
            guard let url, url.isFileURL else { throw AppServerFailure(output.note ?? "This output has no readable local copy. Open its link externally.") }
            data = try bytes(url)
        }
        let ext = url?.pathExtension.lowercased() ?? ""
        if output.mediaType?.hasPrefix("image/") == true || ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext) { return .init(kind: "image", data: data) }
        if output.mediaType == "application/pdf" || ext == "pdf" { return .init(kind: "pdf", data: data) }
        guard let text = String(data: data, encoding: .utf8), !data.contains(0) else { throw AppServerFailure("This document requires an external viewer.") }
        if ["html", "htm"].contains(ext) || output.mediaType == "text/html" {
            let embedded = try embedAssets(text, root: url?.deletingLastPathComponent())
            return .init(kind: "html", data: Data(embedded.utf8), notice: "Interactive local preview. Networking, native integration, and navigation are disabled. External dependencies may not render.")
        }
        return .init(kind: ext == "md" || output.mediaType == "text/markdown" ? "markdown" : "text", data: data)
    }
    /// Only explicit relative script, stylesheet and image references are embedded.
    /// CSS imports, modules and runtime fetches remain blocked by the web sandbox.
    static func embedAssets(_ html: String, root: URL?) throws -> String {
        guard let root else { return html }
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let pattern = #"(?is)<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>\s*</script\s*>|<link\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>|<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#
        let regex = try NSRegularExpression(pattern: pattern)
        var result = html, total = html.utf8.count
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard matches.count <= 200 else { throw AppServerFailure("This page references too many assets to preview.") }
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let group = (1...3).first { match.range(at: $0).location != NSNotFound }!
            guard let pathRange = Range(match.range(at: group), in: html) else { continue }
            let path = String(html[pathRange])
            guard !path.hasPrefix("/"), !path.contains(":"), !path.contains("?"), !path.contains("#"),
                  let decoded = path.removingPercentEncoding, !decoded.split(separator: "/").contains("..") else { continue }
            let file = canonical.appendingPathComponent(decoded).resolvingSymlinksInPath().standardizedFileURL
            guard file.path.hasPrefix(canonical.path + "/") else { throw AppServerFailure("A companion asset points outside the output folder.") }
            guard let asset = try? bytes(file) else { continue }
            total += asset.count * 2
            guard total <= maximumBytes else { throw AppServerFailure("Page and companion assets exceed the preview limit.") }
            let replacement: String
            if group == 1, let script = String(data: asset, encoding: .utf8) {
                replacement = "<script>" + script.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive) + "</script>"
            } else if group == 2, file.pathExtension.lowercased() == "css", let css = String(data: asset, encoding: .utf8) {
                replacement = "<style>" + css.replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive) + "</style>"
            } else if group == 3 {
                let mime = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml"][file.pathExtension.lowercased()]
                guard let mime else { continue }
                replacement = String(result[range]).replacingOccurrences(of: path, with: "data:\(mime);base64," + asset.base64EncodedString())
            } else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
