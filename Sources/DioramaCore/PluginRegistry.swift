import Foundation

/// Names for installed plugins' remote ids, read from what Codex keeps on disk. Codex fetches a
/// plugin's skills by an opaque id (`skill://plugin_connector_690a…/domains`); each installed
/// plugin's folder records that id (`.codex-remote-plugin-install.json`, `remote_plugin_id`) next
/// to its manifest (`.codex-plugin/plugin.json`, `interface.displayName`). Nothing is hard-coded:
/// every installed plugin is found, read once, and re-read when an unknown id shows up (at most
/// every 30 s), so newly installed plugins name themselves.
public final class PluginRegistry: @unchecked Sendable {
    public static let shared = PluginRegistry()

    private let lock = NSLock()
    private var names: [String: String] = [:]
    private var scannedAt: Date?
    private let roots: [URL]
    private let rescanAfter: TimeInterval

    public init(roots: [URL]? = nil, rescanAfter: TimeInterval = 30) {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.roots = roots ?? [home.appendingPathComponent("plugins/cache")]
        self.rescanAfter = rescanAfter
    }

    /// The plugin's display name ("Vercel") for a remote id (`plugin_connector_…`), if installed.
    public func name(for remoteID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let name = names[remoteID] { return name }
        if let scannedAt, Date().timeIntervalSince(scannedAt) < rescanAfter { return nil }
        names = Self.scan(roots)
        scannedAt = Date()
        return names[remoteID]
    }

    /// `<root>/<marketplace>/<plugin>/.codex-remote-plugin-install.json`, and the newest version's
    /// manifest under `<plugin>/<version>/.codex-plugin/plugin.json` for its display name.
    static func scan(_ roots: [URL]) -> [String: String] {
        let files = FileManager.default
        var result: [String: String] = [:]
        for root in roots {
            for marketplace in (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                for plugin in (try? files.contentsOfDirectory(at: marketplace, includingPropertiesForKeys: nil)) ?? [] {
                    guard let data = try? Data(contentsOf: plugin.appendingPathComponent(".codex-remote-plugin-install.json")),
                          let install = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = install["remote_plugin_id"] as? String, !id.isEmpty else { continue }
                    result[id] = displayName(plugin) ?? plugin.lastPathComponent
                }
            }
        }
        return result
    }
    private static func displayName(_ plugin: URL) -> String? {
        let versions = ((try? FileManager.default.contentsOfDirectory(at: plugin, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
        for version in versions {
            guard let data = try? Data(contentsOf: version.appendingPathComponent(".codex-plugin/plugin.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let interface = manifest["interface"] as? [String: Any]
            if let name = (interface?["displayName"] as? String) ?? (manifest["name"] as? String), !name.isEmpty { return name }
        }
        return nil
    }
}
