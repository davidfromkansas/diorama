import Foundation

/// Presentation is driven by typed items, never inferred from arbitrary assistant prose.
public struct ToolResult: Equatable, Sendable, Codable {
    public let item: WireValue
    public var type: String { item["type"].string ?? "Tool" }
    public var title: String {
        switch type {
        case "commandExecution": item["command"].string ?? "Command"
        case "fileChange": "Changed \(item["changes"].array.count) \(item["changes"].array.count == 1 ? "file" : "files")"
        case "webSearch": "Web search"
        case "dynamicToolCall", "functionCall", "functionCallOutput": item["tool"].string ?? item["name"].string ?? "Tool output"
        case "imageView": "Viewed image"
        case "sleep": "Waiting"
        case "subAgentActivity": "Agent activity"
        case "imageGeneration": "Generated image"
        case "mcpToolCall": (item["server"].string ?? "Connector") + " · " + (item["tool"].string ?? "Tool")
        case "collabAgentToolCall", "collabToolCall": "Agent collaboration"
        case "exitedReviewMode": "Code review findings"
        default: type
        }
    }
    public var planSteps: [WireValue] {
        guard ["update_plan", "functions.update_plan"].contains(item["name"].string ?? item["tool"].string ?? "") else { return [] }
        return Array(item["arguments"]["plan"].array.prefix(100))
    }
    public var requestsInput: Bool {
        ["request_user_input", "functions.request_user_input"].contains(item["name"].string ?? item["tool"].string ?? "") && ["Called", "inProgress"].contains(status)
    }
    public var status: String {
        if item["error"] != .null || item["result"]["isError"].bool || item["success"] == .bool(false) || item["failure"] != .null { return "failed" }
        return item["status"].string ?? "Reported"
    }
    public var output: String {
        if let output = item["aggregatedOutput"].string { return CodexOutputEvidence.bounded(output) }
        if let review = item["review"].string { return CodexOutputEvidence.bounded(review) }
        if let output = item["output"].string { return CodexOutputEvidence.bounded(output) }
        return CodexOutputEvidence.text(.array(contentBlocks))
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
        let text = CodexOutputEvidence.safeDetails(.object(payload)).pretty
        return text.count > 128 * 1024 ? String(text.prefix(128 * 1024)) + "\n[Preview truncated]" : text
    }
    public var workers: [String] {
        Array(Set(item["receiverThreadIds"].array.compactMap(\.string) + [item["receiverThreadId"].string, item["newThreadId"].string, item["agentThreadId"].string].compactMap { $0 })).sorted()
    }
    public var resources: [WireValue] { item["result"]["content"].array.filter { $0["type"].string == "resource_link" || $0["type"].string == "resourceLink" } }
    public init?(item: WireValue) {
        let item = CodexOutputEvidence.canonical(item)
        guard ["dynamicToolCall", "functionCall", "functionCallOutput", "imageView", "subAgentActivity", "sleep", "commandExecution", "fileChange", "webSearch", "imageGeneration", "mcpToolCall", "collabAgentToolCall", "collabToolCall", "exitedReviewMode"].contains(item["type"].string ?? "") else { return nil }
        self.item = item
    }
}
