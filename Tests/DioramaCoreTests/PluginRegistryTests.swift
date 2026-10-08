import Foundation
import Testing
@testable import DioramaCore

struct PluginRegistryTests {
    /// A Codex plugin cache laid out the way Codex installs plugins.
    private func cache() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plugins-" + UUID().uuidString)
        func write(_ path: String, _ json: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try json.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("openai-curated-remote/vercel/.codex-remote-plugin-install.json", #"{"schema_version":1,"remote_plugin_id":"plugin_connector_690a"}"#)
        try write("openai-curated-remote/vercel/0.9.0/.codex-plugin/plugin.json", #"{"name":"vercel","interface":{"displayName":"Vercel (old)"}}"#)
        try write("openai-curated-remote/vercel/0.54.1/.codex-plugin/plugin.json", #"{"name":"vercel","interface":{"displayName":"Vercel"}}"#)
        try write("openai-curated-remote/figma/.codex-remote-plugin-install.json", #"{"remote_plugin_id":"plugin_connector_f1"}"#)
        try write("openai-bundled/browser/1.0.0/.codex-plugin/plugin.json", #"{"name":"browser"}"#)
        return root
    }

    @Test func installedPluginsNameTheirRemoteIDs() throws {
        let root = try cache()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PluginRegistry(roots: [root])
        #expect(registry.name(for: "plugin_connector_690a") == "Vercel")
        // No manifest: the folder's name.
        #expect(registry.name(for: "plugin_connector_f1") == "figma")
        #expect(registry.name(for: "plugin_connector_unknown") == nil)
    }

    @Test func aPluginInstalledLaterIsFoundOnTheNextMiss() throws {
        let root = try cache()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PluginRegistry(roots: [root], rescanAfter: 0)
        #expect(registry.name(for: "plugin_connector_new") == nil)
        let folder = root.appendingPathComponent("openai-curated-remote/linear")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"remote_plugin_id":"plugin_connector_new"}"#.write(to: folder.appendingPathComponent(".codex-remote-plugin-install.json"), atomically: true, encoding: .utf8)
        #expect(registry.name(for: "plugin_connector_new") == "linear")
    }
}
