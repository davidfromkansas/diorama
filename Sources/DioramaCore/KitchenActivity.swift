import Foundation

/// What kind of kitchen work an agent's latest tool call represents. Evidence → activity mapping,
/// first ported from the chef avatar prototype (`app/src/agent/mapping.ts`), then extended with
/// shell-command understanding: both providers mostly read files through the shell.
public enum KitchenActivity: String, Sendable, CaseIterable {
    case planning, researching, editing, commands, testing, resources, other

    /// Tool names arrive as Claude Code tool titles (`Read`, `Bash`…), Codex item types
    /// (`commandExecution`, `fileChange`…) or Codex function names (`exec_command`, `apply_patch`…).
    public static func classify(tool: String, detail: String = "") -> KitchenActivity {
        let name = tool.trimmingCharacters(in: .whitespaces).lowercased()
        if commandTools.contains(name) { return classify(command: detail) }
        // Using a skill or an MCP server's tool: fetching from the pantry.
        if isResource(tool: name) { return .resources }
        if researchTools.contains(name) { return .researching }
        if planningTools.contains(name) { return .planning }
        if editingTools.contains(name) { return .editing }
        return .other
    }

    public static func isEditing(tool: String) -> Bool { editingTools.contains(tool.lowercased()) }
    public static func isResource(tool: String) -> Bool {
        let name = tool.lowercased()
        return name.hasPrefix("mcp__") || resourceTools.contains(name)
    }
    static let resourceTools: Set<String> = ["skill", "mcptoolcall", "listmcpresources", "readmcpresource", "listmcpresourcestool", "readmcpresourcetool"]

    /// Tests anywhere in the script → testing; only read-only commands → researching; else commands.
    public static func classify(command: String) -> KitchenActivity {
        let script = shellScript(command)
        let range = NSRange(script.startIndex..., in: script)
        if testCommand.firstMatch(in: script, range: range) != nil { return .testing }
        let words = segments(script).compactMap { segment -> [String]? in
            let words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
                .drop { $0.contains("=") && !$0.hasPrefix("-") } // env assignments
            return words.isEmpty ? nil : Array(words)
        }.filter { $0.first != "cd" }
        guard !words.isEmpty else { return .commands }
        // Redirecting into a file writes (`> out`); stream redirects like `2>&1` don't.
        let redirect = try! NSRegularExpression(pattern: #"(?<![0-9&])>"#)
        if redirect.firstMatch(in: script, range: range) != nil { return .commands }
        let reads = words.allSatisfy { words in
            let program = (words[0] as NSString).lastPathComponent
            if program == "sed" && words.contains(where: { $0.hasPrefix("-i") }) { return false }
            if program == "git" { return words.count > 1 && readOnlyGit.contains(words[1]) }
            return readOnlyCommands.contains(program)
        }
        return reads ? .researching : .commands
    }

    /// Unwraps `/bin/zsh -lc "…"`, `bash -lc '…'`, `sh -c …` and JSON-array commands.
    public static func shellScript(_ command: String) -> String {
        var text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("["), let parts = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String] {
            text = parts.joined(separator: " ")
        }
        let wrapper = try! NSRegularExpression(pattern: #"^(?:/\S*/)?(?:ba|z)?sh\s+-l?c\s+"#)
        if let match = wrapper.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let end = Range(match.range, in: text)?.upperBound {
            text = String(text[end...]).trimmingCharacters(in: .whitespaces)
            if let first = text.first, first == "\"" || first == "'", text.count >= 2, text.last == first {
                text = String(text.dropFirst().dropLast())
            }
        }
        return text
    }

    static func segments(_ script: String) -> [String] {
        var result: [String] = [], current = "", quote: Character?
        var characters = Array(script)[...]
        while let c = characters.popFirst() {
            if let q = quote { current.append(c); if c == q { quote = nil }; continue }
            if c == "\"" || c == "'" { quote = c; current.append(c); continue }
            if c == ";" || c == "|" || c == "&" || c == "\n" {
                if (c == "|" || c == "&"), characters.first == c { characters.removeFirst() }
                result.append(current); current = ""; continue
            }
            current.append(c)
        }
        result.append(current)
        return result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static let researchTools: Set<String> = ["read", "grep", "glob", "websearch", "webfetch", "web__run", "web.search", "toolsearch", "view_image", "imageview"]
    static let planningTools: Set<String> = ["todowrite", "taskcreate", "taskupdate", "enterplanmode", "exitplanmode", "update_plan", "plan"]
    static let editingTools: Set<String> = ["edit", "write", "multiedit", "notebookedit", "filechange", "apply_patch"]
    static let commandTools: Set<String> = ["bash", "commandexecution", "shell", "local_shell", "exec_command", "write_stdin"]
    static let readOnlyCommands: Set<String> = ["cat", "sed", "head", "tail", "grep", "egrep", "rg", "ag", "ls", "find", "fd", "tree", "wc", "nl",
                                                "file", "stat", "du", "less", "more", "pwd", "jq", "echo", "printf", "which", "awk", "sort", "uniq", "cut", "diff", "realpath", "basename", "dirname"]
    static let readOnlyGit: Set<String> = ["log", "show", "diff", "status", "blame", "grep", "ls-files", "rev-parse", "branch", "remote", "describe"]
    static let testCommand = try! NSRegularExpression(pattern:
        #"\b(?:(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test|vitest|jest|pytest|go\s+test|cargo\s+test|swift\s+test|xcodebuild\s+(?:\S+\s+)*test|playwright\s+test|rspec|phpunit|ctest|mvn\s+test|gradle\w*\s+test)\b"#)
}
