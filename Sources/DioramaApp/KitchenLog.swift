import Foundation

/// A log of what each chef does on screen: one JSON line per station change (heading to a
/// station, arriving, or jumping there when an unwatched kitchen catches up), with the agent's
/// latest tool call that caused it. Written to
/// ~/Library/Application Support/Diorama/KitchenLog/<yyyy-MM-dd>.jsonl so it can be laid next to
/// the conversation's transcript (`scripts/kitchen-timeline.py`).
nonisolated enum KitchenLog {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama/KitchenLog")
    }
    private static let queue = DispatchQueue(label: "diorama.kitchen-log", qos: .utility)
    static func record(_ fields: [String: String]) {
        var line = fields
        let now = Date()
        line["time"] = ISO8601DateFormatter.string(from: now, timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        let day = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        let directory = Self.directory
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(day + ".jsonl")
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data("\n".utf8))
        }
    }
}
