import AppKit
import Foundation
import Testing
@testable import DioramaCore
@testable import DioramaApp

/// Opt-in: replays a saved Codex transcript through the kitchen's pacing and prints where its chef
/// goes and when. DIORAMA_REPLAY=/path/to/rollout.jsonl swift test --filter KitchenReplayProbe
@MainActor struct KitchenReplayProbe {
    @Test func replay() async throws {
        guard let path = ProcessInfo.processInfo.environment["DIORAMA_REPLAY"] else { return }
        let id = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.components(separatedBy: "-").suffix(5).joined(separator: "-")
        let provider: Provider = path.contains("/.claude/") ? .claude : .codex
        let session = Session(id: provider.rawValue + ":" + id, provider: provider, url: URL(fileURLWithPath: path), sessionID: id, title: "p", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let events = (await ActivityLibrary().scan([session])[session.id] ?? ActivitySummary()).events
        // What the agent reported and did, as the kitchen sees it.
        let history = await SessionActivityHistory.read(session)
        let plan = AgentPlan.reported(in: history, provider: provider.rawValue, sessionID: id)
        print("PROBE checklist:", plan.hasTasks ? plan.taskProgress + " " + plan.checklist.map { "[\($0.status)] \($0.title)" }.joined(separator: " | ") : "none")
        let work = TurnWork.from(events)
        print("PROBE turn: files", work.files.map { ($0 as NSString).lastPathComponent }, "commands", work.commands, "failed", work.failedCommands, "tests", work.tests.map { "\($0.command)=\($0.outcome)" }, "fetched", work.resources)
        for entry in AgentActivityFeed.entries(from: events) { print("PROBE feed", entry.title, entry.outcome.map { "· \($0)" } ?? "") }
        guard let start = events.first(where: { $0.kind == "started" })?.time, let end = events.last(where: { $0.kind == "finished" })?.time else { print("PROBE no turn"); return }
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        view.apply(agents: [], scope: "p", active: false, reducedMotion: false, now: 0)
        func state(at t: Date) -> SpatialAgent {
            let seen = events.filter { $0.time <= t }
            let done = seen.contains { $0.kind == "finished" }
            var value = WorkspaceAgent(id: "main", name: "Replay", provider: provider.rawValue, task: "site", action: "", status: done ? .done : .working, reportedStatus: done ? "Last turn finished" : "Working", freshness: .live)
            let tools = seen.filter { $0.kind == "toolStarted" }
            // As in the app: plan and checklist updates don't change what the chef is doing.
            let working = tools.last { KitchenActivity.classify(tool: $0.tool ?? "", detail: $0.detail ?? "") != .planning } ?? tools.last
            value.latestTool = working?.tool ?? ""; value.latestToolDetail = KitchenActivity.withoutHeredocs(working?.detail ?? "")
            value.turnHasEdits = tools.contains { KitchenActivity.isEditing(tool: $0.tool ?? "", detail: $0.detail ?? "") }
            value.turnWork = TurnWork.from(seen)
            value.completionKey = provider.rawValue + ":" + id + ":turn"
            value.lastCommentaryAt = seen.last { $0.kind == "commentary" }?.time
            value.lastToolAt = seen.last { $0.kind == "toolStarted" }?.time
            return SpatialAgent(projectID: "p", conversationID: "c", value: value)
        }
        var lastArea = "", lastStation = "", t = 0.0
        let total = end.timeIntervalSince(start) + 25
        var nextApply = 0.0
        while t < total {
            if t >= nextApply {
                // The app refreshes agent state about once a second.
                view.apply(agents: [state(at: start.addingTimeInterval(t))], scope: "p", active: false, reducedMotion: false, now: t)
                nextApply += 1
            }
            for chef in view.chefs.values { chef.update(1 / 30) }
            t += 1 / 30
            guard let director = view.chefs.values.first?.director else { continue }
            let want = director.intent?.station?.area ?? "-"
            let at = director.station?.area ?? "walking"
            if want != lastArea {
                let tag = ChefTagContent.make(view.chefs.keys.first.flatMap { _ in state(at: start.addingTimeInterval(t)) } ?? state(at: start), review: nil, now: start.addingTimeInterval(t))
                print(String(format: "PROBE %6.1fs heading to %@ (%@) · tag icon %@", t, want, director.intent?.loop ?? "", tag.icon.rawValue)); lastArea = want
            }
            if at != lastStation && at != "walking" { print(String(format: "PROBE %6.1fs   arrived %@ · clip %@", t, at, director.clip.name)); lastStation = at }
        }
    }
}
