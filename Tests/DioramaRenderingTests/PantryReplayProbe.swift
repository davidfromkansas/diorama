import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

/// Opt-in replay of real provider sessions through Diorama's own pipeline, one line at a time:
/// the session file → `ExternalSessionObserver` → `WorkspaceAgentPresentation.agents` →
/// `KitchenLayout.work` (the chef's station) and `PantryCarry.item` (what it carries).
///     DIORAMA_PANTRY_REPLAY=/path/rollout.jsonl:/path/claude.jsonl swift test --filter PantryReplayProbe
@MainActor struct PantryReplayProbe {
    @Test func replay() async throws {
        guard let paths = ProcessInfo.processInfo.environment["DIORAMA_PANTRY_REPLAY"] else { return }
        var report = ""
        for path in paths.split(separator: ":").map(String.init) {
            let provider: Provider = path.contains("/.claude/") ? .claude : .codex
            let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            report += "\n=== \(provider.rawValue) · \((path as NSString).lastPathComponent) · \(lines.count) lines\n"
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("replay-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent((path as NSString).lastPathComponent)
            var seen = Set<String>(), pantry = false, carried: PantryCarry.Item?
            for count in 1...lines.count {
                // Only re-derive at lines that report a tool call.
                let line = String(lines[count - 1])
                guard line.contains("tool_use") || line.contains("function_call") || line.contains("custom_tool_call") || line.contains("mcp_tool_call") || count == lines.count else { continue }
                try lines.prefix(count).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
                let id = (path as NSString).lastPathComponent.replacingOccurrences(of: ".jsonl", with: "")
                let session = Session(id: provider.rawValue + ":" + id, provider: provider, url: file, sessionID: id, title: "replay",
                                      project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
                let observation = await ExternalSessionObserver().read(session, limit: 2000, hookDirectory: nil)
                let source = WorkspaceActivitySource(provider: provider, sessionID: id, snapshot: observation.structured, task: nil,
                                                     fallbackStatus: count == lines.count ? observation.activity.state.rawValue : "working",
                                                     observation: observation, now: observation.activity.events.last?.recordedAt ?? Date())
                guard let agent = WorkspaceAgentPresentation.agents(title: "replay", sources: [source]).first(where: \.isMain) else { continue }
                let work = KitchenLayout.work(for: agent)
                let item = PantryCarry.item(for: agent)
                let key = "\(agent.latestTool)|\(work.area)|\(String(describing: item))|\(agent.turnWork.resources)"
                guard seen.insert(key).inserted else { continue }
                if work.area == "pantry" { pantry = true }
                if let item { carried = item }
                report += "line \(count): tool=\(agent.latestTool) detail=\(agent.latestToolDetail.prefix(90)) → station=\(work.area)"
                    + " resources=\(agent.turnWork.resources) carry=\(item.map { "\($0.kind.rawValue):\($0.name)" } ?? "-")\n"
            }
            report += "RESULT: visited pantry=\(pantry) · carries=\(carried.map { "\($0.kind.rawValue) “\($0.name)”" } ?? "nothing")\n"
        }
        print(report)
        try report.write(toFile: "/tmp/diorama-pantry-replay.txt", atomically: true, encoding: .utf8)
    }
}
