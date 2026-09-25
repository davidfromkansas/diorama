import Foundation

/// One location for user-selected tools; never changes global installations.
public enum AgentExecutable {
    public static func resolve(_ name: String, defaults: UserDefaults = .standard) -> URL? {
        if let path = defaults.string(forKey: "agentExecutable." + name) {
            return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return directories.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    public static func validate(_ url: URL, name: String) async throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw AppServerFailure("Choose an executable \(name) tool.") }
        let data = try await ProjectCommand.data(url.path, ["--version"], timeout: 5)
        let version = String(decoding: data, as: UTF8.self).lowercased()
        guard version.contains(name), version.contains(where: { $0.isNumber }) else { throw AppServerFailure("This does not appear to be \(name). Choose its official executable.") }
    }
}
