import Testing
@testable import DioramaCore

struct PermissionPresentationTests {
    func request(_ params: WireValue, method: String = "item/commandExecution/requestApproval") -> ExecutionRequest {
        ExecutionRequest(wireID: .string("permission"), method: method, params: params)
    }
    @Test func structuredClaudeReadPreservesExactPath() {
        let r = request(.object(["toolName": .string("Read"), "toolInput": .object(["file_path": .string("/tmp/space name/file.txt")]), "availableDecisions": .array([.string("accept"), .string("decline")])]))
        let p = PermissionPresentation(request: r)
        #expect(p.title == "Read this file?")
        #expect(p.target == "/tmp/space name/file.txt")
        #expect(r.decisions == ["accept", "decline"])
    }
    @Test func complexCommandsAreNeverParaphrasedAsSafe() {
        let command = "echo testing\n" + String(repeating: "echo more; ", count: 80) + "rm important-file"
        let p = PermissionPresentation(request: request(.object(["command": .string(command), "cwd": .string("/tmp/project")])))
        #expect(p.isLong)
        #expect(p.target.contains("review the full"))
        #expect(p.details.contains(command))
        #expect(p.details.contains("/tmp/project"))
    }
    @Test func unknownToolAndTurnGrantKeepHonestScope() {
        let unknown = PermissionPresentation(request: request(.object(["toolName": .string("mcp__records__update"), "toolInput": .object(["id": .string("123")])])))
        #expect(unknown.title == "Allow this tool action?")
        #expect(unknown.target.contains("not known"))
        #expect(unknown.details.contains("123"))
        let grant = PermissionPresentation(request: request(.object(["permissions": .object(["network": .object(["enabled": .bool(true)])])]), method: "item/permissions/requestApproval"))
        #expect(grant.scope == "Applies to this turn only.")
        #expect(grant.details.contains("Network access requested"))
    }
}
