import Foundation
import Testing
@testable import DioramaCore

/// Opt-in, read-only: replays recent local Claude and Codex transcripts through the activity
/// parser and the kitchen classifier, and writes per-provider bucket shares to /tmp.
struct KitchenActivityAuditProbe {
    @Test func auditRecentTranscripts() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_KITCHEN_AUDIT"] == "1" else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var report: [String] = []
        for (provider, root) in [(Provider.claude, home.appendingPathComponent(".claude/projects")), (.codex, home.appendingPathComponent(".codex/sessions"))] {
            let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])?.compactMap { $0 as? URL } ?? [])
                .filter { $0.pathExtension == "jsonl" }
                .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
                .prefix(40)
            var counts: [KitchenActivity: Int] = [:], tools: [String: Int] = [:]
            for file in files {
                let session = Session(id: "audit", provider: provider, url: file, sessionID: "audit", title: "audit", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for (index, line) in text.split(separator: "\n").enumerated() {
                    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                    for event in ActivityParser.transcript(object, session: session, id: "\(index)", now: Date()) where event.kind == "toolStarted" {
                        counts[KitchenActivity.classify(tool: event.tool ?? "", detail: event.detail ?? ""), default: 0] += 1
                        tools[event.tool ?? "(none)", default: 0] += 1
                    }
                }
            }
            let total = max(1, counts.values.reduce(0, +))
            report.append("\(provider.rawValue): \(total) tool calls in \(files.count) recent transcripts")
            for activity in KitchenActivity.allCases {
                let n = counts[activity, default: 0]
                report.append(String(format: "  %-12@ %6d  %5.1f%%", activity.rawValue as NSString, n, Double(n) * 100 / Double(total)))
            }
            report.append("  top tools: " + tools.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        }
        let output = report.joined(separator: "\n")
        print(output)
        try output.write(toFile: "/tmp/diorama-kitchen-audit.txt", atomically: true, encoding: .utf8)
    }
}
