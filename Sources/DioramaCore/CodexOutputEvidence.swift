import Foundation
import CoreFoundation

/// Adapts saved rollout items to the public App Server presentation vocabulary.
/// No execution or capability lookup is performed while normalizing evidence.
public enum CodexOutputEvidence {
    /// The message Codex posts for `request_user_input_async`: delivered asynchronously, with
    /// the questions attached.
    public static func isAsyncQuestion(_ item: WireValue) -> Bool {
        item["delivery"].string == "async" || !item["questions"].array.isEmpty
    }
    public static func wire(_ value: Any) -> WireValue {
        switch value {
        case let object as [String: Any]: return .object(object.mapValues(wire))
        case let array as [Any]: return .array(array.map(wire))
        case let string as String: return .string(string)
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        default: return .null
        }
    }

    public static func canonical(_ value: WireValue, cwd: String? = nil) -> WireValue {
        var fields = value.object
        let original = value["type"].string ?? "unknown"
        var type = original.prefix(1).lowercased() + original.dropFirst()
        if type == "extension" {
            let kind = value["kind"].string ?? "unknown"
            type = kind.prefix(1).lowercased() + kind.dropFirst()
            if ["web_search", "web.search"].contains(type) { type = "webSearch" }
        }
        fields["type"] = .string(type)
        for (old, new) in [("aggregated_output", "aggregatedOutput"), ("exit_code", "exitCode"), ("saved_path", "savedPath"), ("receiver_thread_ids", "receiverThreadIds"), ("agent_thread_id", "agentThreadId"), ("content_items", "contentItems")] where fields[new] == nil {
            fields[new] = fields[old]
        }
        if fields["cwd"] == nil, let cwd { fields["cwd"] = .string(cwd) }
        // Saved transcripts store argv arrays; App Server reports one shell string.
        if case .array(let argv) = value["command"] { fields["command"] = .string(argv.compactMap(\.string).joined(separator: " ")) }
        if let args = fields["arguments"]?.string, args.utf8.count <= 128 * 1024,
           let parsed = try? JSONSerialization.jsonObject(with: Data(args.utf8)) { fields["arguments"] = wire(parsed) }
        if fields["text"] == nil, type == "agentMessage" { fields["text"] = .string(text(value["content"])) }
        if fields["durationMs"] == nil, value["duration"] != .null,
           let seconds = value["duration"]["secs"].number, let nanos = value["duration"]["nanos"].number {
            fields["durationMs"] = .number(seconds * 1000 + nanos / 1_000_000)
        }
        if type == "fileChange", case .object(let changes) = value["changes"] {
            fields["changes"] = .array(changes.keys.sorted().map { path in
                let change = changes[path] ?? .null
                var entry = change.object
                entry["path"] = .string(path)
                entry["diff"] = change["unified_diff"] == .null ? .null : change["unified_diff"]
                entry["kind"] = .object(["type": change["type"], "movePath": change["move_path"]])
                return .object(entry)
            })
        }
        return .object(fields)
    }
    public static func text(_ content: WireValue) -> String {
        if let string = content.string { return bounded(string) }
        let values = content.array.compactMap { block -> String? in
            ["text", "input_text", "output_text", "inputtext"].contains((block["type"].string ?? "").lowercased()) ? block["text"].string : nil
        }
        return bounded(values.joined(separator: "\n"))
    }
    public static func bounded(_ text: String) -> String {
        text.count <= 128 * 1024 ? text : String(text.prefix(128 * 1024)) + "\n[Preview truncated]"
    }
    public static func safeDetails(_ value: WireValue) -> WireValue {
        switch value {
        case .object(let object):
            if ["reasoning", "thinking", "encrypted_content", "redacted_thinking"].contains(object["type"]?.string ?? "") { return .string("[Private reasoning omitted]") }
            var sanitized: [String: WireValue] = [:]
            for (key, child) in object where !["encrypted_content", "encryptedContent", "raw_content", "rawContent"].contains(key) {
                if (key == "result" && object["type"]?.string == "imageGeneration") || key == "blob" || (key == "data" && ["image", "audio", "base64"].contains(object["type"]?.string ?? "")) {
                    sanitized[key] = .string("[Inline media available through Preview]")
                } else { sanitized[key] = safeDetails(child) }
            }
            return .object(sanitized)
        case .array(let array): return .array(array.map(safeDetails))
        case .string(let string): return .string(string.hasPrefix("data:") ? "[Inline media available through Preview]" : bounded(string))
        default: return value
        }
    }
    public static func localPath(_ path: String?, cwd: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("/") && !path.hasPrefix("//") { return path }
        guard !path.contains(":"), let cwd, cwd.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: cwd).appendingPathComponent(path).standardizedFileURL.path
    }
    public static func outputs(_ blocks: [WireValue], id: String) -> [ClaudeOutput] {
        var results: [ClaudeOutput] = blocks.prefix(100).enumerated().compactMap { index, block in
            let key = id + ":output:\(index)", type = block["type"].string ?? "unknown"
            if ["text", "input_text", "output_text", "inputText", "encrypted_content", "reasoning", "thinking"].contains(type) { return nil }
            var name = block["name"].string ?? block["title"].string ?? "Output"
            var location: String?, encoded: String?, mime: String?
            var kind = "resource"
            switch type {
            case "image", "input_image", "inputImage":
                name = block["name"].string ?? "Image"; kind = "image"
                location = block["image_url"].string ?? block["imageUrl"].string ?? block["url"].string
                encoded = block["data"].string; mime = block["mimeType"].string ?? "image/png"
            case "localImage":
                kind = "image"; name = "Attached image"; location = localPath(block["path"].string, cwd: nil)
            case "file", "document":
                name = block["filename"].string ?? block["name"].string ?? "Document"
                location = block["file_url"].string ?? block["uri"].string ?? localPath(block["path"].string, cwd: nil)
                mime = block["mimeType"].string
            case "resource_link", "resourceLink": location = block["uri"].string; mime = block["mimeType"].string
            case "resource":
                let resource = block["resource"]
                location = resource["uri"].string; mime = resource["mimeType"].string
                encoded = resource["blob"].string ?? resource["text"].string.map { Data($0.utf8).base64EncodedString() }
            case "input_audio", "inputAudio", "audio":
                kind = "unsupported"; name = "Audio output"; location = block["audio_url"].string ?? block["audioUrl"].string
            default: kind = "unsupported"; name = "Unsupported output · " + String(type.prefix(100))
            }
            if let url = location, url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") {
                let header = String(url[..<comma])
                if header.hasSuffix(";base64") { encoded = String(url[url.index(after: comma)...]); mime = String(header.dropFirst(5).dropLast(7)) }
                location = nil
            }
            if let inline = encoded, inline.hasPrefix("data:"), let comma = inline.firstIndex(of: ",") {
                let header = String(inline[..<comma])
                if header.hasSuffix(";base64") { encoded = String(inline[inline.index(after: comma)...]); mime = String(header.dropFirst(5).dropLast(7)) }
                else { encoded = nil }
            }
            let oversized = (encoded?.utf8.count ?? 0) > 8 * 1024 * 1024
            return ClaudeOutput(id: key, name: name, kind: kind, location: location, mediaType: mime, encoded: oversized ? nil : encoded,
                note: oversized ? "Inline preview exceeds 8 MiB" : kind == "unsupported" ? "This output type has no preview yet." : nil)
        }
        if blocks.count > 100 { results.append(.init(id: id + ":omitted", name: "Additional outputs omitted", kind: "unsupported", note: "Showing the first 100 content blocks. Inspect the source client for the complete output.")) }
        return results
    }
}

public extension ToolResult {
    var contentBlocks: [WireValue] {
        item["result"]["content"].array + item["contentItems"].array + item["output"].array
    }
    var outputs: [ClaudeOutput] {
        let key = item["id"].string ?? type
        var outputs = CodexOutputEvidence.outputs(contentBlocks, id: key)
        let cwd = item["cwd"].string
        if type == "imageGeneration" {
            if let path = CodexOutputEvidence.localPath(item["savedPath"].string, cwd: cwd) {
                outputs.append(.init(id: key + ":image", name: URL(fileURLWithPath: path).lastPathComponent, kind: "image", location: path))
            } else if let encoded = item["result"].string, !encoded.isEmpty {
                outputs += CodexOutputEvidence.outputs([.object(["type": .string("image"), "data": .string(encoded), "mimeType": .string("image/png")])], id: key)
            }
        } else if type == "imageView", let path = CodexOutputEvidence.localPath(item["path"].string, cwd: cwd) {
            outputs.append(.init(id: key + ":view", name: URL(fileURLWithPath: path).lastPathComponent, kind: "image", location: path, note: "Viewed by the agent; not necessarily produced by it"))
        } else if type == "fileChange", status == "completed" {
            for (index, change) in item["changes"].array.enumerated() {
                let operation = change["kind"]["type"].string ?? change["kind"].string ?? ""
                guard !["delete", "remove"].contains(operation),
                      let path = CodexOutputEvidence.localPath(change["kind"]["movePath"].string ?? change["path"].string, cwd: cwd) else { continue }
                outputs.append(.init(id: key + ":file:\(index)", name: URL(fileURLWithPath: path).lastPathComponent, kind: "file", location: path, note: "Reported file change · preview shows current file"))
            }
        }
        return outputs
    }
}
