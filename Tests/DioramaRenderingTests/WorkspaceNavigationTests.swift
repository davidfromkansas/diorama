import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct WorkspaceNavigationTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "diorama-ux-tests-" + UUID().uuidString)! }
    @Test func layoutAndDocumentsRestoreWithoutConflatingWorktrees() {
        let storage = defaults()
        let nav = WorkspaceNavigation(defaults: storage)
        nav.layout.sidebarWidth = 270
        nav.layout.inspectorVisible = false
        nav.layout.collapsedProjects.insert("project")
        nav.visit(.project("project", "session"))
        let first = WorkspaceDocument(folder: "/repo/one", path: "Sources/Main.swift")
        let other = WorkspaceDocument(folder: "/repo/two", path: "Sources/Main.swift")
        let diff = WorkspaceDocument(folder: "/repo/one", path: "Sources/Main.swift", workspaceID: "one", changeScope: ChangeScope.session.rawValue)
        nav.open(first, key: "session"); nav.open(first, key: "session"); nav.open(other, key: "session"); nav.open(diff, key: "session")
        #expect(nav.documents["session"]?.count == 3)
        nav.flushPersistence()
        let restored = WorkspaceNavigation(defaults: storage)
        #expect(restored.layout == nav.layout)
        #expect(restored.tabs["session"] == .document(diff))
        restored.close(diff, key: "session")
        #expect(restored.tabs["session"] == .conversation)
        #expect(restored.documents["session"] == [first, other])
        #expect(restored.layout.sidebarVisible)
        #expect(!WorkspaceNavigation.inlineInspector(width: 760))
        #expect(WorkspaceNavigation.inlineInspector(width: 1100))
    }
    @Test func historyBranchesAndDoesNotDuplicateCurrentDestination() {
        let nav = WorkspaceNavigation(defaults: defaults())
        nav.visit(.project("p", "a")); nav.visit(.project("p", "a")); nav.visit(.imported("b"))
        #expect(nav.backStack.count == 2)
        #expect(nav.back() == .project("p", "a"))
        #expect(nav.forward() == .imported("b"))
        _ = nav.back(); nav.visit(.project("p", "c"))
        #expect(nav.forward() == nil)
    }
    @Test func switchingPreservesDraftsWorkspacesAndContext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        var project = DioramaProject(name: "Example", folder: "/repo", commonDirectory: "/repo/.git", base: "main", remote: nil)
        project.draft = "Unsent project prompt"; project.draftAttachments = ["/repo/design.png"]
        project.context.instructions = "Keep this context"
        project.workspaces = [ProjectWorkspace(id: "w", folder: "/repo/work", branch: "codex/work", baseCommit: "abc", context: project.context)]
        projects.projects = [project]
        let library = LibraryModel(projects: projects, navigation: WorkspaceNavigation(defaults: defaults()))
        library.drafts["session"] = ConversationDraft()
        library.drafts["session"]?.text = "Unsent session prompt"
        library.drafts["session"]?.attachments = ["/repo/file.txt"]
        library.navigate(.project(project.id, "session")); library.navigate(.home); library.navigate(.imported("imported")); library.navigate(.project(project.id, "session"))
        #expect(library.drafts["session"]?.text == "Unsent session prompt")
        #expect(library.drafts["session"]?.attachments == ["/repo/file.txt"])
        #expect(projects.selected?.draft == project.draft)
        #expect(projects.selected?.draftAttachments == project.draftAttachments)
        #expect(projects.selected?.workspaces == project.workspaces)
        #expect(projects.selected?.context == project.context)
        #expect(library.selectedID == "session")
    }
}

extension WorkspaceNavigationTests {
    @Test func shellRendersAtSupportedWidthsWithApprovalAndLongTitles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let controller = ExecutionController(transport: WorkspaceFixtureTransport())
        var task = ExecutedTask(id: "ux-fixture", title: "Refine project navigation and preserve the complete agent workflow", folder: root.path, turnID: "turn", attached: true)
        task.model = "gpt-6-astra"; task.phase = .working
        task.transcript.entries = [
            Entry(id: "user", kind: "You", text: "Adopt Conductor’s UX while preserving Diorama’s functionality.", timestamp: nil),
            Entry(id: "assistant", kind: "Assistant", text: "The workspace now keeps the conversation in the center, with files and changes close at hand.\n\n- Project sessions stay together in the sidebar.\n- Existing approvals and provider controls remain available.\n- File previews open without losing your conversation.", timestamp: nil)
        ]
        controller.tasks[task.id] = task
        await controller.receive(.object(["id": .string("approval"), "method": .string("item/fileChange/requestApproval"), "params": .object(["threadId": .string(task.id), "turnId": .string("turn"), "itemId": .string("patch"), "availableDecisions": .array([.string("accept"), .string("decline")])])]))
        var project = DioramaProject(name: "Diorama", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        project.selectedSession = task.session.id
        projects.projects = [project]; projects.selectedID = project.id
        let model = LibraryModel(execution: controller, projects: projects, navigation: WorkspaceNavigation(defaults: defaults()))
        model.sessions = [task.session]; model.selectedID = task.session.id; model.transcriptSessionID = task.session.id; model.projectNavigation = true; model.paused = true
        for width in [760.0, 1100.0, 1440.0] {
            let view = WorkspaceShell(library: model) { Text("Open project") }.environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 820)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            func editors(_ view: NSView) -> [ComposerNSTextView] { (view as? ComposerNSTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
            let editor = try #require(editors(host).first)
            #expect(host.bounds.contains(editor.convert(editor.bounds, to: host)), "Composer must fit at \(width)")
            #expect(abs(host.bounds.width - width) < 1)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-workspace-\(Int(width)).png"))
            window.orderOut(nil)
        }
    }
}

private actor WorkspaceFixtureTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue> = AsyncStream { $0.finish() }
    func connect() {}
    func request(_ method: String, _ params: WireValue) throws -> WireValue {
        if method == "turn/start" { throw AppServerFailure("Fixture must never start an agent turn") }
        return .object(["data": .array([])])
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}

extension WorkspaceNavigationTests {
    @Test func documentTabsKeepTheComposerAndDraftMounted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("A local document".utf8).write(to: root.appendingPathComponent("note.txt"))
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let session = Session(id: "Codex:offline", provider: .codex, url: nil, sessionID: "offline", title: "Offline conversation", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        var project = DioramaProject(name: "Fixture", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        project.selectedSession = session.id; projects.projects = [project]; projects.selectedID = project.id
        let nav = WorkspaceNavigation(defaults: defaults())
        nav.layout.inspectorVisible = false
        let model = LibraryModel(execution: ExecutionController(transport: WorkspaceFixtureTransport()), projects: projects, navigation: nav)
        model.sessions = [session]; model.selectedID = session.id; model.transcriptSessionID = session.id; model.paused = true
        model.drafts[session.id] = ConversationDraft(); model.drafts[session.id]?.text = "Keep my unsent prompt"
        let host = NSHostingView(rootView: ProjectWorkbench(projectID: project.id, library: model).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func editors(_ view: NSView) -> [ComposerNSTextView] { (view as? ComposerNSTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
        try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
        let editor = try #require(editors(host).first)
        let key = project.id + ":" + session.id
        nav.open(WorkspaceDocument(folder: root.path, path: "note.txt"), key: key)
        try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
        #expect(editors(host).first === editor)
        nav.tabs[key] = .conversation
        try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
        #expect(editors(host).first === editor)
        #expect(editor.string == "Keep my unsent prompt")
        #expect(model.drafts[session.id]?.text == "Keep my unsent prompt")
        window.orderOut(nil)
    }
    @Test func emptyLoadingAndUnavailableViewsRender() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        var project = DioramaProject(name: "Long project name for checking the empty state", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        let session = Session(id: "Codex:loading", provider: .codex, url: nil, sessionID: "loading", title: "Loading fixture", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        project.selectedSession = session.id; projects.projects = [project]
        let model = LibraryModel(execution: ExecutionController(transport: WorkspaceFixtureTransport()), projects: projects, navigation: WorkspaceNavigation(defaults: defaults()))
        model.selectedID = session.id; model.paused = true
        let views: [(String, AnyView)] = [
            ("empty", AnyView(WorkspaceHome(library: model, imported: false))),
            ("loading", AnyView(SessionView(session: session, model: model, hasLocalReview: true))),
            ("unavailable", AnyView(WorkspaceDocumentView(document: WorkspaceDocument(folder: root.path, path: "missing.swift"), projectID: project.id, library: model, returnToConversation: {})))
        ]
        for (name, view) in views {
            let host = NSHostingView(rootView: view.background(DioramaStyle.canvas).environment(\.colorScheme, .dark))
            // Keep the fixture's explicit viewport when async loading changes intrinsic size.
            host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false); window.contentView = host
            try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
            #expect(host.bounds.width == 760 && host.bounds.height == 600)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-workspace-\(name).png"))
            window.orderOut(nil)
        }
    }
}
