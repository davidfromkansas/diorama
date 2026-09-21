import Foundation

public enum SessionClassification: String, Sendable {
    case conversation = "Conversation"
    case subagent = "Subagent"
    case internalReview = "Internal approval review"
    case unknown = "Unknown session type"
}

public enum MessageCategory: Sendable {
    case user, assistant, activity, context
}

public extension Entry {
    var category: MessageCategory {
        switch kind {
        case "You": .user
        case "Assistant": .assistant
        case "System context": .context
        default: .activity
        }
    }
}

public struct SessionRow: Identifiable, Sendable {
    public let session: Session
    public let depth: Int
    public let parentUnavailable: Bool
    public var id: String { session.id }
    public var label: String {
        session.classification == .subagent && parentUnavailable ? "Subagent · parent unknown" : session.classification.rawValue
    }
}

public enum SessionPresentation {
    public static func rows(_ sessions: [Session], showInternal: Bool) -> [SessionRow] {
        let visible = sessions.filter { showInternal || $0.classification != .internalReview }
        var parents: [String: String] = [:]
        for child in visible where child.classification == .subagent {
            if let parent = visible.first(where: {
                $0.id != child.id && $0.provider == child.provider && $0.sessionID == child.parentID && $0.classification != .internalReview
                && ($0.classification != .subagent || $0.sessionID != child.sessionID)
            }) { parents[child.id] = parent.id }
        }
        var result: [SessionRow] = []
        var visited: Set<String> = []
        func append(_ session: Session, depth: Int) {
            guard visited.insert(session.id).inserted else { return }
            result.append(SessionRow(session: session, depth: depth, parentUnavailable: session.classification == .subagent && depth == 0))
            for child in visible where parents[child.id] == session.id { append(child, depth: depth + 1) }
        }
        for session in visible where parents[session.id] == nil { append(session, depth: 0) }
        // Broken/cyclic relationships must never hide records.
        for session in visible where !visited.contains(session.id) { append(session, depth: 0) }
        return result
    }

    public static func selection(_ current: String?, rows: [SessionRow]) -> String? {
        if let current, rows.contains(where: { $0.id == current }) { return current }
        return rows.first(where: { $0.session.classification == .conversation })?.id ?? rows.first?.id
    }

    public static func counts(_ sessions: [Session], showInternal: Bool) -> String {
        let conversations = sessions.filter { $0.classification == .conversation }.count
        let subagents = sessions.filter { $0.classification == .subagent }.count
        let reviews = sessions.filter { $0.classification == .internalReview }.count
        let unknown = sessions.filter { $0.classification == .unknown }.count
        var parts = ["\(conversations) conversation\(conversations == 1 ? "" : "s")", "\(subagents) subagent\(subagents == 1 ? "" : "s")"]
        if reviews > 0 { parts.append("\(reviews) internal review\(reviews == 1 ? "" : "s")\(showInternal ? "" : " hidden")") }
        if unknown > 0 { parts.append("\(unknown) unknown") }
        return parts.joined(separator: " · ")
    }
}

public enum MessageContent {
    public struct Part: Equatable, Sendable {
        public let text: String
        public let context: Bool
    }

    public static func split(_ text: String, provider: Provider) -> [Part] {
        if provider == .claude {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("<command-name>/model</command-name>") && trimmed.hasSuffix("</command-args>")) ||
               (trimmed.hasPrefix("<local-command-stdout>") && trimmed.hasSuffix("</local-command-stdout>")) {
                return [Part(text: text, context: true)]
            }
        }
        if provider != .codex && !text.contains("<diorama_html_view>") && !text.contains("<diorama_goal_context>") { return [Part(text: text, context: false)] }
        // Only known complete envelopes at line boundaries, outside fenced examples.
        // Unknown XML, inline examples, and unterminated envelopes remain user text.
        let pattern = #"(?ms)(?:^<(environment_context|recommended_plugins|diorama_html_view|diorama_goal_context)>.*?</\1>[ \t]*(?=\r?$|\n|<environment_context>|<recommended_plugins>|<diorama_html_view>|<diorama_goal_context>)|^# AGENTS\.md instructions for [^\n]+\n\s*<INSTRUCTIONS>.*?</INSTRUCTIONS>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [Part(text: text, context: false)] }
        let ns = text as NSString
        var cursor = 0
        var parts: [Part] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let prefix = ns.substring(to: match.range.location)
            var fence: String?
            for line in prefix.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    let marker = String(trimmed.prefix(3))
                    if fence == nil { fence = marker } else if fence == marker { fence = nil }
                }
            }
            guard fence == nil else { continue }
            let block = ns.substring(with: match.range)
            let recognized = block.hasPrefix("<environment_context>")
                ? (block.contains("<cwd>") && block.contains("<shell>")) || (block.contains("<current_date>") && block.contains("<filesystem>"))
                : block.hasPrefix("# AGENTS.md instructions for ") || block.contains("Here is a list of plugins that are available but not installed.") || (block.hasPrefix("<diorama_html_view>") && block.contains("Maintain this conversation's live HTML view"))
            guard recognized || (block.hasPrefix("<diorama_goal_context>") && block.contains("Diorama goal:")) else { continue }
            if match.range.location > cursor { parts.append(Part(text: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), context: false)) }
            parts.append(Part(text: block, context: true))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { parts.append(Part(text: ns.substring(from: cursor), context: false)) }
        return parts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
