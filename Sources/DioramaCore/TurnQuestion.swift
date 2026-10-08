import Foundation

/// What a turn's final message asks of the person, if anything: a real question the agent needs
/// answered before it can go on, or an offer of more work ("Want me to open a PR?").
public enum TurnQuestion: Equatable, Sendable {
    case question(String)
    case offer(String)

    public var text: String {
        switch self { case let .question(text), let .offer(text): text }
    }

    /// The last question in the final paragraph, when nothing but a short tail follows it
    /// ("…should I use? Nothing was changed."). Code blocks and quoted lines don't count.
    public static func asking(_ message: String) -> TurnQuestion? {
        var lines: [String] = [], fenced = false
        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fenced.toggle(); continue }
            if fenced || trimmed.hasPrefix(">") { continue }
            lines.append(trimmed)
        }
        // The last paragraph with any text in it.
        let paragraphs = lines.split(whereSeparator: \.isEmpty).map { $0.joined(separator: " ") }
        guard let paragraph = paragraphs.last else { return nil }
        let sentences = Self.sentences(paragraph)
        guard let index = sentences.lastIndex(where: { $0.hasSuffix("?") }) else { return nil }
        let tail = sentences[(index + 1)...]
        guard tail.count <= 2, tail.reduce(0, { $0 + $1.count }) < 120 else { return nil }
        // A question of more than one sentence starts where the asking does ("I couldn't find
        // it. Which repository should I use?" asks the second).
        let question = sentences[index]
        return isOffer(question) ? .offer(question) : .question(question)
    }

    static func isOffer(_ question: String) -> Bool {
        let lowered = question.lowercased()
        return ["want me to", "would you like me to", "would you like", "should i also", "shall i", "do you want me to",
                "let me know if", "anything else", "need anything else", "happy to"]
            .contains { lowered.hasPrefix($0) || lowered.contains(" " + $0) }
    }

    /// Splits on sentence ends (. ! ?) followed by a space, keeping the punctuation.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = [], current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            if ".!?".contains(character), next == " " {
                let sentence = current.trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }
}
