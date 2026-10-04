import SwiftUI
import Testing
import Sparkle
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct AppUpdateTests {
    @Test func dismissDoesNotCancelDownloadOrReappearWhenReady() {
        let updates = AppUpdateCoordinator()
        var cancelled = false
        updates.showDownloadInitiated { cancelled = true }
        updates.dismiss()
        updates.showDownloadDidReceiveExpectedContentLength(100)
        updates.showDownloadDidReceiveData(ofLength: 42)
        #expect(updates.progress == 0.42)
        var installed = false
        updates.showReady { _ in installed = true }
        #expect(!updates.visible)
        #expect(!cancelled)
        #expect(!installed)
    }
    @Test func progressHandlesUnknownLengthAndClampsOversizedResponse() {
        let updates = AppUpdateCoordinator()
        updates.showDownloadInitiated {}
        updates.showDownloadDidReceiveData(ofLength: 10)
        #expect(updates.progress == nil)
        updates.showDownloadDidReceiveExpectedContentLength(100)
        updates.showDownloadDidReceiveData(ofLength: 200)
        #expect(updates.progress == 1)
        updates.showDownloadInitiated {}
        #expect(updates.progress == nil)
        updates.showDownloadDidReceiveExpectedContentLength(100)
        updates.showDownloadDidReceiveData(ofLength: 10)
        #expect(updates.progress == 0.1)
    }
    @Test func ordinaryQuitCancelsPreparedInstallerInsteadOfInstalling() async throws {
        let updates = AppUpdateCoordinator()
        var choice: SPUUserUpdateChoice?
        var active = true
        updates.showReady { choice = $0; active = false }
        #expect(choice == nil)
        try await updates.cancelPendingUpdate(while: { active })
        #expect(choice == .skip)
        #expect(!updates.approvedShutdown)
    }
    @Test func ordinaryQuitDuringExtractionCancelsWhenInstallerBecomesReady() async throws {
        let updates = AppUpdateCoordinator()
        var choice: SPUUserUpdateChoice?
        var active = true
        updates.showDownloadDidStartExtractingUpdate()
        let cancellation = Task { try await updates.cancelPendingUpdate(while: { active }) }
        await Task.yield()
        updates.showReady { choice = $0; active = false }
        try await cancellation.value
        #expect(choice == .skip)
    }
    @Test func ordinaryQuitCancelsDownloadAndErrorsRemainVisible() async throws {
        let updates = AppUpdateCoordinator()
        var active = true
        updates.showUserInitiatedUpdateCheck {}
        updates.showDownloadInitiated { active = false }
        try await updates.cancelPendingUpdate(while: { active })
        var acknowledged = false
        updates.showUpdaterError(NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline"])) { acknowledged = true }
        updates.dismissUpdateInstallation()
        #expect(acknowledged)
        #expect(updates.phase == .failed)
        #expect(updates.detail == "Offline")
    }
    @Test(arguments: [false, true]) func restartWaitsForConsentAndSuccessfulShutdown(failShutdown: Bool) async throws {
        let transport = UpdateFixtureTransport(failShutdown: failShutdown)
        let execution = ExecutionController(transport: transport)
        await execution.connect()
        execution.tasks["fixture"] = ExecutedTask(id: "fixture", title: "Fixture", folder: "/tmp", attached: true)
        let defaults = try #require(UserDefaults(suiteName: "update-test-" + UUID().uuidString))
        let library = LibraryModel(execution: execution, navigation: WorkspaceNavigation(defaults: defaults), observationHookDirectory: nil)
        let updates = AppUpdateCoordinator()
        updates.configure(library: library)
        var installed = false
        updates.showReady { installed = $0 == .install }
        updates.requestRestart()
        for _ in 0..<50 where !updates.confirmingRestart { try await Task.sleep(for: .milliseconds(10)) }
        #expect(updates.confirmingRestart)
        #expect(!installed)
        #expect(await transport.closed == false)
        updates.confirmRestart()
        updates.confirmRestart() // Repeated activation must not start a second shutdown.
        for _ in 0..<100 where !installed && updates.detail.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(installed == !failShutdown)
        #expect(updates.approvedShutdown == !failShutdown)
        #expect(await transport.closed == !failShutdown)
        #expect(await transport.turns == 0)
        if failShutdown { #expect(updates.phase == .ready); #expect(updates.detail.contains("Could not restart")) }
    }
    @Test func workspaceAndRestartConfirmationScreenshots() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("update-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let execution = ExecutionController(transport: UpdateFixtureTransport(failShutdown: false))
        var task = ExecutedTask(id: "update-preview", title: "Polish the kitchen", folder: root.path, attached: false)
        task.transcript.entries = [Entry(id: "question", kind: "You", text: "Make the kitchen feel more welcoming.", timestamp: nil), Entry(id: "answer", kind: "Assistant", text: "The layout is ready for review. Warm lighting and open aisles keep the stations easy to see.", timestamp: nil)]
        execution.tasks[task.id] = task
        let defaults = try #require(UserDefaults(suiteName: "update-preview-" + UUID().uuidString))
        defaults.set("Conversation", forKey: "conversationHistoryDisplayMode")
        let model = LibraryModel(execution: execution, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")), navigation: WorkspaceNavigation(defaults: defaults), observationHookDirectory: nil)
        model.paused = true; model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation
        var project = DioramaProject(name: "Kitchen preview", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        project.selectedSession = task.session.id
        model.projects.projects = [project]; model.projects.selectedID = project.id
        model.navigation.projectTabs.select(.project(project.id)); model.projectNavigation = true
        model.spatial.sceneKind = .kitchen
        let agent = try #require(model.spatialWorld(showArchived: false).projects.first?.teams.first?.agents.first)
        model.spatial.focus = .agent(project: project.id, conversation: task.session.id, agent: agent.id, expanded: true)
        model.spatial.conversationPanelVisible = true; model.spatial.conversationWidth = 390
        let updates = AppUpdateCoordinator()
        updates.preview = true; updates.version = "0.9.0"; updates.phase = .available
        let host = NSHostingView(rootView: WorkspaceShell(library: model) { Text("Open project") }
            .overlayPreferenceValue(UpdateComposerAnchor.self) { AppUpdateOverlay(updates: updates, composer: $0) }
            .defaultAppStorage(defaults))
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { updates.confirmingRestart = false; window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded() }
        func capture(_ view: NSView, _ name: String) throws {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-update-\(name).png"))
        }
        try capture(host, "workspace")
        updates.phase = .ready; updates.requestRestart()
        for _ in 0..<10 where window.sheets.isEmpty { try await Task.sleep(for: .milliseconds(80)) }
        let sheet = try #require(window.sheets.first)
        try capture(try #require(sheet.contentView), "confirmation")
        updates.confirmingRestart = false
        try await Task.sleep(for: .milliseconds(150))
    }
    @Test func cardsRenderForScreenshotReview() async throws {
        for phase in [AppUpdateCoordinator.Phase.available, .downloading, .ready, .failed] {
            let updates = AppUpdateCoordinator()
            updates.preview = true; updates.version = "0.9.0"; updates.phase = phase
            updates.progress = phase == .downloading ? 0.42 : nil
            updates.detail = phase == .failed ? "The download was interrupted. Check your connection and try again." : ""
            let host = NSHostingView(rootView: AppUpdateCard(updates: updates).frame(width: 320).padding(28).background(Color(red: 0.94, green: 0.95, blue: 0.95)))
            host.frame = NSRect(x: 0, y: 0, width: 376, height: 250)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil; window.orderOut(nil) }
            for _ in 0..<3 { try await Task.sleep(for: .milliseconds(60)); host.layoutSubtreeIfNeeded() }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-update-\(phase).png"))
            #expect(host.fittingSize.height > 120)
        }
    }
}

private actor UpdateFixtureTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue> = AsyncStream { $0.finish() }
    let failShutdown: Bool
    var terminal = true
    var closed = false
    var turns = 0
    init(failShutdown: Bool) { self.failShutdown = failShutdown }
    func connect() {}
    func request(_ method: String, _ params: WireValue) throws -> WireValue {
        if method == "turn/start" { turns += 1; throw AppServerFailure("Must not start work") }
        if method == "thread/backgroundTerminals/terminate" {
            if failShutdown { throw AppServerFailure("Terminal stop failed") }
            terminal = false
        }
        if method == "thread/backgroundTerminals/list" {
            return .object(["data": .array(terminal ? [.object(["processId": .string("terminal")])] : [])])
        }
        return .object(["data": .array([])])
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() { closed = true }
}
