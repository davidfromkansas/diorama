import Foundation
import Testing
@testable import DioramaCore
@testable import DioramaApp

private actor AppSwitchTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue>
    var calls: [(String, WireValue)] = []
    var rejectCreation = false
    var count = 0
    var queues: [String: [WireValue]] = [:]
    init() { let (stream, _) = AsyncStream<WireValue>.makeStream(); events = stream }
    func connect() {}
    func request(_ method: String, _ p: WireValue) async throws -> WireValue {
        calls.append((method,p))
        switch method {
        case "model/list": return .object(["data": .array([.object(["model": .string("openai-fixture")]), .object(["model": .string("claude/fixture")])])])
        case "thread/start":
            if rejectCreation { throw ExecutionRPCRejection("Not logged in") }
            count += 1
            return .object(["thread": .object(["id": .string("target-\(count)")]), "cwd": p["cwd"], "model": p["model"]])
        case "thread/goal/get": return .object(["goal": .object(["objective": .string("Finish the task"), "status": .string("paused")])])
        case "thread/goal/set": return .object(["goal": .object(["objective": p["objective"], "status": p["status"]])])
        case "thread/queue/list": return .object(["data": .array(queues[p["threadId"].string ?? ""] ?? [])])
        case "thread/queue/add":
            let id = p["threadId"].string ?? ""
            let row: WireValue = .object(["id": .string("q-" + p["clientUserMessageId"].scalarText), "clientUserMessageId": p["clientUserMessageId"], "input": p["input"]])
            queues[id, default: []].append(row); return .object(["queuedSubmission": row])
        case "thread/queue/delete":
            queues[p["threadId"].string ?? ""]?.removeAll { $0["id"] == p["queuedSubmissionId"] }
            return .object(["deleted": .bool(true)])
        default: return .object([:])
        }
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
    func failCreation() { rejectCreation = true }
}

@MainActor struct ConversationSwitchTests {
    @Test func roundTripPreservesConversationWorktreeAndPR() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dirty = root.appendingPathComponent("uncommitted.txt")
        try Data("Keep this edit".utf8).write(to: dirty)
        let transport = AppSwitchTransport()
        let execution = ExecutionController(transport: transport)
        await execution.connect()
        var source = ExecutedTask(id: "source", title: "Original title", folder: root.path, attached: true)
        source.model = "openai-fixture"; source.phase = .finished
        source.transcript.entries = [Entry(id: "first", kind: "You", text: "Build this", timestamp: nil)]
        execution.tasks[source.id] = source
        var workspace = ProjectWorkspace(id: "work", folder: root.path, branch: "feature", baseCommit: "base", context: ProjectContext())
        workspace.threadID = source.id
        workspace.pullRequest = try JSONDecoder().decode(LinkedPullRequest.self, from: Data(#"{"number":1,"title":"Work","url":"https://github.com/a/b/pull/1","state":"OPEN","isDraft":false,"headRefName":"feature","headRefOid":"abc"}"#.utf8))
        var project = DioramaProject(name: "Project", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        project.workspaces = [workspace]
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json")); projects.projects = [project]
        let conversations = DioramaConversationModel(file: root.appendingPathComponent("conversations.json"))
        let library = LibraryModel(execution: execution, projects: projects, conversations: conversations)
        library.sessions = [source.session]; library.selectedID = source.session.id
        let claude = try await library.switchProvider(from: source.session, model: "claude/fixture")
        #expect(claude.id == source.session.id)
        #expect(claude.provider == .claude)
        #expect(library.sessions.count == 1)
        execution.tasks[claude.sessionID]?.transcript.entries = [Entry(id: "second", kind: "Assistant", text: "Claude decision", timestamp: nil)]
        let back = try await library.switchProvider(from: claude, model: "openai-fixture")
        #expect(back.id == source.session.id && back.provider == .codex)
        #expect(library.sessions.count == 1)
        #expect(library.displayedTranscript.entries.contains { $0.text == "Build this" })
        #expect(library.displayedTranscript.entries.contains { $0.text == "Claude decision" })
        #expect(conversations.records[0].segments.last?.handoff.contains("Claude decision") == true)
        let latest = try #require(projects.projects.first?.workspaces.first)
        #expect(latest.id == workspace.id && latest.branch == workspace.branch && latest.baseCommit == workspace.baseCommit)
        #expect(latest.pullRequest == workspace.pullRequest)
        #expect(try String(contentsOf: dirty, encoding: .utf8) == "Keep this edit")
        let restored = DioramaConversationModel(file: conversations.file)
        #expect(restored.records == conversations.records)
        #expect(restored.project([source.session, execution.tasks[claude.sessionID]!.session, execution.tasks[back.sessionID]!.session]).count == 1)
        let calls = await transport.calls
        #expect(!calls.contains { $0.0 == "turn/start" || $0.0 == "thread/fork" })
    }
}

extension ConversationSwitchTests {
    @Test func failedSwitchPreservesSelectionDraftAndSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = AppSwitchTransport(); let execution = ExecutionController(transport: transport)
        await execution.connect(); await transport.failCreation()
        var source = ExecutedTask(id: "failure-source", title: "Original", folder: root.path, attached: true)
        source.phase = .finished
        source.transcript.entries = [Entry(id: "history", kind: "You", text: "Existing conversation", timestamp: nil)]
        execution.tasks[source.id] = source
        let records = DioramaConversationModel(file: root.appendingPathComponent("conversations.json"))
        let library = LibraryModel(execution: execution, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), conversations: records)
        library.sessions = [source.session]; library.selectedID = source.session.id
        var draft = ConversationDraft(); draft.text = "Do not lose this"; draft.attachments = ["/tmp/reference.txt"]
        library.drafts[source.session.id] = draft
        await #expect(throws: (any Error).self) { try await library.switchProvider(from: source.session, model: "claude/fixture") }
        #expect(library.selectedID == source.session.id)
        #expect(library.drafts[source.session.id]?.text == draft.text)
        #expect(library.drafts[source.session.id]?.attachments == draft.attachments)
        #expect(records.records.isEmpty)
        #expect(!execution.retiredProviderSessions.contains(source.id))
    }
}
