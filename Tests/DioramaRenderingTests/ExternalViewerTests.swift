import Foundation
import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ExternalViewerTests {
    private func model(_ root: URL) -> LibraryModel {
        LibraryModel(execution: ExecutionController(transport: PassiveViewerTransport()),
            projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")),
            conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")),
            observationHookDirectory: nil)
    }
    private func session(_ url: URL, id: String = "external") -> Session {
        Session(id: "Codex:" + id, provider: .codex, url: url, sessionID: id,
            title: "External observation fixture", project: url.deletingLastPathComponent().path,
            modified: Date(), bytes: 0, archived: false, parentID: nil)
    }
    private func append(_ data: String, _ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(data.utf8))
    }
    @Test func externalSceneWorksWithoutAttachmentAndExpires() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("task.jsonl")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try Data("{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn\"}}\n".utf8).write(to: url)
        let model = model(root), session = session(url)
        model.sessions = [session]; model.selectedID = session.id
        await model.readSelected()
        #expect(model.execution.tasks.isEmpty)
        #expect(model.workspaceAgents(session)[0].isWorking)
        #expect(model.workspaceAgents(session)[0].freshness == .recentlyObserved)
        model.observationClock = Date().addingTimeInterval(31)
        #expect(!model.workspaceAgents(session)[0].isWorking)
        model.observationClock = Date()
        model.paused = true
        #expect(!model.workspaceAgents(session)[0].isWorking)
    }
    @Test func watcherDeliversThirtyAppendsWithoutPolling() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("task.jsonl")
        try Data().write(to: url)
        let model = model(root), session = session(url)
        model.sessions = [session]; model.selectedID = session.id
        let watcher = DirectoryWatcher(paths: [root.path]) { Task { await model.readSelected() } }
        var latencies: [Double] = []
        for index in 0..<30 {
            let start = Date()
            try append("{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"event-\(index)\"}]}}\n", url)
            while model.transcript.entries.last?.text != "event-\(index)", Date().timeIntervalSince(start) < 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.transcript.entries.last?.text == "event-\(index)")
            latencies.append(Date().timeIntervalSince(start))
        }
        withExtendedLifetime(watcher) {}
        let sorted = latencies.sorted()
        print("EXTERNAL_VIEWER_FIXTURE updates=30 evidence_to_model_p95_ms=\(Int(sorted[28] * 1000)) max_ms=\(Int(sorted.last! * 1000))")
        #expect(sorted[28] <= 0.5)
        #expect(sorted.last! <= 1)
        #expect(model.execution.tasks.isEmpty)
    }
    // This exercises the real mounted conversation under incremental I/O. Layout
    // completion is deliberately not described as compositor/pixel presentation.
    @Test func thirtyAppendsWithMountedRichConversationMeetLayoutBudget() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("mounted.jsonl")
        let initial = (0..<200).map { index in
            #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"CommandExecution","id":"tool-"# + String(index) + #"","status":"completed","aggregatedOutput":"Recorded fixture output","exitCode":0}}}"#
        }.joined(separator: "\n") + "\n"
        try Data(initial.utf8).write(to: url)
        let model = model(root), session = session(url)
        model.sessions = [session]; model.selectedID = session.id
        model.viewMode = .conversation
        await model.readSelected()
        let host = NSHostingView(rootView: SessionView(session: session, model: model, hasLocalReview: true))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let watcher = DirectoryWatcher(paths: [root.path]) { Task { await model.readSelected() } }
        var timings: [Double] = []
        for index in 0..<30 {
            let marker = "mounted-\(index)", start = ContinuousClock.now
            try append("{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(marker)\"}]}}\n", url)
            while model.transcript.entries.last?.text != marker, start.duration(to: .now) < .seconds(2) {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.transcript.entries.last?.text == marker)
            host.layoutSubtreeIfNeeded()
            let duration = start.duration(to: .now).components
            timings.append(Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        }
        withExtendedLifetime(watcher) {}
        let sorted = timings.sorted()
        print("MOUNTED_VIEWER_FIXTURE updates=30 evidence_to_layout_p95_ms=\(Int(sorted[28] * 1000)) max_ms=\(Int(sorted.last! * 1000)) pixel_latency_measured=false")
        #expect(sorted[28] <= 0.5)
        #expect(sorted.last! <= 1)
        #expect(model.execution.tasks.isEmpty)
    }
    @Test func claudeCancellationStopsExternalSceneImmediately() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cancelled.jsonl")
        let date = ISO8601DateFormatter().string(from: Date())
        try Data("{\"type\":\"user\",\"timestamp\":\"\(date)\",\"message\":{\"content\":\"Read README\"}}\n".utf8).write(to: url)
        let session = Session(id: "Claude:cancel-scene", provider: .claude, url: url, sessionID: "cancel-scene", title: "Cancellation", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        let model = model(root)
        model.sessions = [session]; model.selectedID = session.id
        await model.readSelected()
        #expect(model.workspaceAgents(session)[0].isWorking)
        try append("{\"type\":\"user\",\"timestamp\":\"\(date)\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"[Request interrupted by user for tool use]\"}]}}\n", url)
        await model.readSelected()
        #expect(model.workspaceAgents(session)[0].status == .stopped)
        #expect(!model.workspaceAgents(session)[0].isWorking)
        #expect(model.execution.tasks.isEmpty)
    }
    @Test func claudeChildSharingSessionIDAppearsAndFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let parentURL = root.appendingPathComponent("parent.jsonl"), childURL = root.appendingPathComponent("agent-child.jsonl")
        let date = ISO8601DateFormatter().string(from: Date())
        let user = "{\"type\":\"user\",\"timestamp\":\"\(date)\",\"message\":{\"content\":\"Read README\"}}\n"
        try Data(user.utf8).write(to: parentURL)
        try Data(user.utf8).write(to: childURL)
        let parent = Session(id: "Claude Code:parent", provider: .claude, url: parentURL, sessionID: "parent", title: "Parent", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        var child = Session(id: "Claude Code:parent/agent-child", provider: .claude, url: childURL, sessionID: "parent", title: "Child", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: "parent")
        child.classification = .subagent
        let model = model(root)
        model.sessions = [parent]; model.selectedID = parent.id
        await model.readSelected()
        #expect(model.workspaceAgents(parent).count == 1)
        model.sessions.append(child)
        await model.readSelected()
        #expect(model.workspaceAgents(parent).count == 2)
        #expect(model.workspaceAgents(parent)[1].isWorking)
        try append("{\"type\":\"assistant\",\"timestamp\":\"\(date)\",\"message\":{\"stop_reason\":\"end_turn\",\"content\":[{\"type\":\"text\",\"text\":\"Done\"}]}}\n", childURL)
        await model.readSelected()
        #expect(model.workspaceAgents(parent)[1].status == .done)
        #expect(!model.workspaceAgents(parent)[1].isWorking)
    }

    @Test func switchedSelectionAndMissingSourceKeepCorrectHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("first.jsonl")
        try Data().write(to: url)
        let model = model(root), first = session(url)
        let missing = session(root.appendingPathComponent("missing.jsonl"), id: "missing")
        model.sessions = [first, missing]; model.selectedID = first.id
        let read = Task { await model.readSelected() }
        model.selectedID = missing.id
        await model.readSelected(); await read.value
        #expect(model.transcriptSessionID == missing.id)
        #expect(model.transcript.error != nil)
        #expect(model.execution.tasks.isEmpty)
    }
    @Test func pauseReconcilesMissedBurstWithoutDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("paused.jsonl")
        try Data().write(to: url)
        let model = model(root), session = session(url)
        model.sessions = [session]; model.selectedID = session.id
        await model.readSelected()
        model.paused = true
        for index in 0..<100 {
            try append("{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"burst-\(index)\"}]}}\n", url)
        }
        await model.readSelected()
        #expect(model.transcript.entries.isEmpty)
        let start = Date()
        model.paused = false
        await model.readSelected()
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(model.transcript.entries.count == 100)
        #expect(Set(model.transcript.entries.map(\.id)).count == 100)
        await model.readSelected()
        #expect(model.transcript.entries.count == 100)
        model.paused = true
        #expect(model.watcher == nil)
        #expect(model.execution.tasks.isEmpty)
    }

    @Test func twentySubagentsDoNotDelayParentUpdatesOrMoveDesks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let parentURL = root.appendingPathComponent("parent.jsonl")
        try Data().write(to: parentURL)
        let parent = session(parentURL, id: "parent"), model = model(root)
        model.sessions = [parent]; model.selectedID = parent.id
        for index in 0..<20 {
            let url = root.appendingPathComponent("child-\(index).jsonl")
            try Data().write(to: url)
            var child = Session(id: "Codex:child-\(index)", provider: .codex, url: url, sessionID: "child-\(index)", title: "Child \(index)", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: "parent")
            child.classification = .subagent
            model.sessions.append(child)
        }
        await model.readSelected()
        let ids = model.workspaceAgents(parent).map(\.id)
        #expect(ids.count == 21)
        try append(#"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"parent update"}]}}"# + "\n", parentURL)
        let start = Date()
        await model.readSelected()
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(model.transcript.entries.last?.text == "parent update")
        #expect(model.workspaceAgents(parent).map(\.id) == ids)
        #expect(model.execution.tasks.isEmpty)
    }

}

private actor PassiveViewerTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    func connect() { Issue.record("Viewer must not connect execution") }
    func request(_ method: String, _ params: WireValue) -> WireValue {
        Issue.record("Viewer sent execution request: \(method)"); return .null
    }
    func respond(id: WireValue, result: WireValue) { Issue.record("Viewer sent approval") }
    func reject(id: WireValue, message: String) { Issue.record("Viewer rejected approval") }
    func shutdown() {}
}
