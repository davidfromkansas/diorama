import Foundation

/// Codex-only presentation facts. Claude is not required to adopt this vocabulary.
public struct CodexPresentation: Codable, Equatable, Sendable {
    public var category: String
    public var title: String
    public var status: String
    public var evidence: WireValue
    public init(category: String, title: String, status: String = "Reported", evidence: WireValue = .null) {
        self.category = category; self.title = title; self.status = status; self.evidence = evidence
    }
    public var usage: WireValue {
        let info = evidence["info"] == .null ? evidence : evidence["info"]
        return info["last_token_usage"] == .null ? info["usage"] : info["last_token_usage"]
    }
    public var cumulativeUsage: WireValue {
        evidence["info"]["total_token_usage"] == .null ? evidence["total_token_usage"] : evidence["info"]["total_token_usage"]
    }
    public static func tool(_ tool: ToolResult) -> Self {
        .init(category: tool.type, title: tool.title, status: tool.status)
    }
}
