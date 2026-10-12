import Foundation

/// The permission mode Codex and Claude Code start new conversations in, kept in their own
/// settings files: `~/.codex/config.toml` and `~/.claude/settings.json`. The terminal tools and
/// both desktop apps read these, so a default changed here is the default everywhere. (A mode
/// picked inside the Codex or Claude app only lasts in that app; neither writes it back.)
public struct ProviderPermissionDefaults: Sendable {
    public var codexConfig: URL
    public var claudeSettings: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        codexConfig = home.appendingPathComponent(".codex/config.toml")
        claudeSettings = home.appendingPathComponent(".claude/settings.json")
    }

    /// The mode new conversations start in, or nil when it's something Diorama has no preset for.
    public func choice(for provider: Provider) -> ApprovalReviewChoice? {
        provider == .claude ? claudeChoice() : codexChoice()
    }
    /// Whether the person set a default at all, rather than leaving the provider's built-in one.
    public func isSet(for provider: Provider) -> Bool {
        if provider == .claude { return claudeMode() != nil }
        let toml = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        return ["approval_policy", "sandbox_mode", "approvals_reviewer", "default_permissions"].contains { Self.topLevelValue(toml, $0) != nil }
    }
    public func set(_ choice: ApprovalReviewChoice, for provider: Provider) throws {
        if provider == .claude { try setClaude(choice) } else { try setCodex(choice) }
    }

    // MARK: Codex

    func codexChoice() -> ApprovalReviewChoice? {
        let toml = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        // A named permission profile is custom: Diorama doesn't map it to a preset.
        guard Self.topLevelValue(toml, "default_permissions") == nil else { return nil }
        let policy = Self.topLevelValue(toml, "approval_policy"), sandbox = Self.topLevelValue(toml, "sandbox_mode")
        if policy == "never", sandbox == "danger-full-access" { return .fullAccess }
        // Codex's built-in default asks on request inside the workspace, reviewed by you.
        guard policy == nil || policy == "on-request", sandbox == nil || sandbox == "workspace-write" else { return nil }
        return Self.topLevelValue(toml, "approvals_reviewer") == "auto_review" ? .autoReview : .user
    }
    func setCodex(_ choice: ApprovalReviewChoice) throws {
        let values: [(String, String?)]
        switch choice {
        case .user: values = [("approval_policy", "on-request"), ("sandbox_mode", "workspace-write"), ("approvals_reviewer", "user")]
        case .autoReview: values = [("approval_policy", "on-request"), ("sandbox_mode", "workspace-write"), ("approvals_reviewer", "auto_review")]
        case .fullAccess: values = [("approval_policy", "never"), ("sandbox_mode", "danger-full-access"), ("approvals_reviewer", nil)]
        case .acceptEdits, .inherit: throw ExecutionRPCRejection("Codex has no default for \(choice.title).")
        }
        let toml = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        try FileManager.default.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.settingTopLevel(toml, values).write(to: codexConfig, atomically: true, encoding: .utf8)
    }
    /// A top-level key's string value (before the first `[table]`), without quotes or comment.
    static func topLevelValue(_ toml: String, _ key: String) -> String? {
        for line in toml.components(separatedBy: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[") { return nil }
            guard let rest = Self.assignment(text, key) else { continue }
            var value = rest
            if value.hasPrefix("\"") || value.hasPrefix("'") {
                let quote = value.removeFirst()
                return value.firstIndex(of: quote).map { String(value[..<$0]) } ?? value
            }
            return value.split(separator: "#", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
    /// The file with these top-level keys set (nil removes one); everything else is left as written.
    static func settingTopLevel(_ toml: String, _ values: [(String, String?)]) -> String {
        var lines = toml.isEmpty ? [] : toml.components(separatedBy: "\n")
        for (key, value) in values {
            let end = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
            let existing = lines[..<end].firstIndex { Self.assignment($0.trimmingCharacters(in: .whitespaces), key) != nil }
            let line = value.map { "\(key) = \"\($0)\"" }
            switch (existing, line) {
            case let (index?, line?): lines[index] = line
            case let (index?, nil): lines.remove(at: index)
            case let (nil, line?):
                var at = end
                while at > 0, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
                lines.insert(line, at: at)
                // Keep a blank line between the top-level keys and the first table.
                if at + 1 < lines.count, lines[at + 1].trimmingCharacters(in: .whitespaces).hasPrefix("[") { lines.insert("", at: at + 1) }
            case (nil, nil): break
            }
        }
        var text = lines.joined(separator: "\n")
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        return text
    }
    /// What follows `key =` on a trimmed line, or nil when the line doesn't assign that key.
    private static func assignment(_ text: String, _ key: String) -> String? {
        guard text.hasPrefix(key) else { return nil }
        let rest = text.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("=") else { return nil }
        return rest.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    // MARK: Claude Code

    func claudeMode() -> String? {
        guard let data = try? Data(contentsOf: claudeSettings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["permissions"] as? [String: Any])?["defaultMode"] as? String
    }
    func claudeChoice() -> ApprovalReviewChoice? { claudeMode().flatMap { ApprovalReviewChoice.claude($0) } }
    func setClaude(_ choice: ApprovalReviewChoice) throws {
        guard let mode = choice.claudeMode else { throw ExecutionRPCRejection("Claude has no default for \(choice.title).") }
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: claudeSettings) {
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ExecutionRPCRejection("Claude's settings file isn't a JSON object, so Diorama left it alone.")
            }
            json = existing
            // Rewriting reformats the file, so keep the original the first time.
            let backup = claudeSettings.appendingPathExtension("diorama-backup")
            if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup) }
        }
        var permissions = json["permissions"] as? [String: Any] ?? [:]
        permissions["defaultMode"] = mode
        json["permissions"] = permissions
        try FileManager.default.createDirectory(at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: claudeSettings, options: .atomic)
    }
}
