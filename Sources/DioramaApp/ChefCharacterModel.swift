import Foundation
import DioramaCore

/// The characters agents wear in the kitchen (`ChefCharacters`), saved so a chef keeps its look
/// when it leaves and comes back and across relaunches. Like the agent names, assigning one
/// never invalidates SwiftUI.
@MainActor final class ChefCharacterModel {
    static let shared = ChefCharacterModel(url: saves ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Diorama/ChefCharacters.json") : nil)
    /// Tests never read or write the real file.
    private static let saves = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        && !Bundle.main.bundlePath.hasSuffix(".xctest") && ProcessInfo.processInfo.processName != "swiftpm-testing-helper"
    private let url: URL?
    private var value: ChefCharacters
    private let writer = ChefCharactersWriter()
    private var revision = 0
    private(set) var error: String?

    init(url: URL?) {
        self.url = url
        value = url.flatMap { try? JSONDecoder().decode(ChefCharacters.self, from: Data(contentsOf: $0)) } ?? .init()
    }

    /// The character `agent` wears in `project`'s kitchen; `inScene` are the characters the other
    /// chefs there wear now.
    func character(for agent: String, project: String, available: [String], inScene: [String]) -> String {
        let before = value.assignments[ChefCharacters.key(project: project, agent: agent)]
        let character = value.character(for: agent, project: project, available: available, inScene: inScene)
        if character != before, let url {
            revision += 1
            let snapshot = value, number = revision, writer = writer
            Task { do { try await writer.save(snapshot, revision: number, to: url) } catch { self.error = "Chef characters could not be saved: " + error.localizedDescription } }
        }
        return character
    }
}
