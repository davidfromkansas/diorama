import Foundation

public enum SessionOrigin: String, Codable, Sendable {
    case unknown, claudeCLI, claudeDesktop
    public var label: String {
        switch self {
        case .unknown: "Claude Code · source unknown"
        case .claudeCLI: "Claude Code CLI"
        case .claudeDesktop: "Claude Code Desktop"
        }
    }
}

/// Paths are discovered from Desktop metadata and hooks, never reconstructed from a project name.
public struct ClaudeDesktopPaths: Sendable {
    public let metadata: URL
    public let transcripts: URL
    public let registry: URL
    public init(metadata: URL, transcripts: URL, registry: URL) {
        self.metadata = metadata; self.transcripts = transcripts; self.registry = registry
    }
    public static var defaults: Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        return .init(metadata: home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"),
                     transcripts: config.appendingPathComponent("projects"), registry: HookStore.base.appendingPathComponent("ClaudeSessions"))
    }
    public func permitsTranscript(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension == "jsonl" else { return false }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return [transcripts, metadata].contains { root in
            path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/")
        }
    }
}

/// No conversation bodies or credentials. Stored separately from expiring activity events.
public struct ClaudeSessionReference: Codable, Sendable {
    public let sessionID: String
    public let transcriptPath: String
    public let workingDirectory: String
    public let observedAt: Date
    public let origin: SessionOrigin

    public static func hook(_ record: [String: Any], environment: [String: String] = ProcessInfo.processInfo.environment,
                            now: Date = Date()) -> Self? {
        guard let id = record["session_id"] as? String, UUID(uuidString: id) != nil,
              record["agent_id"] == nil,
              let path = record["transcript_path"] as? String, path.hasPrefix("/"), path.utf8.count <= 4096,
              let cwd = record["cwd"] as? String, cwd.hasPrefix("/"), cwd.utf8.count <= 4096,
              environment["CLAUDE_CODE_REMOTE"] != "true", environment["SSH_CONNECTION"] == nil else { return nil }
        // Desktop identity is established by matching its metadata, not by assuming a CLI entrypoint.
        let origin: SessionOrigin = environment["CLAUDE_CODE_ENTRYPOINT"] == "cli" ? .claudeCLI : .unknown
        return .init(sessionID: id, transcriptPath: path, workingDirectory: cwd, observedAt: now, origin: origin)
    }
    public func write(paths: ClaudeDesktopPaths) throws {
        guard UUID(uuidString: sessionID) != nil, paths.permitsTranscript(URL(fileURLWithPath: transcriptPath)) else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.registry, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: paths.registry.appendingPathComponent(sessionID + ".json"), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.registry.appendingPathComponent(sessionID + ".json").path)
    }
    static func read(paths: ClaudeDesktopPaths) -> [Self] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: paths.registry, includingPropertiesForKeys: nil) else { return [] }
        return files.prefix(20_000).compactMap { file in
            guard file.pathExtension == "json", let data = DesktopFile.read(file, limit: 16_384),
                  let record = try? JSONDecoder().decode(Self.self, from: data), UUID(uuidString: record.sessionID) != nil,
                  paths.permitsTranscript(URL(fileURLWithPath: record.transcriptPath)) else { return nil }
            return record
        }
    }
}

private enum DesktopFile {
    static func read(_ url: URL, limit: Int) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit)
    }
}

/// Version-tested local_<UUID>.json metadata adapter. Unknown formats are reported, not guessed.
public struct ClaudeDesktopHistory: Sendable {
    public let paths: ClaudeDesktopPaths
    public init(paths: ClaudeDesktopPaths = .defaults) { self.paths = paths }

    struct Metadata: Decodable {
        let sessionId: String
        let cliSessionId: String
        let cwd: String
        let title: String?
        let lastActivityAt: Double?
        let isArchived: Bool?
    }

    public func merging(_ existing: [Session]) -> LibrarySnapshot {
        var sessions = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var notices: [String] = []
        let references = ClaudeSessionReference.read(paths: paths)
        var latest: [String: ClaudeSessionReference] = [:]
        for ref in references where latest[ref.sessionID].map({ $0.observedAt < ref.observedAt }) ?? true { latest[ref.sessionID] = ref }
        // Hooks can discover a file before the next recursive scan. Verify its embedded identity.
        for ref in latest.values {
            let key = Provider.claude.rawValue + ":" + ref.sessionID
            let url = URL(fileURLWithPath: ref.transcriptPath)
            if sessions[key] == nil, let parsed = verifiedTranscript(url, id: ref.sessionID) { sessions[key] = parsed }
            if var session = sessions[key] {
                session.lastObservedHook = ref.observedAt
                if session.origin == .unknown { session.origin = ref.origin }
                sessions[key] = session
            }
        }
        let fm = FileManager.default
        var unavailable = 0, malformed = 0, visited = 0
        var metadataByID: [String: Metadata] = [:]
        if fm.fileExists(atPath: paths.metadata.path) {
            if !fm.isReadableFile(atPath: paths.metadata.path) { notices.append("Claude Code Desktop: metadata directory is not readable.") }
            let files = fm.enumerator(at: paths.metadata, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in false })
            while let url = files?.nextObject() as? URL {
                if Task.isCancelled { break }
                visited += 1
                if visited > 20_000 { notices.append("Claude Code Desktop: discovery limit reached."); break }
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { files?.skipDescendants(); continue }
                guard url.pathExtension == "json", url.lastPathComponent.hasPrefix("local_") else { continue }
                guard let data = DesktopFile.read(url, limit: 1_048_576),
                      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { malformed += 1; continue }
                // Remote sessions are outside this adapter even if their metadata has a local-looking ID.
                if raw["sshHost"] != nil || raw["sshConnection"] != nil || raw["sshConnectionId"] != nil || raw["remoteSessionId"] != nil { continue }
                guard let meta = try? JSONDecoder().decode(Metadata.self, from: data),
                      meta.sessionId == url.deletingPathExtension().lastPathComponent,
                      UUID(uuidString: String(meta.sessionId.dropFirst(6))) != nil,
                      UUID(uuidString: meta.cliSessionId) != nil, meta.cwd.hasPrefix("/") else { malformed += 1; continue }
                if let old = metadataByID[meta.cliSessionId], (old.lastActivityAt ?? 0) >= (meta.lastActivityAt ?? 0) { continue }
                metadataByID[meta.cliSessionId] = meta
            }
        }
        for meta in metadataByID.values {
            let key = Provider.claude.rawValue + ":" + meta.cliSessionId
            let local = sessions[key]
            let url = local?.url.flatMap { paths.permitsTranscript($0) ? $0 : nil }
            if url == nil { unavailable += 1 }
            let date = Date(timeIntervalSince1970: (meta.lastActivityAt ?? 0) / 1000)
            var session = Session(id: key, provider: .claude, url: url, sessionID: meta.cliSessionId,
                                  title: meta.title.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) } ?? local?.title ?? "Untitled Desktop conversation",
                                  project: meta.cwd, modified: max(date, local?.modified ?? .distantPast), bytes: local?.bytes ?? 0,
                                  archived: meta.isArchived ?? false, parentID: nil)
            session.titleSource = meta.title?.isEmpty == false ? .provider : local?.titleSource ?? .prompt
            if let local { session = session.retainingTitle(from: local) }
            session.origin = .claudeDesktop
            session.desktopSessionID = meta.sessionId
            session.lastObservedHook = latest[meta.cliSessionId]?.observedAt
            session.classification = .conversation
            session.classificationEvidence = "Desktop local session metadata matched by cliSessionId"
            session.historySource = url == nil ? "Claude Code Desktop · transcript unavailable" : "Claude Code Desktop · local transcript"
            sessions[key] = session
        }
        let desktopIDs = Set(metadataByID.keys)
        for (key, value) in sessions where value.provider == .claude && value.parentID.map(desktopIDs.contains) == true {
            var child = value; child.origin = .claudeDesktop; sessions[key] = child
        }
        if malformed > 0 { notices.append("Claude Code Desktop: \(malformed) metadata files have an unsupported or unreadable format.") }
        if unavailable > 0 { notices.append("Claude Code Desktop: \(unavailable) conversations have no readable matching local transcript.") }
        return .init(sessions: sessions.values.sorted { $0.modified > $1.modified }, notices: notices)
    }

    private func verifiedTranscript(_ url: URL, id: String) -> Session? {
        guard paths.permitsTranscript(url),
              let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isRegularFileKey]),
              attrs.isRegularFile == true, attrs.isSymbolicLink != true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512 * 1024),
              let session = SessionLibrary.metadata(data: data, url: url, root: .init(url: paths.transcripts, provider: .claude),
                                                    modified: attrs.contentModificationDate ?? .distantPast, size: attrs.fileSize ?? 0),
              session.sessionID == id, session.classification != .subagent else { return nil }
        return session
    }

    public static var installedVersion: String? {
        for url in [URL(fileURLWithPath: "/Applications/Claude.app"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Claude.app")] {
            if let bundle = Bundle(url: url), let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return version }
        }
        return nil
    }
}
