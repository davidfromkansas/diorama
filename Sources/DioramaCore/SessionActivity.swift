import Foundation
import CryptoKit

/// Provider facts only. Payloads contain bounded summaries, never reasoning or full tool output.
public struct SessionActivityRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: String
    public var sessionID: String
    public var turnID: String?
    public var nativeID: String
    public var parentID: String?
    public var kind: String
    public var title: String
    public var status: String
    public var detail: String
    public var source: String
    public var recordedAt: Date?
    public var observedAt: Date
    public var data: WireValue
    public var bytes: Int = 0
}

/// Same snapshot contract for direct CLI, Agent SDK and Codex App Server.
public struct SessionActivitySnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var codexTurn: String? = nil
    public var currentPlanTurnID: String? = nil
    public var records: [SessionActivityRecord] = []
    public var events: [SessionActivityRecord] = []
    public var lastKnown = false
    public var truncated = false
    public var seenEventIDs: [String] = []
    public init() {}
    public var plans: [SessionActivityRecord] { records.filter { $0.kind == "proposal" } }
    public var agents: [SessionActivityRecord] { records.filter { $0.kind == "agent" || $0.kind == "job" } }
    public var agentSummary: String {
        let counts = Dictionary(grouping: agents.filter { $0.kind == "agent" }, by: \.status).mapValues(\.count)
        return counts.keys.sorted().map { "\(counts[$0]!) " + ($0.isEmpty ? "unknown" : $0) }.joined(separator: " · ")
    }
    public var steps: [SessionActivityRecord] { records.filter { $0.kind == "step" && $0.status != "deleted" } }
    public mutating func apply(_ incoming: SessionActivityRecord) {
        var record = incoming
        record.bytes = ((try? JSONEncoder().encode(record).count) ?? 0) + 128
        if let previous = records.first(where: { $0.id == record.id }), previous.status == record.status,
           previous.detail == record.detail, previous.title == record.title, previous.data == record.data { return }
        // An older historical import must not replace an explicitly newer provider observation.
        if let prior = records.first(where: { $0.id == record.id })?.recordedAt, let time = record.recordedAt, time < prior { return }
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.append(record) }
        var event = record
        event.id = record.id + ":revision:" + UUID().uuidString
        events.append(event)
        lastKnown = false
        if events.count > 10_000 { events.removeFirst(events.count - 10_000); truncated = true }
        if records.count > 2000 { records.removeFirst(records.count - 2000); truncated = true }
        var retained = records.reduce(0) { $0 + $1.bytes } + events.reduce(0) { $0 + $1.bytes }
        while retained > 24 * 1024 * 1024 {
            if !events.isEmpty { retained -= events.removeFirst().bytes }
            else if !records.isEmpty { retained -= records.removeFirst().bytes }
            else { break }
            truncated = true
        }
    }
    public mutating func bound(eventLimit: Int = 10_000, byteLimit: Int = 25 * 1024 * 1024) {
        if events.count > eventLimit { events.removeFirst(events.count - eventLimit); truncated = true }
        // Current state is the replay baseline; keep a bounded recent set if even it exceeds the budget.
        if records.count > 2000 { records.removeFirst(records.count - 2000); truncated = true }
        while (try? JSONEncoder().encode(self).count) ?? 0 > byteLimit {
            if !events.isEmpty { events.removeFirst(max(1, events.count / 4)) }
            else if !records.isEmpty { records.removeFirst(max(1, records.count / 4)) }
            else { break }
            truncated = true
        }
    }
}

public enum SessionActivityReducer {
    private static func bounded(_ value: WireValue, depth: Int = 0) -> WireValue {
        guard depth < 6 else { return .string("Summary depth limit") }
        switch value {
        case .string(let s): return .string(String(s.prefix(4000)))
        case .array(let a): return .array(a.prefix(40).map { bounded($0, depth: depth + 1) })
        case .object(let o): return .object(Dictionary(uniqueKeysWithValues: o.keys.sorted().prefix(40).map { ($0, bounded(o[$0]!, depth: depth + 1)) }))
        default: return value
        }
    }
    public static func records(_ event: WireValue, provider: Provider, sessionID: String, now: Date = Date()) -> [SessionActivityRecord] {
        let method = event["method"].string ?? "", p = event["params"]
        let turn = p["turnId"].string
        let owner = p["parentID"].string
        func record(_ kind: String, _ id: String, _ title: String, status: String = "unknown", detail: String = "", parent: String? = nil, data: WireValue = .null, time: Date? = nil) -> SessionActivityRecord {
            .init(id: provider.rawValue + ":" + sessionID + ":" + kind + ":" + (provider == .codex && kind == "tool" ? (turn ?? "unknown") + ":" : "") + (kind == "step" || kind == "checklist" ? (parent ?? owner).map { String($0.utf8.count) + ":" + $0 + ":" } ?? "" : "") + id, provider: provider.rawValue, sessionID: sessionID,
                  turnID: turn, nativeID: id, parentID: parent ?? owner, kind: kind, title: String(title.prefix(500)), status: status,
                  detail: String(detail.prefix(kind == "proposal" ? 65536 : 4000)), source: provider == .claude ? "Claude structured event" : "Codex App Server",
                  recordedAt: time ?? ActivityParser.date(p["timestamp"].string), observedAt: now, data: bounded(data))
        }
        if method == "diorama/claudeActivity" {
            let e = p["event"], type = e["type"].string ?? "", sub = e["subtype"].string ?? ""
            let time = ActivityParser.date(e["timestamp"].string)
            let parent = e["parent_tool_use_id"].string
            var out: [SessionActivityRecord] = []
            if type == "assistant" {
                for b in e["message"]["content"].array where b["type"].string == "tool_use" {
                    let name = b["name"].string ?? "Tool", id = b["id"].string ?? UUID().uuidString, args = b["input"]
                    if name == "ExitPlanMode", let plan = args["plan"].string {
                        out.append(record("proposal", id + ":plan", "Proposed plan", status: "proposed", detail: plan, parent: parent, time: time))
                    }
                    out.append(record("tool", id, name, status: "running", detail: args["description"].string ?? args["command"].string ?? args["file_path"].string ?? "", parent: parent, data: ["TaskCreate", "TaskUpdate", "TodoWrite", "ExitPlanMode"].contains(name) ? .object(["input": args]) : .null, time: time))
                }
                return out
            }
            if type == "user" {
                let r = e["tool_use_result"]
                if let id = r["task"]["id"].string {
                    out.append(record("step", id, r["task"]["subject"].string ?? "Step", status: r["task"]["status"].string ?? "pending", parent: parent, time: time))
                } else if let id = r["taskId"].string, let status = r["statusChange"]["to"].string {
                    out.append(record("step", id, "", status: status, parent: parent, time: time))
                }
                for b in e["message"]["content"].array where b["type"].string == "tool_result" {
                    guard let id = b["tool_use_id"].string else { continue }
                    out.append(record("tool", id, "", status: b["is_error"].bool ? "failed" : "completed", parent: parent, time: time))
                }
                return out
            }
            if type == "system", sub.hasPrefix("task_"), let id = e["task_id"].string {
                let kind = e["task_type"].string == "local_agent" || e["subagent_type"].string != nil ? "agent" : "job"
                let status = sub == "task_notification" ? (e["status"].string ?? "unknown") : sub == "task_started" ? "running" : ""
                return [record(kind, id, e["description"].string ?? "", status: status,
                               detail: e["prompt"].string ?? e["summary"].string ?? "", parent: e["parent_tool_use_id"].string ?? sessionID,
                               data: .object(["usage": e["usage"], "lastTool": e["last_tool_name"], "role": e["subagent_type"], "delegationID": e["tool_use_id"]]), time: time)]
            }
            if type == "system", sub == "init" {
                return [record("session", "configuration", "Session configuration", status: "connected", data: .object(["model": e["model"], "permissionMode": e["permissionMode"], "version": e["claude_code_version"]]), time: time)]
            }
            if type == "system", ["status", "compact_boundary"].contains(sub) {
                return [record("state", e["uuid"].string ?? UUID().uuidString, sub == "compact_boundary" ? "Context compacted" : "Session state", status: e["status"].string ?? "reported", time: time)]
            }
            if type == "rate_limit_event" {
                return [record("limits", "current", "Rate limits", status: "reported", data: e["rate_limit_info"], time: time)]
            }
            if type == "result" {
                return [record("usage", turn ?? e["uuid"].string ?? UUID().uuidString, "Turn usage", status: "reported",
                               data: .object(["usage": e["usage"], "modelUsage": e["modelUsage"], "duration_ms": e["duration_ms"]]), time: time)]
            }
            return []
        }
        if method == "turn/plan/updated" {
            let hash = SHA256.hash(data: (try? JSONEncoder().encode(p["plan"])) ?? Data()).map { String(format: "%02x", $0) }.joined()
            return [record("checklist", turn ?? "unknown", "Execution checklist revised", status: "reported", data: p["plan"])] + p["plan"].array.enumerated().map { index, step in
                // Position is scoped to this revision; never claimed as a stable milestone identity.
                record("step", (turn ?? "unknown") + ":" + hash + ":" + String(index), step["step"].string ?? "Step", status: step["status"].string ?? "unknown")
            }
        }
        if method == "item/plan/delta" { return [record("proposal", p["itemId"].string ?? "unknown", "Proposed plan", status: "draft", detail: p["delta"].string ?? "")] }
        if ["item/started", "item/completed"].contains(method) {
            let i = p["item"], type = i["type"].string ?? "", id = i["id"].string ?? "unknown"
            if type == "plan" { return [record("proposal", id, "Proposed plan", status: method == "item/completed" ? "proposed" : "draft", detail: i["text"].string ?? "")] }
            if type.lowercased().contains("collab") {
                let states = i["agentsStates"].object.isEmpty ? i["agentsStatus"].object : i["agentsStates"].object
                let children = Set(i["receiverThreadIds"].array.compactMap(\.string) + [i["receiverThreadId"].string, i["newThreadId"].string].compactMap { $0 } + Array(states.keys))
                return children.map { child in
                    record("agent", child, states[child]?["agentNickname"].string ?? "Subagent", status: states[child]?["status"].string ?? i["agentStatus"].string ?? i["agentStatus"]["status"].string ?? "unknown", detail: i["prompt"].string ?? "", parent: i["senderThreadId"].string ?? sessionID)
                }
            }
            if type == "subAgentActivity", let child = i["agentThreadId"].string ?? i["agentId"].string ?? i["threadId"].string {
                return [record("agent", child, i["agentNickname"].string ?? "Subagent", status: i["status"].string ?? "unknown", detail: i["message"].string ?? "", parent: i["parentThreadId"].string ?? sessionID)]
            }
            if type == "contextCompaction" { return [record("state", id, "Context compaction", status: method == "item/completed" ? "completed" : "running")] }
            if ["commandExecution", "mcpToolCall", "fileChange", "webSearch", "dynamicToolCall"].contains(type) {
                return [record("tool", id, i["tool"].string ?? type, status: method == "item/started" ? "running" : ToolResult(item: i)?.status ?? "Reported", detail: i["command"].string ?? "", data: .object(["nativeItem": .bool(true), "durationMs": i["durationMs"], "exitCode": i["exitCode"], "files": .array(i["changes"].array.map { .object(["path": $0["path"], "kind": $0["kind"]]) })]))]
            }
        }
        if method == "thread/tokenUsage/updated" { return [record("usage", turn ?? "thread", "Reported token usage", status: "reported", data: p["tokenUsage"])] }
        if method == "turn/started" || method == "turn/completed" { return [record("turn", p["turn"]["id"].string ?? turn ?? "unknown", "Turn", status: method == "turn/started" ? "running" : p["turn"]["status"].string ?? "unknown")] }
        if method.contains("requestApproval") || method == "item/tool/requestUserInput" {
            return [record("request", event["id"].key, method.contains("requestApproval") ? "Awaiting approval" : "Waiting for input", status: "pending", detail: p["reason"].string ?? "")]
        }
        if method == "serverRequest/resolved" { return [record("request", p["requestId"].key, "Request resolved", status: "resolved")] }
        return []
    }

    public static func ingest(_ event: WireValue, provider: Provider, sessionID: String, into snapshot: inout SessionActivitySnapshot) {
        var event = event
        let method = event["method"].string
        if let uuid = event["params"]["event"]["uuid"].string {
            let identity = provider.rawValue + ":" + sessionID + ":" + uuid
            if snapshot.seenEventIDs.contains(identity) { return }
            snapshot.seenEventIDs.append(identity)
            if snapshot.seenEventIDs.count > 10_000 { snapshot.seenEventIDs.removeFirst() }
        }
        let params = event["params"], claude = params["event"]
        if method == "turn/started" || method == "turn/completed" || provider == .claude,
           let turn = params["turnId"].string ?? params["turn"]["id"].string { snapshot.currentPlanTurnID = turn }
        if provider == .claude, claude["type"].string == "user", claude["tool_use_result"] == .null,
           !claude["message"]["content"].array.contains(where: { $0["type"].string == "tool_result" }),
           let id = claude["uuid"].string { snapshot.currentPlanTurnID = id }
        if provider == .claude, params["turnId"] == .null, let turn = snapshot.currentPlanTurnID {
            var object = event.object; var p = params.object; p["turnId"] = .string(turn); object["params"] = .object(p); event = .object(object)
        }
        if method == "turn/plan/updated" {
            // Whole checklist revisions replace the current checklist, history stays in events.
            let owner = event["params"]["parentID"].string
            let prior = snapshot.records.filter { $0.kind == "checklist" && $0.provider == provider.rawValue && $0.sessionID == sessionID && $0.parentID == owner }
                .max { ($0.recordedAt ?? $0.observedAt) < ($1.recordedAt ?? $1.observedAt) }
            if let prior, let previousTime = prior.recordedAt, let incomingTime = ActivityParser.date(event["params"]["timestamp"].string), incomingTime < previousTime { return }
            if let prior, prior.turnID == event["params"]["turnId"].string, prior.data == bounded(event["params"]["plan"]) { return }
            snapshot.records.removeAll { $0.kind == "step" && $0.provider == provider.rawValue && $0.sessionID == sessionID && $0.parentID == owner }
        }
        if method == "diorama/claudeActivity", event["params"]["event"]["type"].string == "user" {
            let e = event["params"]["event"]
            for block in e["message"]["content"].array where block["type"].string == "tool_result" && !block["is_error"].bool {
                guard let tool = snapshot.records.first(where: { $0.kind == "tool" && $0.provider == provider.rawValue && $0.sessionID == sessionID && $0.nativeID == block["tool_use_id"].string }) else { continue }
                let args = tool.data["input"]
                if tool.title == "TaskUpdate", let id = args["taskId"].string,
                   var step = snapshot.records.first(where: { $0.kind == "step" && $0.provider == provider.rawValue && $0.sessionID == sessionID && $0.parentID == tool.parentID && $0.nativeID == id }) {
                    if let title = args["subject"].string { step.title = title }
                    if let status = args["status"].string { step.status = status }
                    if let description = args["description"].string { step.detail = String(description.prefix(4000)) }
                    step.recordedAt = ActivityParser.date(e["timestamp"].string); step.observedAt = Date(); snapshot.apply(step)
                }
                if tool.title == "TodoWrite" {
                    let plan = args["todos"].array.map { WireValue.object(["step": $0["content"], "status": $0["status"]]) }
                    ingest(.object(["method": .string("turn/plan/updated"), "params": .object(["turnId": event["params"]["turnId"], "plan": .array(plan), "parentID": tool.parentID.map(WireValue.string) ?? .null, "timestamp": e["timestamp"]])]), provider: provider, sessionID: sessionID, into: &snapshot)
                }
            }
        }
        var reported = records(event, provider: provider, sessionID: sessionID)
        if method == "diorama/claudeActivity", event["params"]["event"]["type"].string == "user" {
            let e = event["params"]["event"]
            let results = e["message"]["content"].array.filter { $0["type"].string == "tool_result" }
            let calls = results.compactMap { block -> SessionActivityRecord? in
                guard !block["is_error"].bool else { return nil }
                return snapshot.records.first { $0.kind == "tool" && $0.provider == provider.rawValue && $0.sessionID == sessionID && $0.nativeID == block["tool_use_id"].string }
            }
            if !results.isEmpty {
                reported.removeAll { $0.kind == "step" }
                for tool in calls where tool.title == "TaskCreate" {
                    if let id = e["tool_use_result"]["task"]["id"].string {
                        let args = tool.data["input"], task = e["tool_use_result"]["task"]
                        var step = tool
                        step.kind = "step"; step.nativeID = id
                        step.id = provider.rawValue + ":" + sessionID + ":step:" + (tool.parentID.map { String($0.utf8.count) + ":" + $0 + ":" } ?? "") + id
                        step.title = task["subject"].string ?? args["subject"].string ?? "Step"
                        step.detail = args["description"].string ?? ""
                        step.status = task["status"].string ?? "pending"; step.data = .null
                        step.recordedAt = ActivityParser.date(e["timestamp"].string)
                        reported.append(step)
                    }
                }
                for tool in calls where tool.title == "ExitPlanMode" {
                    if let text = e["tool_use_result"]["plan"].string {
                        var plan = tool; plan.kind = "proposal"; plan.nativeID += ":plan"
                        plan.id = provider.rawValue + ":" + sessionID + ":proposal:" + plan.nativeID
                        plan.title = "Proposed plan"; plan.detail = String(text.prefix(65536)); plan.status = "proposed"; plan.data = .null
                        plan.recordedAt = ActivityParser.date(e["timestamp"].string); reported.append(plan)
                    }
                }
            }
        }
        if reported.contains(where: { $0.detail.count >= 65536 || $0.title.count >= 500 }) ||
            event["params"]["event"]["message"]["content"].array.contains(where: { $0["input"]["todos"].array.count > 40 }) { snapshot.truncated = true }
        for var r in reported {
            // Claude progress/notification may omit the task type; preserve the original classification.
            if r.kind == "job", let old = snapshot.records.first(where: { $0.nativeID == r.nativeID && $0.kind == "agent" }) { r.kind = "agent"; r.id = old.id }
            if let old = snapshot.records.first(where: { $0.id == r.id }) {
                if r.title.isEmpty { r.title = old.title }
                if r.status.isEmpty { r.status = old.status }
                if r.detail.isEmpty && r.kind != "proposal" { r.detail = old.detail }
                if r.parentID == nil { r.parentID = old.parentID }
                if r.data == .null { r.data = old.data }
                else if !old.data.object.isEmpty {
                    r.data = .object(old.data.object.merging(r.data.object.filter { $0.value != .null }) { _, new in new })
                }
                if method == "item/plan/delta", old.status == "proposed" { continue }
                if method == "item/plan/delta" { r.detail = String((old.detail + r.detail).prefix(65536)) }
            }
            snapshot.apply(r)
        }
    }
}

/// Per-provider identity prevents collisions; atomic snapshots carry the retained event feed and baseline.
public actor SessionActivityStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public nonisolated static func file(directory: URL, provider: Provider, id: String) -> URL {
        let safe = Data((provider.rawValue + ":" + id).utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe + ".json")
    }
    public nonisolated static func read(directory: URL, provider: Provider, id: String) -> SessionActivitySnapshot {
        guard let data = try? Data(contentsOf: file(directory: directory, provider: provider, id: id)), data.count <= 25 * 1024 * 1024,
              var value = try? JSONDecoder().decode(SessionActivitySnapshot.self, from: data), value.version == 1 else { return .init() }
        value.lastKnown = true
        return value
    }
    public func save(_ snapshot: SessionActivitySnapshot, provider: Provider, id: String, members: [ActivitySessionIdentity] = []) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var snapshot = snapshot
        snapshot.bound()
        let current = ActivitySessionIdentity(provider: provider, id: id)
        let identities = Array(Set(members + [current])).sorted { $0.key < $1.key }
        var snapshots = identities.map { identity in
            identity == current ? snapshot : Self.read(directory: directory, provider: identity.provider, id: identity.id)
        }
        ConversationActivityBudget.bound(&snapshots)
        for (identity, retained) in zip(identities, snapshots) {
            try JSONEncoder().encode(retained).write(to: Self.file(directory: directory, provider: identity.provider, id: identity.id), options: .atomic)
        }
    }
}

public struct ActivitySessionIdentity: Hashable, Sendable {
    public var provider: Provider
    public var id: String
    public init(provider: Provider, id: String) { self.provider = provider; self.id = id }
    public var key: String { provider.rawValue + ":" + id }
}

/// One budget across provider segments. Snapshots retain current state before event pruning.
public enum ConversationActivityBudget {
    public static func bound(_ snapshots: inout [SessionActivitySnapshot], eventLimit: Int = 10_000, byteLimit: Int = 25 * 1024 * 1024) {
        let ordered = snapshots.enumerated().flatMap { index, snapshot in
            snapshot.events.map { (index, $0.id, $0.observedAt) }
        }.sorted { $0.2 < $1.2 }
        let excess = max(0, ordered.count - eventLimit)
        let removed = Dictionary(grouping: ordered.prefix(excess), by: { $0.0 })
        for (index, entries) in removed {
            let ids = Set(entries.map { $0.1 })
            snapshots[index].events.removeAll { ids.contains($0.id) }; snapshots[index].truncated = true
        }
        func size() -> Int { snapshots.reduce(0) { $0 + ((try? JSONEncoder().encode($1).count) ?? 0) } }
        while size() > byteLimit {
            if let index = snapshots.indices.filter({ !snapshots[$0].events.isEmpty }).min(by: {
                snapshots[$0].events[0].observedAt < snapshots[$1].events[0].observedAt
            }) {
                snapshots[index].events.removeFirst(max(1, snapshots[index].events.count / 8))
                snapshots[index].truncated = true
            } else if let index = snapshots.indices.filter({ !snapshots[$0].records.isEmpty }).min(by: {
                snapshots[$0].records[0].observedAt < snapshots[$1].records[0].observedAt
            }) {
                snapshots[index].records.removeFirst(); snapshots[index].truncated = true
            } else if let index = snapshots.indices.first(where: { !snapshots[$0].seenEventIDs.isEmpty }) {
                snapshots[index].seenEventIDs.removeAll(); snapshots[index].truncated = true
            } else { break }
        }
    }
}
