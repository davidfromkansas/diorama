import SwiftUI
import Testing
@testable import DioramaCore
@testable import DioramaApp

@MainActor struct ClaudeDesktopObservationTests {
    @Test func importedSelectionSurvivesDiscoveryReconciliation() {
        let model = LibraryModel()
        let other = Session(id: "other", provider: .claude, url: nil, sessionID: "other", title: "Other", project: "/other", modified: Date(), bytes: 0, archived: false, parentID: nil)
        var desktop = Session(id: "desktop", provider: .claude, url: nil, sessionID: "desktop", title: "Testing", project: "/desktop", modified: Date(), bytes: 0, archived: false, parentID: nil)
        desktop.origin = .claudeDesktop
        model.sessions = [other, desktop]
        model.selectedFolderID = WorkingFolder.group([other]).first?.id
        model.navigate(.imported(desktop.id))
        model.reconcileSelection()
        #expect(model.selectedID == desktop.id)
        #expect(model.selectedFolder?.path == desktop.project)
    }
    @Test func importedDesktopViewRendersWithoutComposer() throws {
        let model = LibraryModel()
        var session = Session(id: "desktop-fixture", provider: .claude, url: nil, sessionID: "desktop-fixture", title: "Desktop fixture", project: "/tmp", modified: Date(), bytes: 0, archived: false, parentID: nil)
        session.origin = .claudeDesktop
        #expect(session.sourceLabel == "Claude Code Desktop")
        #expect(ExecutionController.resumeUnavailableReason(session) != nil)
        // Even a stale owned-task record must take the observation-only UI branch.
        model.execution.tasks[session.sessionID] = ExecutedTask(id: session.sessionID, title: session.title, folder: session.project, attached: true)
        let view = ExecutionControls(library: model, session: session).frame(width: 600).background(Color.black).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/diorama-desktop-observation.png"))
        #expect(image.size.height < 100)
    }
}
