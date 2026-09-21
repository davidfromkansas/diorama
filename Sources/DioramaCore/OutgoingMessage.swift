import Foundation

/// Local presentation of a submission; never itself triggers execution.
public struct OutgoingMessage: Codable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable { case pending, accepted, failed, uncertain }
    public let id: String
    public let sessionID: String
    public let text: String
    public let attachmentPaths: [String]
    public let createdAt: Date
    public let baselineIDs: Set<String>
    public var state: State = .pending
    public var error: String?
    public var turnID: String?
    public init(sessionID: String, text: String, attachmentPaths: [String], baselineIDs: Set<String>) {
        id = "outgoing-" + UUID().uuidString; self.sessionID = sessionID; self.text = text
        self.attachmentPaths = attachmentPaths; self.baselineIDs = baselineIDs; createdAt = Date()
    }
    public var entry: Entry {
        Entry(id: id, kind: "You", text: ([text] + attachmentPaths.map { "Attachment: " + URL(fileURLWithPath: $0).lastPathComponent }).filter { !$0.isEmpty }.joined(separator: "\n"), timestamp: ISO8601DateFormatter().string(from: createdAt))
    }
    public func matchingEcho(in entries: [Entry]) -> Bool {
        // Only a new provider entry can acknowledge this submission, never an older identical prompt.
        return entries.contains { entry in
            guard !baselineIDs.contains(entry.id), entry.kind == "You" else { return false }
            if let turnID, entry.turnID != turnID { return false }
            if text.isEmpty { return turnID != nil && !attachmentPaths.isEmpty }
            return entry.text == text || (!attachmentPaths.isEmpty && entry.text.hasPrefix(text + "\n"))
        }
    }
}
