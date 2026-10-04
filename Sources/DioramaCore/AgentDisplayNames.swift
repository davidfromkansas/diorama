import Foundation

/// Display metadata only. Keys are scoped native identities, never routing replacements.
public struct AgentDisplayNames: Codable, Sendable {
    public var names: [String: String]? = [:]
    public init() {}
    public static func meaningful(_ name: String) -> Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !value.isEmpty && !["main", "main agent", "agent", "subagent", "sub-agent", "worker", "assistant", "codex", "claude"].contains(value)
            && value.range(of: #"^(agent|subagent|worker)[\s#_-]*\d+$"#, options: .regularExpression) == nil
    }
    public mutating func resolve(project: String, identities: [String], reported: String) -> String {
        let keys = identities.map { project + "\u{1E}" + $0 }
        var values = names ?? [:]
        let existing = keys.compactMap { values[$0] }.first
        let chosen: String
        if Self.meaningful(reported) { chosen = reported }
        else if let existing { chosen = existing }
        else {
            let used = Set(values.filter { $0.key.hasPrefix(project + "\u{1E}") }.map { $0.value.lowercased() })
            let bank = "Milo Iris Otto Ada Felix Nora Leo Luna Theo Cleo Hugo Esme Finn Vera Arlo Ruby Remy Alba Nico Wren Axel Cora Ezra Faye Enzo Ivy Luca Mira Owen Opal Rory Sage Eli June Kai Lena Max Nina Orin Pia Quinn Rose Seth Tess Uri Veda Will Xena Yara Zane Atlas Basil Cedar Delta Echo Flora Glen Hazel Indigo Juno Koda Lark Maple Nova Olive Poppy Reed Sora Toby Uma Vale Willa Yuki Zora".split(separator: " ").map(String.init)
            var candidate = bank.first { !used.contains($0.lowercased()) }
            var suffix = 0
            while candidate == nil {
                var number = suffix, letters = ""
                repeat { letters = String(UnicodeScalar(97 + number % 26)!) + letters; number = number / 26 - 1 } while number >= 0
                let name = "Milo" + letters
                if !used.contains(name.lowercased()) { candidate = name }
                suffix += 1
            }
            chosen = candidate!
        }
        for key in keys { values[key] = chosen }
        names = values
        return chosen
    }
}

public actor AgentDisplayNameWriter {
    private var revision = 0
    public init() {}
    public func save(_ value: AgentDisplayNames, revision: Int, to url: URL) throws {
        guard revision > self.revision else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        self.revision = revision
    }
}

public extension SessionActivityRecord {
    /// Task descriptions and imported conversation titles are not provider-assigned names.
    var reportedAgentName: String {
        if let name = data["agentNickname"].string, AgentDisplayNames.meaningful(name) { return name }
        if provider == Provider.codex.rawValue, source != "External transcript", AgentDisplayNames.meaningful(title) { return title }
        return "Subagent"
    }
}
