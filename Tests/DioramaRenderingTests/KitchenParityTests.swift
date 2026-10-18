import AppKit
@testable import DioramaCore
import SceneKit
import Testing
import simd
@testable import DioramaApp

/// The kitchen exactly as it was before the scene engine was shared with the office: its slots,
/// walkable floor, the station table over every agent state, the built room and a scripted run of
/// chefs. Recorded once into `Fixtures/kitchen-parity.json` (DIORAMA_RECORD_PARITY=1); any drift
/// in the kitchen fails here.
@MainActor struct KitchenParityTests {
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/kitchen-parity.json")

    private func agent(_ id: String, _ status: WorkspaceAgentStatus, tool: String = "", detail: String = "", attention: WorkspaceAttentionReason = .other,
                       edits: Bool = false, freshness: WorkspaceAgentFreshness = .live, conversation: String? = nil) -> SpatialAgent {
        var value = WorkspaceAgent(id: id, name: "Agent \(id)", provider: "Claude", task: "Task", action: "", status: status, reportedStatus: status.rawValue, freshness: freshness)
        value.latestTool = tool; value.latestToolDetail = detail; value.attentionReason = attention; value.turnHasEdits = edits
        value.completionKey = "turn-1"
        return SpatialAgent(projectID: "p", conversationID: conversation ?? "c-" + id, value: value)
    }
    private func r(_ value: Float) -> String { String(format: "%.4f", value) }
    private func r(_ value: CGFloat) -> String { String(format: "%.4f", Double(value)) }
    private func r(_ value: Double) -> String { String(format: "%.4f", value) }

    /// Every agent state the station table distinguishes.
    private var matrix: [SpatialAgent] {
        var result: [SpatialAgent] = []
        let tools: [(String, String)] = [("", ""), ("Read", ""), ("Edit", ""), ("TaskCreate", ""), ("Bash", "make"), ("Bash", "swift test"),
                                         ("Bash", "npm test && npm run build"), ("computer_use", ""), ("Skill", "pdf"), ("mcp__linear__list", "")]
        for status in [WorkspaceAgentStatus.ready, .working, .waiting, .done, .stopped, .failed, .unknown] {
            for freshness in [WorkspaceAgentFreshness.live, .recentlyObserved, .lastKnown, .ready] {
                for attention in [WorkspaceAttentionReason.other, .approval, .input] {
                    for (tool, detail) in tools {
                        for edits in [false, true] {
                            result.append(agent("m\(result.count)", status, tool: tool, detail: detail, attention: attention, edits: edits, freshness: freshness))
                        }
                    }
                }
            }
        }
        return result
    }

    private func snapshot() throws -> [String: [String]] {
        var out: [String: [String]] = [:]
        out["slots"] = KitchenLayout.chefSlots.keys.sorted().flatMap { area in
            (KitchenLayout.chefSlots[area] ?? []).map { "\($0.id) \(r($0.stand.x)) \(r($0.stand.y)) \(r($0.facing))" }
        }
        let navigation = KitchenLayout.chefNavigation
        out["navigation"] = ["\(r(navigation.min.x)) \(r(navigation.min.y)) \(r(navigation.max.x)) \(r(navigation.max.y))"]
            + navigation.obstacles.map { "\(r($0.min.x)) \(r($0.min.y)) \(r($0.max.x)) \(r($0.max.y))" }
        out["breakSpots"] = BreakRoomLayout.spots.map { "\($0.station.id) \(r($0.station.stand.x)) \(r($0.station.stand.y)) \(r($0.station.facing)) \($0.kind)" }
        out["fixed"] = [KitchenLayout.gongStrike, KitchenLayout.elevatorLanding, KitchenLayout.diningDoor].map { "\($0.id) \(r($0.stand.x)) \(r($0.stand.y)) \(r($0.facing))" }
            + ["\(r(KitchenLayout.gongCenter.x)) \(r(KitchenLayout.gongCenter.y))"]
        let reviews: [KitchenReviews.State?] = [nil, .approved, .committed, .merged, .checking, .needsFix, .shipped, .reworking, .awaiting]
        let slot = ChefStation(id: "slot", area: "x", stand: .zero, facing: 0), pickup = ChefStation(id: "pickup", area: "cooking", stand: .zero, facing: 0)
        var work: [String] = [], intents: [String] = []
        for agent in matrix {
            for review in reviews {
                let w = KitchenLayout.work(for: agent.value, review: review)
                work.append([w.area ?? "-", w.loop, w.hand?.rawValue ?? "-", w.oneShot ?? "-", "\(w.urgent)", "\(w.deliversPlate)", w.prelude ?? "-"].joined(separator: " "))
                for restored in [false, true] {
                    let i = KitchenLayout.intent(for: agent.value, at: slot, pickup: pickup, restored: restored, review: review)
                    intents.append([i.key, i.loop, i.hand?.rawValue ?? "-", i.oneShot?.id ?? "-", i.pickup?.id ?? "-", "\(i.urgent)", i.prelude ?? "-",
                                    i.strike.map { "\($0.id) \(r($0.stand.x)) \(r($0.stand.y))" } ?? "-"].joined(separator: " "))
                }
            }
        }
        // A table of distinct results and, per row, its index: the full mapping, compactly.
        func table(_ name: String, _ rows: [String]) {
            var unique: [String] = [], index: [String: Int] = [:]
            let codes = rows.map { row in index[row] ?? { unique.append(row); index[row] = unique.count - 1; return unique.count - 1 }() }
            out[name] = unique
            out[name + "Rows"] = stride(from: 0, to: codes.count, by: 200).map { codes[$0..<min(codes.count, $0 + 200)].map(String.init).joined(separator: ",") }
        }
        table("work", work); table("intents", intents)
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        out["world"] = (view.scene?.rootNode.childNodes ?? []).filter { $0.camera == nil && $0.light == nil }.map { node in
            let (low, high) = node.boundingBox
            return "\(node.name ?? "?") \(r(low.x)) \(r(low.y)) \(r(low.z)) \(r(high.x)) \(r(high.y)) \(r(high.z)) \(r(node.position.x)) \(r(node.position.z))"
        }.sorted()
        var homes: [String] = []
        for size in [CGSize(width: 1000, height: 700), CGSize(width: 650, height: 650), CGSize(width: 1500, height: 700)] {
            let fitted = DioramaSceneView(frame: CGRect(origin: .zero, size: size)); fitted.fitFloor()
            homes.append("\(Int(size.width))x\(Int(size.height)) \(r(fitted.freeCamera.homeDistance))")
        }
        out["home"] = homes
        out["run"] = try scriptedRun()
        return out
    }

    /// A kitchen driven through arrivals, work, tests, the gong and serving: where every chef is
    /// headed and standing, and what it plays, sampled each second.
    private func scriptedRun() throws -> [String] {
        _ = try ChefAssets.shared.get()
        let view = DioramaSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        view.characters = ChefCharacterModel(url: nil)
        var clock = 1000.0, lines: [String] = []
        let resting = (0..<4).map { agent("rest\($0)", .done, freshness: .lastKnown) }
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 30) {
                clock += 1 / 30
                for chef in view.chefs.values { chef.update(1 / 30) }
                view.pace(now: clock); view.updateBreakRoom(now: clock)
                view.updateManager(); view.updateGong(); view.serveDiners(now: clock)
            }
        }
        func sample(_ label: String) {
            for id in view.chefs.keys.sorted() {
                guard let chef = view.chefs[id] else { continue }
                let d = chef.director
                lines.append("\(label) \(id) \(d.intent?.station?.id ?? "-") \(d.station?.id ?? "-") \(d.clip.name) \(d.held.map(\.rawValue).sorted().joined(separator: ","))")
            }
        }
        var agents = resting + [agent("a", .working, tool: "Read"), agent("b", .working, tool: "Edit", edits: true), agent("c", .ready, freshness: .ready)]
        view.apply(agents: agents, scope: "p", active: false, reducedMotion: false, now: clock)
        step(1); sample("t1")
        agents += [agent("new", .working, tool: "Bash", detail: "make")]
        view.apply(agents: agents, scope: "p", active: false, reducedMotion: false, now: clock)
        for second in 2...12 { step(1); sample("t\(second)") }
        agents = resting + [agent("a", .working, tool: "Bash", detail: "swift test", edits: true), agent("b", .waiting, attention: .approval),
                            agent("c", .working, tool: "Skill", detail: "pdf"), agent("new", .done)]
        view.apply(agents: agents, scope: "p", active: false, reducedMotion: false, now: clock)
        for second in 13...30 { step(1); sample("t\(second)") }
        lines.append("t30 manager \(view.manager?.director.station?.id ?? "-") \(view.managerVisit?.id ?? "-") served \(view.servedSeats.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))")
        agents = resting + [agent("a", .done), agent("b", .stopped), agent("c", .failed), agent("new", .done, freshness: .lastKnown)]
        view.apply(agents: agents, scope: "p", active: false, reducedMotion: false, now: clock)
        for second in 31...45 { step(1); sample("t\(second)") }
        lines.append("manager \(view.manager?.director.station?.id ?? "-") \(view.managerVisit?.id ?? "-") served \(view.servedSeats.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))")
        return lines
    }

    @Test func kitchenMatchesItsRecordedParity() throws {
        let current = try snapshot()
        if ProcessInfo.processInfo.environment["DIORAMA_RECORD_PARITY"] == "1" {
            try FileManager.default.createDirectory(at: Self.fixture.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(current).write(to: Self.fixture)
            return
        }
        let recorded = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: Self.fixture))
        #expect(Set(recorded.keys) == Set(current.keys))
        for key in recorded.keys.sorted() {
            let old = recorded[key] ?? [], new = current[key] ?? []
            #expect(old.count == new.count, "\(key): \(old.count) recorded, \(new.count) now")
            if let index = zip(old, new).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                Issue.record("\(key)[\(index)] drifted:\n  was \(old[index])\n  now \(new[index])")
            }
        }
    }
}
