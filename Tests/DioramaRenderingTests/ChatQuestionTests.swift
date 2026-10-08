import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ChatQuestionTests {
    /// Opt-in render of the request modal's answer-a-chat-question layout.
    @Test func captureChatQuestion() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_MODAL_CAPTURE"] == "1" else { return }
        let session = AppServerHistory.session(["id": "c", "cwd": "/tmp/kitchen-demo", "name": "Use the GitHub connector to list the 5 most recent PRs", "threadSource": "user"], archived: false)!
        let view = VStack(spacing: 0) {
            ModalHeader(group: .needsYou, title: TaskTitle.full(session.displayTitle), status: "Needs an answer", model: "GPT-6 Astra", question: true) {}
            ChatQuestionContent(question: "What GitHub repository URL or `owner/name` should I use?",
                                context: "This local repository is named `kitchen-demo`, but has no Git remote configured, and the GitHub connector found no matching repository. Nothing was changed.",
                                session: session, library: LibraryModel()) {
                Text("Open conversation").font(.system(size: 12)).foregroundStyle(SidebarStyle.accent)
            } done: {}
        }
        .reviewModalSurface()
        .padding(20).background(Color(red: 0.3, green: 0.2, blue: 0.14))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-chat-question.png"))
    }
}
