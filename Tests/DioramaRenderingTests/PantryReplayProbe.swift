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
            // The stations in order, with what's carried away from prep and the pantry.
            var sequence: [String] = [], leaving: String?
            // Brief work still owes its station (KitchenSceneSurface's pacing): the pantry for each
            // fetch, cooking for new edits (before tasting), tasting/stove for each test run.
            var filesSeen = 0, testsSeen = 0, fetchedSeen = 0
            func visit(_ area: String, carry: String?) {
                guard sequence.last.map({ !$0.hasPrefix(area) }) ?? true else { return }
                if let leaving { sequence[sequence.count - 1] += " (carries \(leaving))" }
                sequence.append(area); leaving = carry
            }
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
                if agent.status == .working {
                    var owed: [String] = []
                    if agent.turnWork.resources.count > fetchedSeen { owed.append("pantry") }
                    if agent.turnWork.files.count > filesSeen { owed.append("cooking") }
                    if agent.turnWork.tests.count > testsSeen {
                        let steps = agent.turnWork.tests.last.map { KitchenActivity.stations(command: $0.command) } ?? []
                        let areas = steps.compactMap { step -> String? in switch step { case .testing, .checking: "tasting"; case .commands: "stove"; default: nil } }
                        owed += areas.isEmpty ? ["tasting"] : areas
                    }
                    for area in owed where area != work.area {
                        visit(area + " (owed)", carry: area == "pantry" ? item.map { "\($0.kind.rawValue) “\($0.name)”" } : nil)
                    }
                    filesSeen = agent.turnWork.files.count; testsSeen = agent.turnWork.tests.count; fetchedSeen = agent.turnWork.resources.count
                }
                let key = "\(agent.latestTool)|\(work.area)|\(String(describing: item))|\(agent.turnWork.resources)"
                guard seen.insert(key).inserted else { continue }
                if work.area == "pantry" { pantry = true }
                let area = work.area ?? "rest"
                let carry = area == "prep" ? "plate “\(PantryCarry.planItem(for: agent).name)”"
                    : area == "pantry" ? item.map { "\($0.kind.rawValue) “\($0.name)”" } : nil
                visit(area, carry: carry)
                if sequence.last?.hasPrefix(area) == true, carry != nil { leaving = carry }
                if let item { carried = item }
                report += "line \(count): tool=\(agent.latestTool) detail=\(agent.latestToolDetail.prefix(90)) → station=\(work.area)"
                    + " resources=\(agent.turnWork.resources) carry=\(item.map { "\($0.kind.rawValue):\($0.name)" } ?? "-")"
                    + (work.area == "prep" ? " plate=“\(PantryCarry.planItem(for: agent).name)”" : "") + "\n"
            }
            report += "SEQUENCE: " + sequence.joined(separator: " → ") + "\n"
            report += "RESULT: visited pantry=\(pantry) · carries=\(carried.map { "\($0.kind.rawValue) “\($0.name)”" } ?? "nothing")\n"
        }
        print(report)
        try report.write(toFile: "/tmp/diorama-pantry-replay.txt", atomically: true, encoding: .utf8)
    }
}
