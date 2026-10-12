import AppKit
import SwiftUI
import DioramaCore

/// The demo you drive yourself (`--demo-interactive`): the reel's made-up portfolio in a normal
/// window, no script and no recording. Creating a task and answering a question work on made-up
/// conversations, and keyboard shortcuts set off what you can't by hand: someone needing you (the
/// gong), a dish finishing, a pantry run (keys in `DemoPlaygroundKeys`). Nothing reaches Codex, Claude or GitHub.
@MainActor enum DemoPlayground {

    /// Opens on Atlas API's kitchen with the agent list showing.
    static func start(window: NSWindow, library: LibraryModel) {
        install(library)
        DemoPlaygroundKeys.install(library)
        window.setContentSize(NSSize(width: 1392, height: 783))
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        library.selectProjectTab("demo-atlas-api")
        library.spatial.sceneKind = .kitchen
        library.spatial.roster(for: "demo-atlas-api").collapsed = false
    }

    /// Stand-ins for creating a task and answering a question.
    static func install(_ library: LibraryModel) {
        library.demoCreate = { [weak library] projectID, prompt in
            guard let library else { return "" }
            let conversation = projectID + "-new-" + String(Int(Date().timeIntervalSince1970))
            let names = ["Pixel", "Juno", "Atlas", "Remy", "Skye", "Milo", "Nora", "Otis"]
            let taken = Set((library.demo?.agents.values.compactMap { $0.first?.name }) ?? [])
            let name = names.first { !taken.contains($0) } ?? "Remy"
            let title = TaskTitle.compact(prompt.isEmpty ? "New task" : prompt)
            let agent = DemoFixture.a(name, .claude, title, .research("README.md"), minutes: 0)
            let folder = library.projects.projects.first { $0.id == projectID }?.folder ?? ""
            library.demo?.agents[conversation] = [DemoFixture.agentValue(agent, id: conversation, updated: Date())]
            library.demo?.models[conversation] = agent.model
            var transcript = Transcript()
            transcript.entries = [.demo("n1", "You", prompt),
                                  .demo("n2", "Assistant", "Got it. I'll read the code involved first, then plan the change and get to work.")]
            library.demo?.transcripts[conversation] = transcript
            library.sessions.append(.demo(id: conversation, provider: .claude, title: title, folder: folder, modified: Date()))
            library.demoRevision += 1
            return conversation
        }
        library.demoSend = { [weak library] session, text in
            guard let library else { return }
            library.demo?.transcripts[session.id, default: Transcript()].entries.append(.demo("y" + UUID().uuidString, "You", text))
            library.demo?.transcripts[session.id]?.entries.append(.demo("r" + UUID().uuidString, "Assistant", "Thanks, that settles it. Picking it back up now."))
            library.demo?.questions[session.id] = nil
            if let transcript = library.demo?.transcripts[session.id] { library.transcript = transcript; library.transcriptSessionID = session.id }
            update(library, session.id) {
                $0.status = .working; $0.attentionReason = .other; $0.reportedStatus = "Working"
                $0.latestTool = "Bash"; $0.latestToolDetail = "npm run build"; $0.turnHasEdits = false
            }
        }
    }

    // MARK: The Demo menu

    /// A working agent in the project you're looking at asks you something: it heads for the gong.
    static func needsYou(_ library: LibraryModel) {
        guard let id = pick(library, where: { $0.status == .working && $0.latestTool == "Bash" }) ?? pick(library, where: { $0.status == .working }) else { return }
        let question = questions.randomElement() ?? questions[0]
        library.demo?.questions[id] = question.ask
        library.demo?.contexts[id] = question.context
        library.demo?.transcripts[id, default: Transcript()].entries.append(.demo("q" + UUID().uuidString, "Assistant", question.context + " " + question.ask))
        update(library, id) {
            $0.status = .waiting; $0.attentionReason = .input; $0.reportedStatus = "waitingForInput"; $0.latestTool = ""
        }
    }
    /// An agent testing its work finishes: it carries its dish to the pass.
    static func finishTask(_ library: LibraryModel) {
        guard let id = pick(library, where: { agent in agent.status == .working && ["test", "playwright", "pytest"].contains { agent.latestToolDetail.contains($0) } })
                ?? pick(library, where: { $0.status == .working }) else { return }
        update(library, id) { $0.status = .done; $0.reportedStatus = "Done" }
    }
    /// One agent fetches a connector (the blender) and another a skill (the jar).
    static func pantryRun(_ library: LibraryModel) {
        let connectors = ["mcp__github__create_pull_request", "mcp__linear__create_issue", "mcp__claude_ai_Slack__send_message", "mcp__sentry__search_issues", "mcp__figma__get_design_context"]
        let skills = ["frontend-design", "pdf", "webapp-testing"]
        if let id = pick(library, where: { $0.status == .working && $0.turnHasEdits }) {
            let tool = connectors.randomElement() ?? connectors[0]
            update(library, id) { $0.latestTool = tool; $0.latestToolDetail = ""; $0.turnHasEdits = false }
        }
        if let id = pick(library, where: { $0.status == .working && !$0.turnHasEdits && !$0.latestTool.hasPrefix("mcp__") }) {
            let skill = skills.randomElement() ?? skills[0]
            update(library, id) { $0.latestTool = "Skill"; $0.latestToolDetail = skill }
        }
    }
    /// Everyone fetching from the pantry goes back to cooking.
    static func backToWork(_ library: LibraryModel) {
        for (id, values) in library.demo?.agents ?? [:] where values.first.map({ $0.latestTool.hasPrefix("mcp__") || $0.latestTool == "Skill" }) == true && inCurrentProject(library, id) {
            update(library, id) { $0.latestTool = "Edit"; $0.latestToolDetail = "src/index.ts"; $0.turnHasEdits = true }
        }
    }

    // MARK: Helpers

    private static let questions: [(ask: String, context: String)] = [
        ("Should this also ship on desktop, or mobile only?", "The change works on mobile and the tests pass."),
        ("Charge VAT on EU B2B orders too, or only B2C?", "VAT rates are in for all 27 EU countries."),
        ("Keep the old endpoint for a deprecation window, or remove it now?", "The new endpoint is live behind a flag."),
        ("Retry failed webhooks for 24 hours or 72 hours?", "The retry queue and backoff are in."),
    ]
    private static func inCurrentProject(_ library: LibraryModel, _ conversation: String) -> Bool {
        guard let project = library.spatial.focus.projectID ?? library.projects.selectedID else { return true }
        return conversation.hasPrefix(project + "-")
    }
    /// A random agent in the current project matching `test`.
    private static func pick(_ library: LibraryModel, where test: (WorkspaceAgent) -> Bool) -> String? {
        (library.demo?.agents ?? [:]).filter { id, values in values.first.map(test) == true && inCurrentProject(library, id) }.keys.randomElement()
    }
    private static func update(_ library: LibraryModel, _ conversation: String, _ change: (inout WorkspaceAgent) -> Void) {
        guard var value = library.demo?.agents[conversation]?.first else { return }
        change(&value)
        value.meaningfulUpdatedAt = Date(); value.observedAt = Date(); value.lastToolAt = Date()
        value.completionKey = conversation + "." + String(Int(Date().timeIntervalSince1970 * 10))
        library.demo?.agents[conversation] = [value]
        library.demoRevision += 1
    }
}

/// The demo's moments, on keys: ⌃⌥1 someone needs you, ⌃⌥2 a dish finishes, ⌃⌥3 a pantry run,
/// ⌃⌥4 back to cooking.
@MainActor final class DemoPlaygroundKeys {
    static var monitor: Any?
    static func install(_ library: LibraryModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak library] event in
            guard let library, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: [.control, .option]) else { return event }
            switch event.charactersIgnoringModifiers {
            case "1": DemoPlayground.needsYou(library)
            case "2": DemoPlayground.finishTask(library)
            case "3": DemoPlayground.pantryRun(library)
            case "4": DemoPlayground.backToWork(library)
            default: return event
            }
            return nil
        }
    }
}
