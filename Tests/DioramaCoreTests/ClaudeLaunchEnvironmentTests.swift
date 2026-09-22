import Foundation
import Testing
@testable import DioramaCore

struct ClaudeLaunchEnvironmentTests {
    @Test func childUsesActualWorktreeInsteadOfInheritedGUIWorkingDirectory() {
        let source = ["PWD": "/Users/example/Documents/unrelated-project", "OLDPWD": "/Users/example/Desktop", "HOME": "/Users/example", "PATH": "/custom/bin:/usr/bin", "CFFIXED_USER_HOME": "/tmp/test-home", "__CFBundleIdentifier": "local.diorama", "XPC_SERVICE_NAME": "application.local.diorama", "CUSTOM_TOOL_SETTING": "preserved"]
        let binary = URL(fileURLWithPath: "/Users/example/.local/bin/claude")
        let result = ClaudeExecutionTransport.childEnvironment(source, folder: "/tmp/session worktree", executable: binary)
        #expect(result["PWD"] == "/tmp/session worktree")
        #expect(result["OLDPWD"] == nil)
        for key in ["HOME", "PATH", "CFFIXED_USER_HOME", "__CFBundleIdentifier", "XPC_SERVICE_NAME", "CUSTOM_TOOL_SETTING"] { #expect(result[key] == source[key]) }
        #expect(result["DIORAMA_CLAUDE_EXECUTABLE"] == binary.path)
        #expect(result["CLAUDE_CODE_ENABLE_TODO_TOOLS"] == "1")
        #expect(source["OLDPWD"] != nil)
    }

    @Test func directoryCorrectionPreservesSubscriptionCredentialFiltering() {
        let keys = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"]
        let source = Dictionary(uniqueKeysWithValues: keys.map { ($0, "fixture") })
        let result = ClaudeExecutionTransport.childEnvironment(source, folder: "/tmp/worktree", executable: URL(fileURLWithPath: "/usr/local/bin/claude"))
        for key in keys { #expect(result[key] == nil) }
        #expect(result["PWD"] == "/tmp/worktree")
    }
}
