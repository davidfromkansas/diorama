import Foundation
import DioramaCore

/// Office-only discovery never attaches, resumes, or selects a provider session.
final class AgentPlanDiscovery {
    private let history = AgentPlanHistory()
    private(set) var snapshots: [String: SessionActivitySnapshot] = [:]
    private(set) var unavailable: Set<String> = []

    func refresh(_ sources: [Session]) async {
        var seen = Set<String>()
        let sources = sources.filter { seen.insert(Self.key($0)).inserted }
        // Two reads at a time, including cancellation between batches.
        for start in stride(from: 0, to: sources.count, by: 2) {
            guard !Task.isCancelled else { return }
            let batch = Array(sources[start..<min(start + 2, sources.count)])
            let history = history
            let results = await withTaskGroup(of: (String, AgentPlanHistory.Result).self) { group in
                for source in batch { group.addTask { (Self.key(source), await history.read(source)) } }
                var results: [(String, AgentPlanHistory.Result)] = []
                for await result in group { results.append(result) }
                return results
            }
            guard !Task.isCancelled else { return }
            for (key, result) in results {
                snapshots[key] = result.snapshot
                if result.unavailable { unavailable.insert(key) } else { unavailable.remove(key) }
            }
        }
    }
    nonisolated static func key(_ session: Session) -> String { session.url?.path ?? session.id }
}
