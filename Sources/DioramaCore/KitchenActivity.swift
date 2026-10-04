import Foundation

/// What kind of kitchen work an agent's latest tool call represents. Configurable evidence →
/// activity mapping, ported from the chef avatar prototype (`app/src/agent/mapping.ts`).
public enum KitchenActivity: String, Sendable, CaseIterable {
    case planning, researching, working, commands, testing

    /// Tool names arrive as Claude Code tool titles (`Read`, `Bash`…) or Codex item types
    /// (`commandExecution`, `fileChange`…). Anything unlisted counts as generic working.
    public static func classify(tool: String, detail: String = "") -> KitchenActivity {
        let name = tool.trimmingCharacters(in: .whitespaces).lowercased()
        if commandTools.contains(name) {
            let range = NSRange(detail.startIndex..., in: detail)
            return testCommand.firstMatch(in: detail, range: range) != nil ? .testing : .commands
        }
        if researchTools.contains(name) { return .researching }
        if planningTools.contains(name) { return .planning }
        return .working
    }
    static let researchTools: Set<String> = ["read", "grep", "glob", "websearch", "webfetch", "listmcpresources", "readmcpresource", "listmcpresourcestool", "readmcpresourcetool"]
    static let planningTools: Set<String> = ["todowrite", "taskcreate", "taskupdate", "enterplanmode", "exitplanmode", "update_plan", "plan"]
    static let commandTools: Set<String> = ["bash", "commandexecution", "shell", "local_shell", "exec_command"]
    static let testCommand = try! NSRegularExpression(pattern:
        #"\b(?:(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test|vitest|jest|pytest|go\s+test|cargo\s+test|swift\s+test|xcodebuild\s+(?:\S+\s+)*test|playwright\s+test|rspec|phpunit|ctest|mvn\s+test|gradle\w*\s+test)\b"#)
}
