import Foundation

/// A task checklist written as Markdown in an agent's message (`- [x] Read files`), as Codex does
/// when asked to keep a to-do list without using its plan tool.
public enum MessageChecklist {
    /// The message's checklist as plan steps (`step`, `status`), or nil when it has fewer than two
    /// checklist lines. Several checklists in one message: the last one stands.
    public static func plan(_ text: String) -> WireValue? {
        var lists: [[WireValue]] = [], current: [WireValue] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = item.firstMatch(in: String(line), range: range),
               let mark = Range(match.range(at: 1), in: line), let title = Range(match.range(at: 2), in: line) {
                let done = line[mark].lowercased() == "x"
                current.append(.object(["step": .string(String(line[title]).trimmingCharacters(in: .whitespaces)), "status": .string(done ? "completed" : "pending")]))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty, !current.isEmpty {
                lists.append(current); current = []
            }
        }
        if !current.isEmpty { lists.append(current) }
        guard let last = lists.last(where: { $0.count >= 2 }) else { return nil }
        return .array(last)
    }
    private static let item = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\]\s+(.+?)\s*$"#)
}
