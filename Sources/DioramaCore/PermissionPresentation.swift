import Foundation

/// Display-only metadata. Decisions and grants always come from the original request.
public struct PermissionPresentation: Sendable {
    public let title: String
    public let target: String
    public let reason: String?
    public let scope: String
    public let details: String
    public let isLong: Bool

    public init(request: ExecutionRequest) {
        let p = request.params
        let tool = p["toolName"].string ?? ""
        let input = p["toolInput"]
        let command = input["command"].string ?? p["command"].string
        let path = input["file_path"].string ?? p["path"].string
        let suppliedReason = p["reason"].string ?? input["description"].string
        reason = suppliedReason.flatMap { $0.isEmpty || $0 == "Claude requests permission for this action." ? nil : $0 }
        var fullTarget: String
        if request.method == "item/permissions/requestApproval" {
            title = "Allow these permissions?"
            fullTarget = Self.permissionScope(p["permissions"])
            scope = "Applies to this turn only."
        } else {
            scope = "Allow once approves only this action."
            switch tool {
            case "Read": title = "Read this file?"; fullTarget = path ?? "File path unavailable — review details."
            case "Edit", "Write", "MultiEdit": title = tool == "Write" ? "Write this file?" : "Edit this file?"; fullTarget = path ?? "File path unavailable — review details."
            case "WebFetch": title = "Fetch this page?"; fullTarget = input["url"].string ?? "URL unavailable — review details."
            case "Bash", "PowerShell": title = "Run this command?"; fullTarget = command ?? "Command unavailable — review details."
            default:
                if !tool.isEmpty { title = "Allow this tool action?"; fullTarget = tool + "\nEffects are not known to Diorama. Review the arguments." }
                else if request.method == "item/fileChange/requestApproval" { title = "Allow these file changes?"; fullTarget = path ?? p["grantRoot"].string ?? "Review the requested changes and scope." }
                else { title = "Run this command?"; fullTarget = command ?? "Command unavailable — review details." }
            }
        }
        isLong = fullTarget.count > 240 || fullTarget.components(separatedBy: "\n").count > 4
        target = isLong ? "Long request · review the full action and scope" : fullTarget
        var sections = [fullTarget]
        if let cwd = p["cwd"].string { sections.append("Working folder\n" + cwd) }
        if input != .null { sections.append("Tool arguments\n" + Self.fields(input)) }
        if let reason { sections.append("Agent’s reason\n" + reason) }
        details = sections.joined(separator: "\n\n")
    }

    private static func permissionScope(_ value: WireValue) -> String {
        value.object.sorted { $0.key < $1.key }.map { key, item in
            if key == "network", item.object.keys.sorted() == ["enabled"], item["enabled"] == .bool(true) {
                return "Network access requested · no domain restriction specified"
            }
            return key.replacingOccurrences(of: "_", with: " ").capitalized + "\n" + fields(item)
        }.joined(separator: "\n\n")
    }

    private static func fields(_ value: WireValue) -> String {
        if !value.object.isEmpty {
            return value.object.sorted { $0.key < $1.key }.map { key, value in
                key.replacingOccurrences(of: "_", with: " ") + ": " + fields(value)
            }.joined(separator: "\n")
        }
        if case .array(let values) = value { return values.map(fields).joined(separator: "\n") }
        return value.string ?? value.pretty
    }
}
