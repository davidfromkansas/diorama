import AppKit
import SwiftUI
import Testing
@testable import DioramaCore
@testable import DioramaApp

/// Opt-in native view/backend integration. This does not replace a manual UI walkthrough.
@MainActor struct ClaudeLivePresentationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_CLAUDE_PRESENTATION_LIVE"] == "1"))
    func realPlanningTurnSurvivesNativePresentationAndTeardown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-native-claude-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = AgentExecutionTransport()
        let controller = ExecutionController(transport: transport, journal: root.appendingPathComponent("owned.json"))
        var host: NSHostingView<AnyView>?
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; host = nil; window.orderOut(nil) }
        do {
            await controller.connect()
            try #require(controller.connected)
            await controller.loadModes()
            let id = try await controller.prepare(folder: root.path, title: "Native Claude presentation probe", model: "claude/sonnet")
            let session = Session(id: "Claude Code:" + id, provider: .claude, url: nil, sessionID: id, title: "Native Claude presentation probe", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
            let library = LibraryModel(execution: controller)
            library.sessions = [session]; library.selectedID = session.id
            library.transcriptSessionID = session.id; library.projectNavigation = true
            host = NSHostingView(rootView: AnyView(SessionView(session: session, model: library, hasLocalReview: true)))
            window.contentView = host
            host?.layoutSubtreeIfNeeded()
            try await controller.send(id: id, prompt: "Do not use tools, edit files, or use the network. Reply with three short planning steps for a garden landing page, beginning with NATIVE_PLAN_OK.", model: "claude/sonnet", mode: "plan")
            let deadline = Date().addingTimeInterval(75)
            var renderedUpdates = 0
            var recreations = 0
            var observedPhases: [String] = []
            while ![.finished, .failed, .disconnected].contains(controller.tasks[id]?.phase ?? .failed), Date() < deadline {
                let observed = controller.tasks[id]?.phase.rawValue ?? "missing"
                if observedPhases.last != observed { observedPhases.append(observed) }
                host?.layoutSubtreeIfNeeded()
                renderedUpdates += 1
                if renderedUpdates % 20 == 0 {
                    host?.rootView = AnyView(EmptyView())
                    host?.layoutSubtreeIfNeeded()
                    host?.rootView = AnyView(SessionView(session: session, model: library, hasLocalReview: true))
                    host?.layoutSubtreeIfNeeded()
                    recreations += 1
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            host?.layoutSubtreeIfNeeded()
            let phase = controller.tasks[id]?.phase
            let mode = controller.tasks[id]?.workflow.mode ?? ""
            let response = controller.tasks[id]?.transcript.entries.filter { $0.kind == "Assistant" }.map(\.text).joined(separator: "\n") ?? ""
            let evidence: [String: Any] = ["sessionID": id, "phase": phase?.rawValue ?? "missing", "mode": mode, "response": String(response.prefix(1500)), "renderedUpdates": renderedUpdates, "viewRecreations": recreations, "observedPhases": observedPhases, "manualUIWalkthrough": false]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/diorama-claude-native-presentation.json"))
            try #require(phase == .finished)
            #expect(response.contains("NATIVE_PLAN_OK"))
            #expect(mode == "plan")
            #expect(renderedUpdates > 0)
            #expect(!observedPhases.contains("Ready"))
            // Destroy native presentation closures after actual streamed snapshots.
            host?.rootView = AnyView(EmptyView()); host?.layoutSubtreeIfNeeded()
            window.contentView = nil; host = nil
            controller.tasks.removeAll()
            try await Task.sleep(for: .milliseconds(100))
            #expect(controller.tasks.isEmpty)
            await transport.shutdown()
        } catch {
            await transport.shutdown()
            throw error
        }
    }
}
