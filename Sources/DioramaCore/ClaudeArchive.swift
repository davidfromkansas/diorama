import Foundation

/// Archiving Claude Code conversations. Claude Desktop keeps the flag as `isArchived` in its
/// `local_<id>.json` session metadata (the same file `ClaudeDesktopHistory` reads); CLI and
/// Diorama-run sessions have no such file. Diorama also remembers every Claude conversation it
/// archived, so it stays hidden here even when no Desktop file exists or Claude Desktop rewrites
/// its own copy from memory.
public struct ClaudeArchive {
    public static let defaultsKey = "archivedClaudeSessions"
    public let paths: ClaudeDesktopPaths
    private let defaults: UserDefaults
    public init(paths: ClaudeDesktopPaths = .defaults, defaults: UserDefaults = .standard) {
        self.paths = paths; self.defaults = defaults
    }

    /// Session ids (`Session.id`) archived from Diorama.
    public var archivedIDs: Set<String> { Set(defaults.stringArray(forKey: Self.defaultsKey) ?? []) }

    public func setArchived(_ session: Session, archived: Bool) throws {
        guard session.provider == .claude else { throw AppServerFailure("Only Claude conversations are archived here") }
        if let desktopID = session.desktopSessionID { try setDesktopArchived(desktopID, archived: archived) }
        var ids = archivedIDs
        if archived { ids.insert(session.id) } else { ids.remove(session.id) }
        defaults.set(ids.sorted(), forKey: Self.defaultsKey)
    }

    /// Flips only `isArchived` in Claude Desktop's metadata, keeping every other field as it was.
    public func setDesktopArchived(_ desktopSessionID: String, archived: Bool) throws {
        guard desktopSessionID.hasPrefix("local_"), UUID(uuidString: String(desktopSessionID.dropFirst(6))) != nil,
              let file = metadataFile(desktopSessionID) else { throw AppServerFailure("Claude Desktop session file not found") }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1_048_576 else {
            throw AppServerFailure("Claude Desktop session file is not a plain file")
        }
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
              object["sessionId"] as? String == desktopSessionID else { throw AppServerFailure("Claude Desktop session file has an unexpected format") }
        object["isArchived"] = archived
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]).write(to: file, options: .atomic)
    }

    private func metadataFile(_ desktopSessionID: String) -> URL? {
        let name = desktopSessionID + ".json"
        let files = FileManager.default.enumerator(at: paths.metadata, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        var visited = 0
        while let url = files?.nextObject() as? URL {
            visited += 1
            if visited > 20_000 { return nil }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { files?.skipDescendants(); continue }
            if url.lastPathComponent == name { return url }
        }
        return nil
    }
}
