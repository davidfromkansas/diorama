import SwiftUI
import DioramaCore

/// Presentation only. Original entries remain available in Detailed mode.
enum HistoryDisplayMode: String, CaseIterable {
    case conversation = "Conversation"
    case detailed = "Detailed"
}

private struct HistoryDetailsKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var historyDetails: Bool {
        get { self[HistoryDetailsKey.self] }
        set { self[HistoryDetailsKey.self] = newValue }
    }
}

struct HistoryRow: Identifiable {
    var entries: [Entry]
    var grouped: Bool
    var id: String { entries[0].id }
    var summary: String {
        let count = entries.count
        return "Work activity · \(count) \(count == 1 ? "record" : "records")"
    }
}

enum ConversationHistory {
    static func isUsage(_ entry: Entry) -> Bool {
        entry.codex?.category.hasPrefix("usage") == true || ["usage", "sessionUsage"].contains(entry.claude?.category ?? "")
    }
    static func needsAttention(_ entry: Entry) -> Bool {
        let status = (entry.tool?.status ?? entry.claude?.status ?? entry.codex?.status ?? "").lowercased()
        return entry.tool?.requestsInput == true ||
            ["failed", "error", "denied", "rejected", "waiting for input", "awaiting approval", "blocked", "interrupted"].contains(status) ||
            (entry.tool?.item["exitCode"].number.map { $0 != 0 } ?? false)
    }
    static func canGroup(_ entry: Entry) -> Bool {
        guard entry.category == .activity, !needsAttention(entry), entry.image == nil,
              entry.kind != "Proposed plan", entry.kind != "Provider switch" else { return false }
        let name = entry.tool?.item["name"].string ?? entry.tool?.item["tool"].string ?? entry.claude?.toolName ?? ""
        if ["request_user_input", "request_user_input_async", "AskUserQuestion", "ExitPlanMode", "EnterPlanMode", "TodoWrite", "TaskCreate", "TaskUpdate"].contains(name.components(separatedBy: ".").last ?? name) { return false }
        if let tool = entry.tool {
            return tool.outputs.isEmpty && tool.planSteps.isEmpty && tool.type != "exitedReviewMode" && tool.workers.isEmpty
        }
        if let claude = entry.claude {
            return claude.callID != nil && claude.outputs.isEmpty && (claude.checklist ?? []).isEmpty &&
                !["delegation", "task", "unknown"].contains(claude.category ?? "")
        }
        // Unknown records stay individually inspectable; never classify assistant prose.
        return false
    }
    static func rows(_ entries: [Entry], mode: HistoryDisplayMode) -> [HistoryRow] {
        var rows: [HistoryRow] = []
        var lastAsked: (text: String, turn: String?)?
        for entry in entries {
            if mode == .conversation && (isUsage(entry) || entry.category == .context) { continue }
            // A question the agent repeats in the same turn (Codex asks, waits for an answer, then
            // ends the turn asking again) shows once.
            if entry.kind == "You" { lastAsked = nil }
            if entry.kind == "Assistant" {
                let said = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if mode == .conversation, said.hasSuffix("?"), let lastAsked, lastAsked.text == said, lastAsked.turn == entry.turnID { continue }
                lastAsked = said.hasSuffix("?") ? (said, entry.turnID) : nil
            }
            let grouped = mode == .conversation && canGroup(entry)
            if grouped, rows.last?.grouped == true,
               rows.last?.entries.last?.turnID == entry.turnID,
               (rows.last?.entries.last?.claude != nil) == (entry.claude != nil) {
                rows[rows.count - 1].entries.append(entry)
            } else { rows.append(HistoryRow(entries: [entry], grouped: grouped)) }
        }
        return rows
    }
    static func anchor(_ id: String?, in rows: [HistoryRow], original: [Entry] = []) -> String? {
        guard let id else { return nil }
        if let match = rows.first(where: { $0.entries.contains { $0.id == id } }) { return match.id }
        guard let index = original.firstIndex(where: { $0.id == id }) else { return nil }
        let visible = Set(rows.map(\.id))
        return original.prefix(index).reversed().first { visible.contains($0.id) }?.id ?? rows.first?.id
    }
}

struct HistoryActivityGroup<Content: View>: View {
    let row: HistoryRow
    @ViewBuilder var content: (Entry) -> Content
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(row.entries) { entry in content(entry) }
                }.padding(.top, 10)
            }
        } label: { Group {
            Label(row.summary, systemImage: "terminal").font(.callout).foregroundStyle(.secondary)
         }.disclosurePointingHand() }.padding(.vertical, 4)
    }
}

/// Rebuilt only for changed source content; row layout never scans the transcript.
@MainActor final class ConversationRowCache {
    struct Prepared: Identifiable {
        var row: HistoryRow
        var separator: Date?
        var tail: Bool
        var id: String { row.id }
    }
    private var entries: [Entry] = []
    private var dates: [String: Date] = [:]
    private var invalidDates: Set<String> = []
    private var mode: HistoryDisplayMode?
    private var calendar: Calendar?
    private(set) var rows: [Prepared] = []
    private(set) var revision = 0
    func prepare(_ entries: [Entry], mode: HistoryDisplayMode, calendar: Calendar = .current) -> [Prepared] {
        guard self.entries != entries || self.mode != mode || self.calendar != calendar else { return rows }
        self.entries = entries; self.mode = mode; self.calendar = calendar
        // Retain only timestamps still in this history; streamed text reuses parsed dates.
        let stamps = Set(entries.compactMap(\.timestamp))
        dates = dates.filter { stamps.contains($0.key) }
        invalidDates.formIntersection(stamps)
        let grouped = ConversationHistory.rows(entries, mode: mode)
        var previous: Date?
        rows = grouped.map { row in
            let stamp = row.entries.first?.timestamp
            if let stamp, dates[stamp] == nil, !invalidDates.contains(stamp) {
                if let date = AvatarMessagePresentation.date(stamp) { dates[stamp] = date }
                else { invalidDates.insert(stamp) }
            }
            let date = stamp.flatMap { dates[$0] }
            var separator: Date?
            if let date {
                if let previous {
                    if !calendar.isDate(previous, inSameDayAs: date) || date.timeIntervalSince(previous) >= 300 { separator = date }
                } else { separator = date }
            }
            if let date { previous = date }
            return Prepared(row: row, separator: separator, tail: true)
        }
        for index in rows.indices.dropLast() {
            rows[index].tail = rows[index].row.entries.first?.category != rows[index + 1].row.entries.first?.category || rows[index + 1].separator != nil
        }
        revision += 1
        return rows
    }
}
