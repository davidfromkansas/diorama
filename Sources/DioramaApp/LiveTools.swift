import DioramaCore
import Foundation

/// Something a chef reached for beyond the kitchen's own stations: an MCP server or app (an icon
/// on the live bar), or a skill (the bar's flip slot).
struct LiveResource: Hashable, Identifiable {
    enum Kind: Hashable { case server, skill }
    let id: String
    let name: String
    let kind: Kind
    /// The plugin that brought it, when it came from one.
    var plugin: String? = nil
    /// The company mark for it, when it's a known service.
    var brand: BrandMark.Mark? { kind == .server ? BrandMark.match(id.replacingOccurrences(of: "server:", with: "")) ?? plugin.flatMap(BrandMark.match) : nil }
}

enum LiveResources {
    /// The resource a tool call uses, if any: `mcp__server__tool` (Claude, and Codex's MCP calls),
    /// a plugin's server (`mcp__plugin_<plugin>_<server>__tool`), or a skill (the Skill tool, or
    /// reading a `SKILL.md`). Built-in tools (shell, edits, search) are the kitchen's stations.
    static func resource(tool: String, detail: String) -> LiveResource? {
        if let skill = KitchenActivity.skillName(detail) { return LiveResource(id: "skill:" + skill, name: skill, kind: .skill) }
        if tool.lowercased() == "skill" {
            let name = detail.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            return name.isEmpty ? nil : LiveResource(id: "skill:" + name, name: name, kind: .skill)
        }
        guard tool.hasPrefix("mcp__") else { return nil }
        let parts = tool.dropFirst(5).components(separatedBy: "__")
        guard var server = parts.first, !server.isEmpty else { return nil }
        // Connectors with opaque ids (claude.ai's UUID servers) can't be named or branded.
        if server.count >= 32, server.filter({ $0 == "-" }).count >= 4 { return nil }
        var plugin: String?
        if server.hasPrefix("plugin_") {
            let rest = server.dropFirst(7).split(separator: "_", maxSplits: 1).map(String.init)
            plugin = rest.first
            server = rest.count > 1 ? rest[1] : rest.first ?? server
        }
        if server.hasPrefix("claude_ai_") { server = String(server.dropFirst(10)) }
        let key = server.lowercased()
        return LiveResource(id: "server:" + key, name: BrandMark.match(key)?.title ?? title(server), kind: .server, plugin: plugin)
    }
    /// "google-calendar" → "Google Calendar", "computer_use" → "Computer Use".
    static func title(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

extension BrandMark {
    /// The mark for a service name, by slug, alias, or a slug it starts with ("githubcopilot").
    static func match(_ name: String) -> Mark? {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !key.isEmpty else { return nil }
        if let mark = marks[key] { return mark }
        if let slug = aliases[key], let mark = marks[slug] { return mark }
        return marks.values.filter { $0.slug.count >= 4 && key.hasPrefix($0.slug) }.max { $0.slug.count < $1.slug.count }
    }
}

/// The live bar's state: up to five servers in the order chefs last reached for them, the latest
/// skill, and a caption naming who picked up what. Calm by design: at most one reshuffle every
/// 1.5 s (picks inside it are applied together), a tool used again within 20 s pulses where it
/// is instead of jumping, and nothing moves while the pointer is over the bar.
@MainActor @Observable final class LiveToolsModel {
    struct Slot: Identifiable, Equatable {
        let resource: LiveResource
        /// Chefs using it right now.
        var users: [String] = []
        var lastUsed: Date
        /// Bumped when it's used again in place, for a pulse.
        var pulses = 0
        var id: String { resource.id }
    }
    struct Pick: Equatable { let resource: LiveResource; let chef: String; let at: Date; var agentID = "" }
    /// A spark from the chef who picked something up to where it lands on the bar.
    struct Spark: Equatable, Identifiable { let id = UUID(); let agentID: String; let skill: Bool }
    struct Caption: Equatable, Identifiable { let id = UUID(); let chef: String; let text: String; let at: Date }

    static let capacity = 5
    static let calm: TimeInterval = 1.5
    static let stay: TimeInterval = 20

    private(set) var slots: [Slot] = []
    private(set) var skill: Pick?
    private(set) var caption: Caption?
    private(set) var sparks: [Spark] = []
    /// The pointer is over the bar: changes wait.
    var frozen = false { didSet { if !frozen { flush() } } }

    @ObservationIgnored private var pending: [Pick] = []
    @ObservationIgnored private var lastApplied = Date.distantPast
    @ObservationIgnored private var seen: [String: String] = [:]
    @ObservationIgnored private var seeded = false

    /// Reads the chefs' latest tool calls; a new call to a server or skill becomes a pick.
    func observe(_ agents: [SpatialAgent], now: Date = Date()) {
        var using: [String: [String]] = [:]
        for agent in agents {
            let value = agent.value
            guard let resource = LiveResources.resource(tool: value.latestTool, detail: value.latestToolDetail) else { seen[agent.id] = nil; continue }
            let chef = value.name
            let fresh = value.isWorking && (value.lastToolAt.map { now.timeIntervalSince($0) < 60 } ?? true)
            if fresh, resource.kind == .server { using[resource.id, default: []].append(chef) }
            let signature = resource.id + "\u{1F}" + (value.lastToolAt.map { String($0.timeIntervalSince1970) } ?? value.latestToolDetail)
            guard seen[agent.id] != signature else { continue }
            seen[agent.id] = signature
            // What was already running when the bar appeared fills it without a show.
            if !seeded || !fresh { place(resource, users: [], at: value.lastToolAt ?? now, quietly: true); continue }
            pending.append(Pick(resource: resource, chef: chef, at: now, agentID: agent.id))
        }
        seeded = true
        for index in slots.indices { slots[index].users = using[slots[index].id] ?? [] }
        flush(now: now)
    }

    /// Applies waiting picks, unless the pointer holds the bar or the last move was too recent.
    func flush(now: Date = Date()) {
        guard !frozen, !pending.isEmpty, now.timeIntervalSince(lastApplied) >= Self.calm else { return }
        let batch = pending; pending = []
        for pick in batch {
            if !pick.agentID.isEmpty { sparks.append(Spark(agentID: pick.agentID, skill: pick.resource.kind == .skill)) }
            if pick.resource.kind == .skill { skill = pick } else { place(pick.resource, users: [pick.chef], at: pick.at, quietly: false) }
        }
        if let last = batch.last {
            caption = Caption(chef: last.chef, text: last.resource.kind == .skill ? "used the \(last.resource.name) skill"
                : "called \(last.resource.name)" + (last.resource.plugin.map { " (\($0) plugin)" } ?? ""), at: now)
        }
        lastApplied = now
    }
    func landed(_ spark: Spark) { sparks.removeAll { $0.id == spark.id } }
    /// Clears a caption that has been up for a while.
    func expireCaption(now: Date = Date()) {
        if let caption, now.timeIntervalSince(caption.at) > 3.5 { self.caption = nil }
    }

    private func place(_ resource: LiveResource, users: [String], at: Date, quietly: Bool) {
        guard resource.kind == .server else { if skill == nil { skill = Pick(resource: resource, chef: "", at: at) }; return }
        if let index = slots.firstIndex(where: { $0.id == resource.id }) {
            var slot = slots[index]
            let recent = at.timeIntervalSince(slot.lastUsed) < Self.stay
            slot.lastUsed = max(slot.lastUsed, at)
            for user in users where !slot.users.contains(user) { slot.users.append(user) }
            if recent || quietly || index == 0 { if !quietly { slot.pulses += 1 }; slots[index] = slot; return }
            slots.remove(at: index); slots.insert(slot, at: 0)
        } else {
            let slot = Slot(resource: resource, users: users, lastUsed: at)
            if quietly {
                slots.append(slot); slots.sort { $0.lastUsed > $1.lastUsed }
            } else {
                slots.insert(slot, at: 0)
            }
        }
        // Over capacity, the idle one used longest ago drops into All.
        while slots.count > Self.capacity {
            if let drop = slots.indices.reversed().first(where: { slots[$0].users.isEmpty }) { slots.remove(at: drop) } else { slots.removeLast() }
        }
    }
}
