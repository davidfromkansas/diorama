import Foundation
import Observation
import os
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct WorkspacePerformanceTests {
    @Test func disclosureDoesNotInvalidatePaneObserversOrWriteDuringTheClick() async throws {
        let suite = "diorama-disclosure-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let navigation = WorkspaceNavigation(defaults: defaults)
        let paneInvalidations = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = navigation.layout.sidebarVisible; _ = navigation.layout.sidebarWidth
            _ = navigation.layout.inspectorVisible; _ = navigation.layout.inspectorWidth
            _ = navigation.layout.inspector; _ = navigation.layout.destination
        } onChange: { paneInvalidations.withLock { $0 += 1 } }
        let elapsed = ContinuousClock().measure {
            for index in 0..<100 { navigation.layout.collapsedProjects.insert("project-\(index)") }
        }
        #expect(paneInvalidations.withLock { $0 } == 0)
        #expect(defaults.data(forKey: "workspaceLayout.v1") == nil)
        #expect(elapsed < .milliseconds(100), "Disclosure mutations must stay comfortably below a click's perceptible delay")
        await navigation.waitForPendingPersistence()
        let restored = WorkspaceNavigation(defaults: defaults)
        #expect(restored.layout.collapsedProjects.count == 100)
        print("100 disclosure mutations: \(elapsed); unrelated pane invalidations: 0")
    }

    @Test func projectMembershipCacheTracksLibraryAssociationAndWorktreeChanges() throws {
        let model = ProjectModel(storageURL: URL(fileURLWithPath: "/tmp/missing-" + UUID().uuidString))
        let library = LibraryModel(projects: model)
        var project = DioramaProject(name: "Project", folder: "/project", commonDirectory: "/project/.git", base: "main", remote: nil)
        func session(_ id: String, folder: String) -> Session {
            Session(id: id, provider: .codex, url: nil, sessionID: id, title: id, project: folder,
                    modified: .distantPast, bytes: 0, archived: false, parentID: nil)
        }
        library.sessions = [session("main", folder: "/project"), session("linked", folder: "/linked"), session("other", folder: "/other")]
        #expect(model.sessions(project, library: library).map(\.id) == ["main"])
        model.associations["/linked"] = project.commonDirectory
        #expect(model.sessions(project, library: library).map(\.id) == ["main", "linked"])
        project.workspaces = [ProjectWorkspace(id: "work", folder: "/other", branch: "codex/work", baseCommit: "abc", context: .init())]
        #expect(model.sessions(project, library: library).count == 3)
        library.sessions.removeFirst()
        #expect(model.sessions(project, library: library).map(\.id) == ["linked", "other"])
        project.workspaces = []; model.associations = [:]
        #expect(model.sessions(project, library: library).isEmpty)
    }

    @Test func cachedProjectLookupDoesNotRescanLargeLibrary() {
        let model = ProjectModel(storageURL: URL(fileURLWithPath: "/tmp/missing-" + UUID().uuidString))
        let library = LibraryModel(projects: model)
        let project = DioramaProject(name: "Project", folder: "/project", commonDirectory: "/project/.git", base: "main", remote: nil)
        library.sessions = (0..<20_000).map { index in
            Session(id: "s\(index)", provider: .codex, url: nil, sessionID: "s\(index)", title: "Session \(index)",
                project: index < 10 ? "/project" : "/unrelated/\(index)", modified: .distantPast, bytes: 0, archived: false, parentID: nil)
        }
        #expect(model.sessions(project, library: library).count == 10)
        let elapsed = ContinuousClock().measure {
            for _ in 0..<100 { _ = model.sessions(project, library: library) }
        }
        #expect(elapsed < .milliseconds(100))
        print("100 cached membership lookups across 20,000 sessions: \(elapsed)")
    }
}

extension WorkspacePerformanceTests {
    @Test func projectDisclosureUpdatesNativeLayoutWithinOneInteractionBudget() async throws {
        let suite = "diorama-click-layout-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ProjectModel(storageURL: URL(fileURLWithPath: "/tmp/missing-" + UUID().uuidString))
        let navigation = WorkspaceNavigation(defaults: defaults)
        let library = LibraryModel(projects: model, navigation: navigation)
        let project = DioramaProject(name: "Project", folder: "/project", commonDirectory: "/project/.git", base: "main", remote: nil)
        library.sessions = (0..<20_000).map { index in
            Session(id: "s\(index)", provider: .codex, url: nil, sessionID: "s\(index)", title: "Session \(index)",
                project: index < 100 ? "/project" : "/unrelated/\(index)", modified: .distantPast, bytes: 0, archived: false, parentID: nil)
        }
        let host = NSHostingView(rootView: ScrollView { WorkspaceProjectGroup(project: project, library: library, showArchived: false) })
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 650)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        var timings: [Duration] = []
        for _ in 0..<10 {
            timings.append(ContinuousClock().measure {
                navigation.layout.collapsedProjects.insert(project.id)
                host.layoutSubtreeIfNeeded()
            })
            timings.append(ContinuousClock().measure {
                navigation.layout.collapsedProjects.remove(project.id)
                host.layoutSubtreeIfNeeded()
            })
        }
        let worst = try #require(timings.max())
        #expect(worst < .milliseconds(100), "Native disclosure layout should not visibly stall with a large imported library")
        print("20 native disclosure layouts with 20,000 imported sessions: median \(timings.sorted()[10]), worst \(worst)")
        window.orderOut(nil)
        await navigation.waitForPendingPersistence()
    }
}
