import Foundation

public enum HookStore {
    public static var base: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Diorama") }
    public static var directory: URL { base.appendingPathComponent("Activity") }
    public static func write(_ event: ActivityEvent, directory: URL = directory) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(event)
        let url = directory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try prune(directory: directory)
    }
    private static func files(_ directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey])) ?? [])
            .filter { $0.pathExtension == "json" && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
    }
    public static func read(directory: URL = directory) -> [ActivityEvent] {
        try? prune(directory: directory)
        return files(directory).compactMap { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32 * 1024,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(ActivityEvent.self, from: data)
        }
    }
    public static func prune(directory: URL = directory, now: Date = Date(), maxBytes: Int = 50 * 1024 * 1024) throws {
        let items = files(directory).compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 < $1.1 }
        var total = items.reduce(0) { $0 + $1.2 }
        for (url, date, size) in items where date < now.addingTimeInterval(-7 * 86400) || total > maxBytes {
            try? FileManager.default.removeItem(at: url); total -= size
        }
    }
    public static func clear(directory: URL = directory) throws {
        for url in files(directory) { try FileManager.default.removeItem(at: url) }
    }
}

public struct HookCapability: Sendable {
    public let provider: Provider
    public let version: String
    public let events: [String]
    public let explanation: String
    public var canInstall: Bool { !events.isEmpty }
    public static func profile(provider: Provider, version: String) -> HookCapability {
        // Only the inspected Codex release is eligible for experimental setup. Never assume
        // current Claude documentation describes the old installed 1.x executable.
        if provider == .codex, version == "0.153.4" {
            return .init(provider: provider, version: version,
                         events: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "PreCompact", "PostCompact", "SubagentStart", "SubagentStop"],
                         explanation: "CLI verified: session/prompt, tools, approval/cancellation, interruption, subagents and manual compaction. Desktop 26.901.51231 resume verified: session-start, tool start/result and stop. UserPromptSubmit was absent on the desktop dispatch path; other desktop events and app restart remain unverified. Review hooks in the source client after setup.")
        }
        if provider == .claude, version == "1.0.108" {
            return .init(provider: provider, version: version,
                         events: ["PreToolUse", "PostToolUse", "Notification", "UserPromptSubmit", "SessionStart", "SessionEnd", "Stop", "SubagentStop", "PreCompact"],
                         explanation: "Legacy CLI: successful execution, session/prompt, tool start/result and subagent-stop delivery verified. Failure hooks and explicit subagent identity were unavailable. This version lacks PermissionRequest, SubagentStart, PostCompact and PostToolUseFailure. Notification payloads may not identify a reason. Restart Claude Code after setup.")
        }
        if provider == .claude, version == "2.1.276" {
            return .init(provider: provider, version: version,
                         events: ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "UserPromptSubmit", "SessionStart", "SessionEnd", "Stop", "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"],
                         explanation: "CLI verified: tools, subagents, compaction, resume, interactive approval/denial, AskUserQuestion, permission notifications and idle notifications. Approval resolution lacks correlation IDs. Command cancellation was tested but emitted no dedicated interruption hook; its transcript records a rejected tool result. Generic permission reminders may obscure the more specific input label. Unified Claude Desktop requires a separate integration. Restart Claude Code after setup.")
        }
        return .init(provider: provider, version: version, events: [], explanation: "Hook setup unavailable for this unvalidated version. Transcript observation remains available. Do not assume current documentation applies to this client.")
    }
}

public struct HookConfiguration: Sendable {
    public let provider: Provider
    public let configURL: URL
    public let reporterURL: URL
    public let eventDirectory: URL
    public init(provider: Provider, configURL: URL? = nil, base: URL = HookStore.base) {
        self.provider = provider
        let root = StorageRoot.defaults().first { $0.provider == provider }!.url.deletingLastPathComponent()
        self.configURL = configURL ?? root.appendingPathComponent(provider == .codex ? "hooks.json" : "settings.json")
        reporterURL = base.appendingPathComponent("Tools/DioramaReporter")
        eventDirectory = base.appendingPathComponent("Activity")
    }
    private func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public var command: String {
        quoted(reporterURL.path) + " --diorama-reporter-v1 " + (provider == .codex ? "codex" : "claude") + " " + quoted(eventDirectory.path)
    }
    public func original() throws -> Data? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        return try Data(contentsOf: configURL)
    }
    public func preview(original: Data?, events: [String], remove: Bool = false) throws -> Data {
        var object: [String: Any] = [:]
        if let original {
            guard let parsed = try JSONSerialization.jsonObject(with: original) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            object = parsed
        }
        if let hooks = object["hooks"], !(hooks is [String: Any]) { throw CocoaError(.fileReadCorruptFile) }
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        for key in Array(hooks.keys) {
            guard let groups = hooks[key] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            hooks[key] = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let kept = handlers.filter { $0["command"] as? String != command }
                if kept.count == handlers.count { return group }
                if kept.isEmpty { return nil }
                var updated = group; updated["hooks"] = kept; return updated
            }
        }
        if !remove {
            for event in events {
                var groups = hooks[event] as? [[String: Any]] ?? []
                groups.append(["matcher": "", "hooks": [["type": "command", "command": command, "timeout": 1]]])
                hooks[event] = groups
            }
        }
        object["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
    public func installed() -> Bool {
        guard let data = try? original(), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: [[String: Any]]] else { return false }
        return hooks.values.flatMap { $0 }.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
        }
    }
    public func apply(expected: Data?, updated: Data, bundledReporter: URL, remove: Bool) throws {
        guard try original() == expected else { throw NSError(domain: "Diorama", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provider settings changed. Reopen the preview before applying."]) }
        let fm = FileManager.default
        if !remove {
            try fm.createDirectory(at: reporterURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try Data(contentsOf: bundledReporter)
            try data.write(to: reporterURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: reporterURL.path)
        }
        try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let expected {
            let backup = configURL.appendingPathExtension("diorama-backup-" + UUID().uuidString)
            try expected.write(to: backup, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try updated.write(to: configURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }
}
