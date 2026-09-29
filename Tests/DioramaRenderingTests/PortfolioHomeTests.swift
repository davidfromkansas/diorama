import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct PortfolioHomeTests {
    private func model(_ root: URL) -> LibraryModel {
        let project = DioramaProject(name: "Portfolio fixture", folder: root.path, commonDirectory: "", base: "", remote: nil)
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json")); projects.projects = [project]
        let model = LibraryModel(execution: ExecutionController(), projects: projects, conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")))
        model.portfolio = PortfolioStore(cache: nil)
        return model
    }
    private func session(_ root: URL, provider: Provider = .codex, id: String = "portfolio-external", archived: Bool = false) -> Session {
        Session(id: provider.rawValue + ":" + id, provider: provider, url: root.appendingPathComponent(id + ".jsonl"), sessionID: id,
            title: "Build project", project: root.path, modified: Date(), bytes: 0, archived: archived, parentID: nil, classification: .conversation)
    }
    @Test func externalUsageAndWorkingStateUpdateWithoutSelectingAConversation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(root), source = session(root), url = try #require(source.url)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let start = "{\"timestamp\":\"\(stamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn\"}}\n"
        let usage = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}"# + "\n"
        try Data((start + usage).utf8).write(to: url)
        model.sessions = [source]
        await model.portfolio.refresh(model)
        let id = try #require(model.projects.projects.first?.id)
        #expect(model.portfolio.usage(id).tokens == 100)
        #expect(model.spatialWorld(showArchived: false).projects.first?.summary.working == 1)
        let roster = OfficeRoster(teams: model.spatialWorld(showArchived: false).projects[0].teams, now: Date())
        #expect(roster.occupants.count == 1 && roster.occupants[0].agent.value.isWorking)
        let watcher = DirectoryWatcher(paths: [root.path]) { Task { await model.portfolio.refresh(model) } }
        let file = try FileHandle(forWritingTo: url); try file.seekToEnd()
        try file.write(contentsOf: Data(usage.replacingOccurrences(of: "100", with: "175").utf8)); try file.close()
        let deadline = Date().addingTimeInterval(3)
        while model.portfolio.usage(id).tokens != 175 && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.portfolio.usage(id).tokens == 175)
        #expect(model.selectedID == nil && model.execution.tasks.isEmpty)
        withExtendedLifetime(watcher) {}
        model.observationClock = Date().addingTimeInterval(31)
        #expect(model.spatialWorld(showArchived: false).projects.first?.summary.working == 0)
    }
    @Test func allTimeIncludesArchivedAndDeduplicatesMergedSources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(root), codex = session(root, id: "old", archived: true), claude = session(root, provider: .claude, id: "new")
        try Data((#"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}"# + "\n").utf8).write(to: try #require(codex.url))
        try Data((#"{"type":"assistant","message":{"id":"message","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30}}}"# + "\n").utf8).write(to: try #require(claude.url))
        var record = DioramaConversation(session: codex, model: "")
        record.segments.append(ConversationSegment(nativeID: claude.sessionID, provider: .claude, model: ""))
        model.conversations.records = [record]
        model.portfolio.register([codex, claude])
        model.sessions = model.conversations.project([codex, claude])
        await model.portfolio.refresh(model)
        let id = try #require(model.projects.projects.first?.id)
        #expect(model.portfolio.usage(id).tokens == 160)
        #expect(model.portfolio.usage(id).sources.count == 2)
        await model.portfolio.refresh(model)
        #expect(model.portfolio.usage(id).tokens == 160)
        #expect(model.spatialWorld(showArchived: false).projects.first?.teams.count == 1)
    }
    @Test func externalClaudeUpdatesUsageAndAttentionWithoutSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(root), source = session(root, provider: .claude), url = try #require(source.url)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let working = "{\"type\":\"assistant\",\"timestamp\":\"\(stamp)\",\"message\":{\"id\":\"m1\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20,\"cache_read_input_tokens\":30},\"content\":[{\"type\":\"tool_use\",\"id\":\"read\",\"name\":\"Read\",\"input\":{}}]}}\n"
        try Data(working.utf8).write(to: url)
        model.sessions = [source]
        await model.portfolio.refresh(model)
        let project = try #require(model.projects.projects.first)
        #expect(model.portfolio.usage(project.id).tokens == 60)
        #expect(model.spatialWorld(showArchived: false).projects.first?.summary.working == 1)
        let question = "{\"type\":\"assistant\",\"timestamp\":\"\(stamp)\",\"message\":{\"id\":\"m2\",\"usage\":{\"input_tokens\":5,\"output_tokens\":5},\"content\":[{\"type\":\"tool_use\",\"id\":\"question\",\"name\":\"AskUserQuestion\",\"input\":{}}]}}\n"
        let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd()
        try handle.write(contentsOf: Data(question.utf8)); try handle.close()
        await model.portfolio.refresh(model)
        #expect(model.portfolio.usage(project.id).tokens == 70)
        let spatial = try #require(model.spatialWorld(showArchived: false).projects.first)
        let roster = OfficeRoster(teams: spatial.teams, now: Date())
        #expect(roster.occupants.count == 1)
        #expect(roster.occupants[0].agent.needsAttention)
        #expect(roster.occupants[0].destination.expanded)
        #expect(spatial.summary.attention == 1)
        #expect(PortfolioException.ordered(spatial).first?.destination.expanded == true)
        #expect(model.selectedID == nil && model.execution.tasks.isEmpty)
    }
    @Test func stableProjectOrderAndScrollSurviveFocusChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(root)
        let original = try #require(model.projects.projects.first)
        await model.portfolio.refresh(model)
        model.portfolio.scrollID = original.id
        let added = DioramaProject(name: "Added", folder: root.appendingPathComponent("added").path, commonDirectory: "", base: "", remote: nil)
        model.projects.projects.insert(added, at: 0)
        model.spatial.focus = .project(original.id)
        await model.portfolio.refresh(model)
        model.spatial.focus = .portfolio
        #expect(model.portfolio.ordered(model.spatialWorld(showArchived: false).projects).map(\.id) == [original.id, added.id])
        #expect(model.portfolio.scrollID == original.id)
    }
    @Test func attachedUsageUpdatesWithoutExecutionAndPartialChildrenNeverDoubleCount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(root)
        var task = ExecutedTask(id: "live", title: "Live", folder: root.path, attached: true)
        task.workflow.usage = .object(["total": .object(["totalTokens": .number(90)])])
        model.execution.tasks[task.id] = task; model.sessions = [task.session]
        await model.portfolio.refresh(model)
        let project = try #require(model.projects.projects.first)
        #expect(model.portfolio.usage(project.id).tokens == 90)
        model.execution.tasks[task.id]?.workflow.usage = .object(["total": .object(["totalTokens": .number(150)])])
        await model.portfolio.refresh(model)
        #expect(model.portfolio.usage(project.id).tokens == 150)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let childURL = root.appendingPathComponent("child.jsonl")
        try Data((#"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000}}}}"# + "\n").utf8).write(to: childURL)
        let child = Session(id: "child", provider: .codex, url: childURL, sessionID: "child", title: "Child", project: root.path,
            modified: Date(), bytes: 0, archived: false, parentID: task.id, classification: .subagent)
        model.sessions.append(child)
        await model.portfolio.refresh(model)
        #expect(model.portfolio.usage(project.id).tokens == 150)
        #expect(model.portfolio.usage(project.id).coverage == .partial)
        #expect(model.selectedID == nil)
    }
    @Test func exceptionsHaveStablePriorityAndSourceDestinations() {
        let root = URL(fileURLWithPath: "/tmp/portfolio")
        let source = session(root)
        func agent(_ id: String, reason: WorkspaceAttentionReason, status: WorkspaceAgentStatus = .waiting) -> SpatialAgent {
            SpatialAgent(projectID: "p", conversationID: source.id, value: WorkspaceAgent(id: id, name: id, provider: "Codex", task: "Task", action: "", status: status, reportedStatus: "", freshness: .live, observedAt: Date(timeIntervalSince1970: id == "older" ? 1 : 2), attentionReason: reason))
        }
        let approval = agent("older", reason: .approval)
        let agents = [agent("input", reason: .input), agent("failed", reason: .other, status: .failed), approval, approval]
        let project = SpatialProject(id: "p", name: "P", teams: [.init(projectID: "p", session: source, agents: agents)])
        let ordered = PortfolioException.ordered(project)
        #expect(ordered.map(\.priority) == [0, 1, 2])
        #expect(ordered[0].destination.agentID == approval.id && ordered[0].destination.expanded)
    }
    @Test func platformCoordinatesAndResponsiveGridRemainIndependentOfRenderer() {
        let surface = PortfolioSurface(projectID: "p")
        let first = surface.project(u: 0.2, v: 0.8, width: 100, height: 100)
        let larger = surface.project(u: 0.2, v: 0.8, width: 200, height: 200)
        #expect(larger.x == first.x * 2 && larger.y == first.y * 2)
        #expect(surface.contains(u: 0, v: 1) && !surface.contains(u: -0.1, v: 0))
        #expect(PortfolioHomeView.columnCount(width: 1039) == 1)
        #expect(PortfolioHomeView.columnCount(width: 1040) == 2)
    }
    @Test func compactGridRendersLongNamesAndLargeRosters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = model(root)
        let projects = (0..<100).map { SpatialProject(id: "p\($0)", name: $0 == 0 ? "A long project name that needs two lines of readable text" : "Project \($0)", teams: []) }
        for width in [430, 800, 1100] {
            let host = NSHostingView(rootView: PortfolioHomeView(library: model, projects: projects, active: false, select: { _ in }))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 720)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/diorama-portfolio-\(width).png"))
        }
    }
}
