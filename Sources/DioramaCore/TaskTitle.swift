import Foundation

/// Provider metadata is kept separate from the compact label. Unknown provenance
/// must not be mistaken for a generated summary or an explicit rename.
public enum TaskTitleSource: String, Codable, Sendable {
    case prompt, provider, summary, explicit
    var priority: Int { switch self { case .prompt: 0; case .summary: 1; case .provider: 2; case .explicit: 3 } }
}

public enum TaskTitle {
    public static func full(_ text: String) -> String {
        let clean = text.components(separatedBy: "<diorama_").first ?? text
        let plain = (try? AttributedString(markdown: clean, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))).map { String($0.characters) } ?? clean
        return plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public static func compact(_ text: String) -> String {
        let words = full(text).split(whereSeparator: \.isWhitespace)
        return words.prefix(6).joined(separator: " ") + (words.count > 6 ? "…" : "")
    }
}

/// Small, rebuildable metadata cache. No transcript bodies or generated titles.
struct SavedTaskTitle: Codable, Equatable {
    var text: String
    var source: TaskTitleSource
}

public extension Session {
    var displayTitle: String { TaskTitle.compact(title) }
    func retainingTitle(from known: Session) -> Session {
        guard !known.title.isEmpty,
              title.isEmpty || title.hasPrefix("Untitled") || known.titleSource.priority > titleSource.priority else { return self }
        var result = updated(title: known.title)
        result.titleSource = known.titleSource
        return result
    }
}
