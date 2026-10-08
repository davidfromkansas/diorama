import CryptoKit
import DioramaCore
import Foundation

/// Four-word task labels for name tags, written once per task by a small model from the agent's
/// own provider (through Diorama's existing connection: `ExecutionController.taskLabel`) and kept
/// in ~/Library/Application Support/Diorama/TaskLabels.json. A keyword label stands in until the
/// written one arrives; `revision` moves when one does, so tags can refresh.
final class TaskLabels {
    static let shared = TaskLabels()
    private(set) var revision = 0
    private var labels: [String: String]
    private var pending: Set<String> = []
    private var running = 0
    private var waiting: [(key: String, task: String, latest: String?, provider: Provider)] = []
    /// What each chef's tag last showed, kept while a new turn's label is being written.
    private var shown: [String: String] = [:]
    /// The newest message that counted (not an acknowledgement), per chef.
    private var request: [String: String] = [:]
    /// Writes a label (task, newest request, provider); set once the execution connection exists.
    var generator: ((String, String?, Provider) async -> String?)?
    private let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/TaskLabels.json")
    /// Test runs never call out to a model.
    static let generates = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        && !Bundle.main.bundlePath.hasSuffix(".xctest") && ProcessInfo.processInfo.processName != "swiftpm-testing-helper"
        && UserDefaults.standard.object(forKey: "generatedTaskLabels") as? Bool ?? true

    init(labels: [String: String]? = nil) {
        self.labels = labels ?? (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }
    static func key(_ task: String) -> String {
        SHA256.hash(data: Data(task.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// The label for what a chef is working on now: the task, as updated by the newest message
    /// each turn. A written label when there is one; until it arrives, the chef's previous label
    /// (or a keyword label the first time), and a request for one. Acknowledgements ("yes",
    /// "continue") keep the current label.
    func label(agent: String = "", for task: String, latest: String? = nil, provider: Provider) -> String {
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return "" }
        var latest = latest?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = latest, message.isEmpty || message == task || task.hasPrefix(message) || TaskLabel.isAcknowledgement(message) { latest = nil }
        // An acknowledgement keeps the request the label was last written for.
        let current = latest ?? request[agent]
        if let latest { request[agent] = latest }
        let key = Self.key(current.map { task + "\u{1F}" + $0 } ?? task)
        if let label = labels[key] { shown[agent] = label; return label }
        if Self.generates, generator != nil, !pending.contains(key) {
            pending.insert(key); waiting.append((key, task, current, provider)); startNext()
        }
        return shown[agent] ?? TaskLabel.fallback(task)
    }

    /// Two at a time: a kitchen full of new chefs shouldn't start a dozen model calls at once.
    private func startNext() {
        while running < 2, !waiting.isEmpty {
            let (key, task, latest, provider) = waiting.removeFirst()
            running += 1
            Task { [weak self] in
                guard let self else { return }
                let label = await self.generator?(task, latest, provider)
                self.running -= 1
                // Without a reply (provider not connected, a timeout) the keyword label stays, not
                // saved: the next launch tries again. Within this run it isn't retried.
                if let label {
                    self.labels[key] = label
                    self.revision += 1
                    self.save()
                }
                self.startNext()
            }
        }
    }
    private func save() {
        if labels.count > 1000 { labels = Dictionary(uniqueKeysWithValues: labels.suffix(800)) }
        let snapshot = labels, url = url
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }
}
