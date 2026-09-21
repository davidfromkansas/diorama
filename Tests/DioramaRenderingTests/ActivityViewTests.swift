import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ActivityViewTests {
    func session(_ id: String, classification: SessionClassification = .conversation) -> Session {
        var result = Session(id: id, provider: .codex, url: URL(fileURLWithPath: "/test/\(id).jsonl"), sessionID: id,
                             title: id, project: "/test", modified: Date(), bytes: 0, archived: false, parentID: nil)
        result.classification = classification; return result
    }
    @Test func filtersCountsSelectionAndInboxIgnoreReviews() throws {
        let model = LibraryModel()
        let main = session("main"), review = session("review", classification: .internalReview), child = session("child", classification: .subagent)
        let e = ActivityEvent(id: "request", provider: "Codex", sessionID: "main", kind: "approval", source: "fixture", state: .approval)
        model.sessions = [main, review, child]
        model.activity = [main.id: .init(events: [e]), review.id: .init(events: [e]), child.id: .init(events: [ActivityEvent(id: "start", provider: "Codex", sessionID: "child", kind: "started", source: "fixture", state: .working)])]
        let folder = try #require(model.folders.first)
        #expect(model.attentionSessions.count == 1)
        #expect(model.counts(folder).contains("conversations: 0 working · 1 attention"))
        #expect(model.counts(folder).contains("Subagents: 1 working · 0 attention"))
        model.selectedFolderID = folder.id; model.selectedID = main.id
        model.activityFilter = "Working"; model.selectFolderSession()
        #expect(model.selectedID == child.id)
        model.openAttention(main)
        #expect(model.selectedID == main.id); #expect(model.activityFilter == "All"); #expect(model.viewMode == .activity)
        model.paused = true; #expect(model.health == "Paused")
    }
    @Test func activityBadgeRendering() throws {
        let event = ActivityEvent(id: "sample", provider: "Codex", sessionID: "s", kind: "approval", source: "Hook", state: .approval)
        let view = VStack(alignment: .leading, spacing: 18) {
            Text("Diorama · Activity").font(.title2)
            ActivityBadge(summary: .init(events: [event]))
            Text("Resolution unverified · respond in the source client").font(.caption).foregroundStyle(.orange)
        }.padding(24).frame(width: 520).background(Color(white: 0.12)).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-activity-preview.png"))
    }
    @Test func watcherSeesNewSessionFile() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-watch-\(UUID())")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        var received = false
        let watcher = DirectoryWatcher(paths: [path.path]) { received = true }
        try Data("test".utf8).write(to: path.appendingPathComponent("new.jsonl"))
        for _ in 0..<30 {
            if received { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        withExtendedLifetime(watcher) { #expect(received) }
    }
}
