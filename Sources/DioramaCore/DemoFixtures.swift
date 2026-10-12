import Foundation

/// Made-up conversations for the development demo recording (`--record-demo`); nothing else
/// creates sessions or transcript lines by hand.
extension Session {
    public static func demo(id: String, provider: Provider, title: String, folder: String, modified: Date) -> Session {
        var session = Session(id: id, provider: provider, url: nil, sessionID: id, title: title, project: folder,
                              modified: modified, bytes: 0, archived: false, parentID: nil)
        session.classification = .conversation
        session.titleSource = .provider
        return session
    }
}

extension Entry {
    /// A message ("You" or "Assistant").
    public static func demo(_ id: String, _ kind: String, _ text: String) -> Entry {
        Entry(id: id, kind: kind, text: text, timestamp: nil)
    }
    /// A tool call as Codex reports one, e.g. `["type": "commandExecution", "command": "swift test"]`.
    public static func demoTool(_ id: String, _ item: [String: String]) -> Entry? {
        guard let tool = ToolResult(item: .object(item.mapValues { .string($0) })) else { return nil }
        var entry = Entry(id: id, kind: "Tool activity", text: tool.title, timestamp: nil, tool: tool)
        entry.codex = .tool(tool)
        return entry
    }
}

extension AgentPlan {
    /// A checklist kept this turn: each step's title and status ("completed", "in_progress", "pending").
    public static func demo(_ steps: [(String, String)], provider: Provider, sessionID: String, at time: Date) -> AgentPlan {
        let records = steps.enumerated().map { index, step in
            SessionActivityRecord(id: sessionID + ".step\(index)", provider: provider.rawValue, sessionID: sessionID, nativeID: "step\(index)",
                                  kind: "step", title: step.0, status: step.1, detail: "", source: "demo", recordedAt: time, observedAt: time, data: .null)
        }
        return AgentPlan(checklist: records, taskUpdatedAt: time, tasksPreviousTurn: false, proposalPreviousTurn: false,
                         updatedAt: time, previousTurn: false, truncated: false)
    }
}
