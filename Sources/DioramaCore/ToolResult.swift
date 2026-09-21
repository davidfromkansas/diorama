import Foundation

/// Presentation is driven by typed items, never inferred from arbitrary assistant prose.
public struct ToolResult: Equatable, Sendable, Codable {
    public let item: WireValue
    public var type: String { item["type"].string ?? "Tool" }
    public var title: String {
        switch type {
        case "commandExecution": item["command"].string ?? "Command"
        case "fileChange": "Changed \(item["changes"].array.count) files"
        case "webSearch": "Web search"
        case "imageGeneration": "Generated image"
        case "mcpToolCall": (item["server"].string ?? "Connector") + " · " + (item["tool"].string ?? "Tool")
        case "collabAgentToolCall", "collabToolCall": "Agent collaboration"
        case "exitedReviewMode": "Code review findings"
        default: type
        }
    }
    public var status: String { item["status"].string ?? "Reported" }
    public var output: String {
        if let output = item["aggregatedOutput"].string { return output }
        if let review = item["review"].string { return review }
        let content = item["result"]["content"].array
        return content.compactMap { $0["text"].string }.joined(separator: "\n")
    }
    public var rawPreview: String {
        var payload = item.object
        if type == "imageGeneration", let encoded = payload["result"]?.string { payload["result"] = .string("[Image data: \(encoded.utf8.count) bytes; shown in preview]") }
        if case .object(var result) = payload["result"], case .array(let blocks) = result["content"] {
            result["content"] = .array(blocks.map { block in
                guard block["type"].string == "image" else { return block }
                var fields = block.object; fields["data"] = .string("[Image data shown in preview]"); return .object(fields)
            })
            payload["result"] = .object(result)
        }
        let text = WireValue.object(payload).pretty
        return text.count > 128 * 1024 ? String(text.prefix(128 * 1024)) + "\n[Preview truncated]" : text
    }
    public var workers: [String] { item["receiverThreadIds"].array.compactMap(\.string) }
    public var resources: [WireValue] { item["result"]["content"].array.filter { $0["type"].string == "resource_link" || $0["type"].string == "resourceLink" } }
    public init?(item: WireValue) {
        guard ["commandExecution", "fileChange", "webSearch", "imageGeneration", "mcpToolCall", "collabAgentToolCall", "collabToolCall", "exitedReviewMode"].contains(item["type"].string ?? "") else { return nil }
        self.item = item
    }
}
