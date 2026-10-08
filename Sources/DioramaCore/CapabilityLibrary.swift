import Foundation

public struct CapabilityLibraryContext: Hashable, Sendable {
    public var provider: Provider
    public var folder: String
    public var sessionID: String?
    public init(provider: Provider, folder: String, sessionID: String? = nil) {
        self.provider = provider; self.folder = folder; self.sessionID = sessionID
    }
}
public enum CapabilityLibraryKind: String, CaseIterable, Sendable { case skill = "Skills", plugin = "Plugins", app = "Apps", tool = "Tools" }
public enum CapabilityAvailability: String, Sendable { case available = "Available", disabled = "Disabled", connectionNeeded = "Connection needed", unverified = "Unverified" }
public struct CapabilityLibraryItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var kind: CapabilityLibraryKind
    public var provider: Provider
    public var source: String
    public var pluginID: String?
    public var availability: CapabilityAvailability
    public init(id: String, name: String, description: String = "", kind: CapabilityLibraryKind, provider: Provider, source: String = "", pluginID: String? = nil, availability: CapabilityAvailability = .unverified) {
        self.id = id; self.name = name; self.description = description; self.kind = kind; self.provider = provider
        self.source = source; self.pluginID = pluginID; self.availability = availability
    }
    /// Stable across launches, unlike Swift's randomized Hasher.
    public var coverIndex: Int { Int((pluginID ?? id).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 } % 5) }
    public var emblem: String {
        switch kind { case .skill: "sparkles"; case .plugin: "books.vertical.fill"; case .app: "app.connected.to.app.below.fill"; case .tool: "wrench.and.screwdriver.fill" }
    }
}
public struct CapabilityLibrarySnapshot: Sendable {
    public var context: CapabilityLibraryContext
    public var items: [CapabilityLibraryItem] = []
    public var errors: [String: String] = [:]
    public var loadedAt = Date()
    public init(context: CapabilityLibraryContext, items: [CapabilityLibraryItem] = [], errors: [String: String] = [:], loadedAt: Date = Date()) {
        self.context = context; self.items = items; self.errors = errors; self.loadedAt = loadedAt
    }
    public var isFresh: Bool { errors.isEmpty && Date().timeIntervalSince(loadedAt) < 60 }
    public mutating func normalize() {
        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }.sorted { a, b in
            let comparison = a.name.localizedStandardCompare(b.name)
            return comparison == .orderedSame ? a.id < b.id : comparison == .orderedAscending
        }
    }
}

/// Files supply metadata, never proof that a runtime can invoke a capability.
public enum CapabilityLibraryFiles {
    static func wire(_ url: URL) throws -> WireValue { try JSONDecoder().decode(WireValue.self, from: Data(contentsOf: url)) }
    public static func plugin(containing path: String, provider: Provider) -> CapabilityLibraryItem? {
        guard path.hasPrefix("/") else { return nil }
        var directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        for _ in 0..<12 {
            let manifest = directory.appendingPathComponent(provider == .codex ? ".codex-plugin/plugin.json" : ".claude-plugin/plugin.json")
            if let data = try? wire(manifest), let name = data["name"].string {
                return .init(id: provider.rawValue + ":plugin:" + directory.path, name: name, description: data["description"].string ?? "", kind: .plugin, provider: provider, source: directory.path)
            }
            if directory.path == "/" { break }; directory.deleteLastPathComponent()
        }
        return nil
    }
    public static func attachPlugin(to item: inout CapabilityLibraryItem, items: inout [CapabilityLibraryItem]) {
        if var plugin = plugin(containing: item.source, provider: item.provider) {
            item.pluginID = plugin.id
            // A discovered enabled child proves this bundle contributes capabilities, not that every child is callable.
            plugin.availability = item.availability == .available ? .available : .unverified
            if let index = items.firstIndex(where: { $0.id == plugin.id }) {
                if plugin.availability == .available { items[index].availability = .available }
            } else { items.append(plugin) }
        }
    }
    /// Only explicit plugin configuration is considered; an arbitrary cache directory is not inventory.
    public static func codex(context: CapabilityLibraryContext, home: URL? = nil) -> CapabilityLibrarySnapshot {
        let root = home ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
        var result = CapabilityLibrarySnapshot(context: context)
        var flags: [String: Bool?] = [:]
        for file in [root.appendingPathComponent("config.toml"), URL(fileURLWithPath: context.folder).appendingPathComponent(".codex/config.toml")] {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                var plugin: String?
                for raw in text.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("[") {
                        plugin = nil
                        for quote in ["\"", "'"] {
                            let prefix = "[plugins." + quote, suffix = quote + "]"
                            if line.hasPrefix(prefix), let end = line.range(of: suffix, range: line.index(line.startIndex, offsetBy: prefix.count)..<line.endIndex) {
                                let value = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<end.lowerBound])
                                if !value.contains("\\") && value.contains("@") { plugin = value; if !flags.keys.contains(value) { flags[value] = .some(nil) } }
                            }
                        }
                    } else if let plugin, let match = line.range(of: #"^enabled\s*=\s*(true|false)\s*(#.*)?$"#, options: .regularExpression) {
                        flags[plugin] = line[match].split(separator: "#", maxSplits: 1)[0].contains("true")
                    }
                }
            } catch { result.errors["Configured plugins"] = error.localizedDescription }
        }
        for key in flags.keys.sorted() {
            let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts.allSatisfy({ !$0.contains("/") && $0 != "." && $0 != ".." }) else { continue }
            let cache = root.appendingPathComponent("plugins/cache").appendingPathComponent(parts[1]).appendingPathComponent(parts[0])
            let versions = (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? []
            let directory = versions.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }.first {
                FileManager.default.fileExists(atPath: $0.appendingPathComponent(".codex-plugin/plugin.json").path)
            }
            let manifest = directory.flatMap { try? wire($0.appendingPathComponent(".codex-plugin/plugin.json")) } ?? .null
            let source = directory?.path ?? "Configured: " + key
            result.items.append(.init(id: "Codex:plugin:" + source, name: manifest["name"].string ?? parts[0],
                description: manifest["description"].string ?? "Configured plugin. Runtime availability has not been verified.",
                kind: .plugin, provider: .codex, source: source, availability: flags[key] == .some(false) ? .disabled : .unverified))
        }
        result.normalize(); return result
    }
    static func linkPluginMembers(_ snapshot: inout CapabilityLibrarySnapshot) {
        let plugins = snapshot.items.filter { $0.kind == .plugin && $0.source.hasPrefix("/") }
        var apps: [String: [String]] = [:], servers: [String: [String]] = [:]
        for plugin in plugins {
            let root = URL(fileURLWithPath: plugin.source).standardizedFileURL
            let manifest = (try? wire(root.appendingPathComponent(plugin.provider == .codex ? ".codex-plugin/plugin.json" : ".claude-plugin/plugin.json"))) ?? .null
            func configuration(_ key: String, defaultFile: String) -> WireValue {
                if !manifest[key].object.isEmpty { return manifest[key] }
                let file = root.appendingPathComponent(manifest[key].string ?? defaultFile).standardizedFileURL
                guard file.path.hasPrefix(root.path + "/") else { return .null }
                return (try? wire(file)) ?? .null
            }
            let appConfig = configuration("apps", defaultFile: ".app.json")
            for app in appConfig["apps"].object.values {
                if let id = app["id"].string { apps[id, default: []].append(plugin.id) }
            }
            let serverConfig = configuration("mcpServers", defaultFile: ".mcp.json")
            let names = serverConfig["mcpServers"].object.isEmpty ? Array(serverConfig.object.keys) : Array(serverConfig["mcpServers"].object.keys)
            for name in names {
                servers[name, default: []].append(plugin.id)
                servers["plugin:" + plugin.name + ":" + name, default: []].append(plugin.id)
            }
        }
        for index in snapshot.items.indices where snapshot.items[index].pluginID == nil {
            let item = snapshot.items[index]
            let matches: [String]
            if item.kind == .app { matches = apps[String(item.source.dropFirst("app://".count))] ?? [] }
            else if item.kind == .tool { matches = servers[item.source == "MCP server" ? item.name : item.source] ?? [] }
            else { continue }
            if Set(matches).count == 1 { snapshot.items[index].pluginID = matches.first }
        }
    }
    public static func claude(context: CapabilityLibraryContext, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CapabilityLibrarySnapshot {
        var result = CapabilityLibrarySnapshot(context: context)
        let fm = FileManager.default
        var roots = [home.appendingPathComponent(".claude")]
        var folder = URL(fileURLWithPath: context.folder).standardizedFileURL
        var ancestors: [URL] = []
        while folder.path != "/" {
            if folder != home { ancestors.append(folder.appendingPathComponent(".claude")) }
            folder.deleteLastPathComponent()
        }
        roots += ancestors.reversed()
        var enabled: [String: Bool] = [:]
        for root in roots {
            for name in ["settings.json", "settings.local.json"] {
                let file = root.appendingPathComponent(name)
                if fm.fileExists(atPath: file.path) {
                    do { for (key, value) in try wire(file)["enabledPlugins"].object { if case .bool(let flag) = value { enabled[key] = flag } } }
                    catch { result.errors[file.path] = "Could not read Claude settings: \(error.localizedDescription)" }
                }
            }
            scanSkills(root.appendingPathComponent("skills"), plugin: nil, enabled: nil, into: &result)
        }
        let installed = home.appendingPathComponent(".claude/plugins/installed_plugins.json")
        if fm.fileExists(atPath: installed.path) {
            do {
                let registry = try wire(installed)
                for (key, entries) in registry["plugins"].object {
                    for entry in entries.array {
                        let scope = entry["scope"].string ?? "user"
                        if scope != "user" {
                            guard let project = entry["projectPath"].string,
                                  context.folder == project || context.folder.hasPrefix(project + "/") else { continue }
                        }
                        guard let path = entry["installPath"].string else { continue }
                        let root = URL(fileURLWithPath: path)
                        let manifest = root.appendingPathComponent(".claude-plugin/plugin.json")
                        let data = (try? wire(manifest)) ?? .null
                        let plugin = CapabilityLibraryItem(id: Provider.claude.rawValue + ":plugin:" + path,
                            name: data["name"].string ?? key, description: data["description"].string ?? "Installed plugin. Runtime availability has not been verified.", kind: .plugin, provider: .claude, source: path,
                            availability: enabled[key] == false ? .disabled : .unverified)
                        result.items.append(plugin)
                        scanSkills(root.appendingPathComponent("skills"), plugin: plugin, enabled: enabled[key], into: &result)
                    }
                }
            } catch { result.errors["Claude plugins"] = error.localizedDescription }
        }
        result.normalize(); return result
    }
    /// Codex skills on disk (`~/.codex/skills`, the project's `.codex/skills`), for when the
    /// runtime cannot list them (for example before signing in). Availability stays unverified.
    public static func codexSkills(context: CapabilityLibraryContext, home: URL? = nil) -> CapabilityLibrarySnapshot {
        let root = home ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
        var snapshot = CapabilityLibrarySnapshot(context: context)
        for folder in [root.appendingPathComponent("skills"), URL(fileURLWithPath: context.folder).appendingPathComponent(".codex/skills")] {
            scanSkills(folder, plugin: nil, enabled: nil, provider: .codex, into: &snapshot)
        }
        return snapshot
    }
    private static func scanSkills(_ root: URL, plugin: CapabilityLibraryItem?, enabled: Bool?, provider: Provider = .claude, into snapshot: inout CapabilityLibrarySnapshot) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        do {
            let dirs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            for dir in dirs where !dir.lastPathComponent.hasPrefix(".") {
                let file = dir.appendingPathComponent("SKILL.md")
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                do {
                    let metadata = frontmatter(try String(contentsOf: file, encoding: .utf8))
                    let localName = metadata["name"] ?? dir.lastPathComponent
                    let name = plugin.map { $0.name + ":" + localName } ?? localName
                    snapshot.items.append(.init(id: (provider == .claude ? "Claude Code" : "Codex") + ":skill:" + file.path, name: name, description: metadata["description"] ?? "", kind: .skill, provider: provider, source: file.path, pluginID: plugin?.id, availability: enabled == false ? .disabled : .unverified))
                } catch { snapshot.errors[file.path] = error.localizedDescription }
            }
        } catch { snapshot.errors[root.path] = error.localizedDescription }
    }
    static func frontmatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var values: [String: String] = [:]; var multiline: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if let key = multiline, line.hasPrefix(" ") { values[key, default: ""] += (values[key, default: ""].isEmpty ? "" : " ") + line.trimmingCharacters(in: .whitespaces); continue }
            multiline = nil
            guard let split = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<split]); let value = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
            guard ["name", "description"].contains(key) else { continue }
            if [">", "|", ">-", "|-"].contains(value) { values[key] = ""; multiline = key }
            else { values[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        }
        return values
    }
}

extension ExecutionController {
    public func capabilityLibrary(_ context: CapabilityLibraryContext) async -> CapabilityLibrarySnapshot {
        if context.provider == .claude {
            var snapshot = CapabilityLibraryFiles.claude(context: context)
            guard let id = context.sessionID else { return snapshot }
            do {
                let runtime = try await transport.request("diorama/capabilities", .object(["threadId": .string(id), "dioramaProvider": .string(Provider.claude.rawValue)]))
                Self.mergeClaude(runtime, into: &snapshot)
            } catch { snapshot.errors["Claude runtime"] = error.localizedDescription }
            CapabilityLibraryFiles.linkPluginMembers(&snapshot); snapshot.normalize(); return snapshot
        }
        var snapshot = CapabilityLibraryFiles.codex(context: context)
        var params: [String: WireValue] = [:]
        if let id = context.sessionID, tasks[id]?.attached == true { params["threadId"] = .string(id) }
        do {
            let reply = try await transport.request("skills/list", .object(["cwds": .array([.string(context.folder)]), "forceReload": .bool(true)]))
            for group in reply["data"].array {
                for row in group["skills"].array {
                    guard let path = row["path"].string, let name = row["name"].string else { continue }
                    var item = CapabilityLibraryItem(id: "Codex:skill:" + path, name: name, description: row["description"].string ?? "", kind: .skill, provider: .codex, source: path,
                        availability: row["enabled"] == .bool(true) ? .available : row["enabled"] == .bool(false) ? .disabled : .unverified)
                    CapabilityLibraryFiles.attachPlugin(to: &item, items: &snapshot.items); snapshot.items.append(item)
                }
                for (index, error) in group["errors"].array.enumerated() { snapshot.errors["Skill \(index)"] = error["message"].string ?? error.pretty }
            }
        } catch {
            snapshot.errors["Skills"] = error.localizedDescription
            // The runtime could not list skills; the ones on disk are still worth showing.
            snapshot.items += CapabilityLibraryFiles.codexSkills(context: context).items
        }
        do {
            let reply = try await transport.request("app/installed", .object(params))
            for row in reply["apps"].array {
                guard let id = row["id"].string else { continue }
                snapshot.items.append(.init(id: "Codex:app:" + id, name: row["runtimeName"].string ?? row["name"].string ?? id, description: row["description"].string ?? "", kind: .app, provider: .codex, source: "app://" + id,
                    availability: row["enabled"] == .bool(false) ? .disabled : row["callable"] == .bool(true) ? .available : row["callable"] == .bool(false) ? .connectionNeeded : .unverified))
            }
        } catch { snapshot.errors["Apps"] = error.localizedDescription }
        do {
            var cursor: String?; var seen = Set<String>()
            repeat {
                var p = params; p["limit"] = .number(100); if let cursor { p["cursor"] = .string(cursor) }
                let reply = try await transport.request("mcpServerStatus/list", .object(p))
                for row in reply["data"].array { Self.appendServer(row, provider: .codex, into: &snapshot) }
                cursor = reply["nextCursor"].string
                if let cursor, !seen.insert(cursor).inserted { throw AppServerFailure("Server pagination repeated") }
            } while cursor != nil
        } catch { snapshot.errors["Tools"] = error.localizedDescription }
        CapabilityLibraryFiles.linkPluginMembers(&snapshot); snapshot.normalize(); return snapshot
    }
    static func mergeClaude(_ runtime: WireValue, into snapshot: inout CapabilityLibrarySnapshot) {
        for (key, value) in runtime["errors"].object { snapshot.errors[key] = value.string ?? "Discovery failed" }
        let skills = Set(runtime["skills"].array.compactMap(\.string))
        let builtins = Set(runtime["commands"].array.filter { $0["builtin"] == .bool(true) }.compactMap { $0["name"].string })
        for command in runtime["commands"].array where command["builtin"] != .bool(true) {
            guard let name = command["name"].string, !builtins.contains(name) else { continue }
            let matches = snapshot.items.indices.filter { snapshot.items[$0].kind == .skill && snapshot.items[$0].name == name }
            if matches.count == 1, let index = matches.first {
                snapshot.items[index].availability = .available
                if snapshot.items[index].description.isEmpty { snapshot.items[index].description = command["description"].string ?? "" }
            } else if skills.contains(name) {
                snapshot.items.append(.init(id: "Claude Code:runtime-skill:" + name, name: name, description: command["description"].string ?? "", kind: .skill, provider: .claude, source: "Attached session", availability: .available))
            }
        }
        for plugin in runtime["plugins"].array {
            guard let path = plugin["path"].string else { continue }
            let id = "Claude Code:plugin:" + path
            if let index = snapshot.items.firstIndex(where: { $0.id == id }) { snapshot.items[index].availability = .available }
            else { snapshot.items.append(.init(id: id, name: plugin["name"].string ?? URL(fileURLWithPath: path).lastPathComponent, kind: .plugin, provider: .claude, source: path, availability: .available)) }
        }
        for name in runtime["tools"].array.compactMap(\.string) where !name.hasPrefix("mcp__") {
            snapshot.items.append(.init(id: "Claude Code:tool:" + name, name: name, kind: .tool, provider: .claude, source: "Attached Claude session", availability: .available))
        }
        for row in runtime["servers"].array { appendServer(row, provider: .claude, into: &snapshot) }
    }
    static func appendServer(_ row: WireValue, provider: Provider, into snapshot: inout CapabilityLibrarySnapshot) {
        guard let name = row["name"].string else { return }
        let state: CapabilityAvailability = row["status"].string == "connected" ? .available : row["status"].string == "disabled" ? .disabled : ["needs-auth", "failed"].contains(row["status"].string ?? "") || row["authStatus"].string == "notLoggedIn" ? .connectionNeeded : .unverified
        let serverID = provider.rawValue + ":server:" + name
        snapshot.items.append(.init(id: serverID, name: name, description: "MCP server. Tool access may require approval.", kind: .tool, provider: provider, source: "MCP server", availability: state))
        let tools = row["tools"].array.isEmpty ? row["tools"].object.map { key, value -> WireValue in var o = value.object; o["name"] = .string(key); return .object(o) } : row["tools"].array
        for tool in tools {
            guard let toolName = tool["name"].string else { continue }
            snapshot.items.append(.init(id: serverID + ":" + toolName, name: toolName, description: tool["description"].string ?? "", kind: .tool, provider: provider, source: name, availability: state))
        }
    }
}
