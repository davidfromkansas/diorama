import Foundation
import Testing
@testable import DioramaCore

@Suite struct AgentNamingTests {
    @Test func stableScopedNamesAndMerges() throws {
        var names = AgentDisplayNames()
        let first = names.resolve(project: "p", identities: ["codex:a:main"], reported: "Main agent")
        let other = names.resolve(project: "p", identities: ["codex:b:main"], reported: "Main agent")
        #expect(first != other)
        var restored = try JSONDecoder().decode(AgentDisplayNames.self, from: JSONEncoder().encode(names))
        #expect(restored.resolve(project: "p", identities: ["codex:a:main", "claude:c:main"], reported: "Main agent") == first)
        #expect(restored.resolve(project: "p", identities: ["claude:c:main"], reported: "Main agent") == first)
        #expect(restored.resolve(project: "p", identities: ["codex:a:child"], reported: "Subagent") != first)
        #expect(restored.resolve(project: "p", identities: ["codex:d:child"], reported: "Socrates") == "Socrates")
        #expect(try JSONDecoder().decode(AgentDisplayNames.self, from: Data("{}".utf8)).names == nil)
    }
    @Test func taskTitlesAreNotNames() {
        var record = SessionActivityRecord(id: "a", provider: Provider.claude.rawValue, sessionID: "s", nativeID: "a", kind: "agent", title: "Review every changed file", status: "working", detail: "", source: "SDK", observedAt: Date(), data: .null)
        #expect(record.reportedAgentName == "Subagent")
        record.provider = Provider.codex.rawValue
        record.title = "Socrates"
        #expect(record.reportedAgentName == "Socrates")
        record.source = "External transcript"
        #expect(record.reportedAgentName == "Subagent")
        record.data = .object(["agentNickname": .string("Socrates")])
        #expect(record.reportedAgentName == "Socrates")
    }
    @Test func namePoolExhaustionStillOneWordAndUnique() {
        var names = AgentDisplayNames(), used = Set<String>()
        for index in 0..<150 {
            let name = names.resolve(project: "p", identities: ["agent:\(index)"], reported: "Subagent")
            let lettersOnly = name.allSatisfy { $0.isLetter }
            #expect(lettersOnly)
            #expect(used.insert(name).inserted)
        }
    }
    @Test func descriptiveSuggestionsValidationAndOldOptions() throws {
        #expect(DescriptiveBranch.suggestion("Can you add the project inbox please?") == "add-project-inbox")
        #expect(DescriptiveBranch.suggestion("hello") == nil)
        #expect(DescriptiveBranch.suggestion("do it") == nil)
        #expect(DescriptiveBranch.valid("fix-conversation-scrolling"))
        for name in ["bad/name", "Bad-Name", "-bad", "bad..name", "one-two-three-four-five-six-seven", ""] { #expect(!DescriptiveBranch.valid(name)) }
        #expect(DescriptiveBranch.candidate("one-two-three-four-five-six", suffix: 2) == "one-two-three-four-five-2")
        let old = try JSONDecoder().decode(SessionStartOptions.self, from: Data(#"{"folder":"/tmp","reference":"main","createWorktree":true}"#.utf8))
        #expect(old.branchName == nil)
    }
    @Test func gitCollisionConcurrencyAndPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await ProjectCommand.git(root.path, ["init", "-b", "main"])
        _ = try await ProjectCommand.git(root.path, ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-m", "Initial"])
        let project = try await ProjectGit.discover(root.path)
        _ = try await ProjectCommand.git(root.path, ["update-ref", "refs/remotes/origin/add-inbox", "HEAD"])
        let trees = root.appendingPathComponent("trees")
        async let a = ProjectGit.createWorkspace(project: project, id: "a", branchName: "add-inbox", root: trees)
        async let b = ProjectGit.createWorkspace(project: project, id: "b", branchName: "add-inbox", root: trees)
        let (first, second) = try await (a, b)
        #expect(Set([first.branch, second.branch]) == Set(["add-inbox-2", "add-inbox-3"]))
        #expect(first.folder == trees.appendingPathComponent(project.id).appendingPathComponent("a").path)
        #expect(await ProjectGit.currentBranch(root.path) == "main")
        #expect(try await ProjectGit.createWorkspace(project: project, id: "a", branchName: "different-name", root: trees).branch == first.branch)
    }
}
