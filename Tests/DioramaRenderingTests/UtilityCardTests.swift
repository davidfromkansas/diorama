import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct UtilityCardTests {
    private func thread(_ id: String, _ agent: String, _ title: String, _ excerpt: String, unread: Bool, minutes: Double) -> InboxThread {
        InboxThread(id: id, project: "p", conversation: id, title: title, agent: agent, excerpt: excerpt,
                    date: Date().addingTimeInterval(-minutes * 60), received: false, outcome: "completed", attachments: 0, unread: unread, updates: [])
    }

    @Test func inboxRowsKeepTheirAccessibleSummary() {
        let row = InboxThreadRow(thread: thread("1", "Sage", "Add stats dashboard", "Which colour theme?", unread: true, minutes: 2))
        let host = NSHostingView(rootView: row.frame(width: 360))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height >= 56)
    }

    /// Opt-in render of the kitchen's light pills and inbox rows, for comparing with the mockups.
    @Test func captureUtilityPillsAndInbox() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_UTILITY_CAPTURE"] == "1" else { return }
        let view = VStack(alignment: .trailing, spacing: 24) {
            HStack(alignment: .top) {
                AgentSidebarPill(summary: .init(active: 3, needsYou: 1, done: 1)) { _ in }
                Spacer()
                UtilityPill {
                    UtilitySegment(symbol: "server.rack", count: 2, label: "servers", selected: false, action: {}) { UtilityStatusDot(live: true) }
                    UtilityPillDivider()
                    UtilitySegment(symbol: "tray", label: "Inbox", selected: true, action: {}) { UtilityBadge(count: 3) }
                }
            }
            VStack(spacing: 0) {
                UtilityCardBand(title: "Unread", count: 2, tint: SidebarStyle.tint(.inProgress))
                InboxThreadRow(thread: thread("1", "Sage", "Add stats dashboard", "Which colour theme should the dashboard use?", unread: true, minutes: 2))
                InboxThreadRow(thread: thread("2", "Opal", "Update app icon", "Done: 4 files changed, tests passed.", unread: true, minutes: 14))
                UtilityCardBand(title: "Earlier", tint: SidebarStyle.tint(.idle))
                InboxThreadRow(thread: thread("3", "Eli", "Improve search", "Switched the index to trigram matching.", unread: false, minutes: 60))
            }
            .frame(width: 360).utilityCard(open: true)
            .overlay(alignment: .topLeading) { SidebarCornerButton(grow: false) {}.offset(x: -14, y: -14) }
        }
        .padding(24).frame(width: 760).background(Color(red: 0.48, green: 0.31, blue: 0.2)).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-utility-cards.png"))
    }

    /// Opt-in render of the selected chef's command bar in the light style.
    @Test func captureCommandBar() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_UTILITY_CAPTURE"] == "1" else { return }
        let agent = SpatialAgent(projectID: "p", conversationID: "c", value: WorkspaceAgent(id: "a", name: "Sage", provider: "Codex",
            task: "Build a settings page with a General section", action: "Editing", status: .working, reportedStatus: "working", freshness: .live, observedAt: Date()))
        let bar = AgentCommandBar(agent: agent, library: LibraryModel(), review: {}, close: {}).frame(width: 880)
        let host = NSHostingView(rootView: bar)
        host.frame = NSRect(x: 0, y: 0, width: 880, height: AgentCommandBar.height)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-command-bar.png"))
    }
}
