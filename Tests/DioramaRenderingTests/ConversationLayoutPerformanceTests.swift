import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ConversationLayoutPerformanceTests {
    @Test func startingAndStreamingKeepsProjectConversationResponsive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let execution = ExecutionController()
        var task = ExecutedTask(id: "layout-fixture", title: "Layout fixture", folder: root.path, attached: true)
        task.transcript.entries = (0..<500).map {
            Entry(id: "message-\($0)", kind: $0 % 2 == 0 ? "You" : "Assistant",
                  text: String(repeating: "A conversation message with **formatting**, wrapping text and a [link](https://example.com).\n\n", count: 4), timestamp: nil)
        }
        if let path = ProcessInfo.processInfo.environment["DIORAMA_LAYOUT_TRANSCRIPT"] {
            task.transcript = SessionLibrary.readTranscript(url: URL(fileURLWithPath: path), provider: .codex, limit: 500)
            #expect(task.transcript.error == nil)
            print("Read-only layout fixture entries: \(task.transcript.entries.count)")
        }
        execution.tasks[task.id] = task
        let session = task.session
        let model = LibraryModel(execution: execution, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")))
        model.sessions = [session]; model.selectedID = session.id; model.transcriptSessionID = session.id
        model.projectNavigation = true
        var project = DioramaProject(name: "Fixture", folder: root.path, commonDirectory: root.path, base: "main", remote: nil)
        project.selectedSession = session.id
        model.projects.projects = [project]
        let key = project.id + ":" + session.id
        model.navigation.tabs[key] = .conversation
        let host = NSHostingView(rootView: GeometryReader { _ in
            ProjectWorkbench(projectID: project.id, library: model)
        })
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        var timings: [Duration] = []
        for phase in [ExecutionPhase.submitting, .working, .approval, .working, .finished] {
            timings.append(ContinuousClock().measure {
                execution.tasks[task.id]?.phase = phase
                execution.tasks[task.id]?.transcript.entries.append(Entry(id: UUID().uuidString, kind: "Assistant", text: "Streaming update.", timestamp: nil))
                host.layoutSubtreeIfNeeded()
            })
            try await Task.sleep(for: .milliseconds(20))
        }
        let worst = try #require(timings.max())
        print("Conversation transition worst layout: \(worst)")
        #expect(worst < .seconds(1), "Starting and streaming must not monopolize the UI thread")
        model.navigation.tabs[key] = .workspace
        host.layoutSubtreeIfNeeded()
        model.navigation.tabs[key] = .conversation
        host.layoutSubtreeIfNeeded()
    }
}
