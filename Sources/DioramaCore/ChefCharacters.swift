import Foundation

/// Which chef character each agent wears, per project kitchen. A new chef gets a random character
/// that no chef in its kitchen is wearing; only once every character is in use do they repeat
/// (then the least-worn ones). Once given, a character stays with its agent: when its chef leaves
/// and comes back, and across relaunches.
public struct ChefCharacters: Codable, Sendable {
    /// project + "\u{1E}" + agent identity → character id.
    public var assignments: [String: String] = [:]
    public init() {}

    public static func key(project: String, agent: String) -> String { project + "\u{1E}" + agent }

    /// The character for `agent`: its own if it has one, otherwise a new pick. `inScene` lists the
    /// characters the other chefs in this kitchen are wearing now (repeats included).
    public mutating func character<R: RandomNumberGenerator>(for agent: String, project: String, available: [String],
                                                             inScene: [String], using random: inout R) -> String {
        let key = Self.key(project: project, agent: agent)
        if let existing = assignments[key], available.contains(existing) { return existing }
        guard !available.isEmpty else { return "" }
        let worn = Dictionary(inScene.map { ($0, 1) }, uniquingKeysWith: +)
        let fewest = available.map { worn[$0] ?? 0 }.min() ?? 0
        let choice = available.filter { (worn[$0] ?? 0) == fewest }.randomElement(using: &random)!
        assignments[key] = choice
        return choice
    }

    public mutating func character(for agent: String, project: String, available: [String], inScene: [String]) -> String {
        var random = SystemRandomNumberGenerator()
        return character(for: agent, project: project, available: available, inScene: inScene, using: &random)
    }
}

public actor ChefCharactersWriter {
    private var revision = 0
    public init() {}
    public func save(_ value: ChefCharacters, revision: Int, to url: URL) throws {
        guard revision > self.revision else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        self.revision = revision
    }
}
