import AppKit
import SwiftUI
import DioramaCore

/// The reel (`--demo-scene reel`), recorded in real time (about a minute) and cut to about 35 s
/// with `scripts/demo-edit.py`: a live kitchen; a new task and its cook riding the elevator in;
/// planning; Home → Active → a third project in a new tab; cooking and stove close-ups; the
/// pantry (a connector's blender, a skill's jar) and the live tools bar; Home → Needs you; the
/// gong and an answer; tasting, the pass, a merge, and the break room.
extension DemoDirector {
    func reel(window: NSWindow, library: LibraryModel) async throws {
        guard let fixture = library.demo else { return }
        // Conversations by agent name (names are unique across the reel's projects).
        var ids: [String: String] = [:]
        for (id, values) in fixture.agents { if let name = values.first?.name { ids[name] = id } }
        func id(_ name: String) -> String { ids[name] ?? "" }
        func project(_ conversation: String) -> String {
            String(conversation[..<(conversation.lastIndex(of: "-") ?? conversation.endIndex)])
        }
        func identity(_ conversation: String) -> String {
            SpatialAgent.identity(project: project(conversation), conversation: conversation,
                                  provider: library.demo?.agents[conversation]?.first?.provider ?? "", agent: "main")
        }
        func update(_ name: String, _ change: (inout WorkspaceAgent) -> Void) {
            let conversation = id(name)
            guard var value = library.demo?.agents[conversation]?.first else { return }
            change(&value)
            value.meaningfulUpdatedAt = Date(); value.observedAt = Date()
            library.demo?.agents[conversation] = [value]
            library.demoRevision += 1
        }
        func use(_ name: String, tool: String, detail: String = "", edits: Bool = false) {
            update(name) {
                $0.status = .working; $0.attentionReason = .other; $0.reportedStatus = "Working"
                $0.latestTool = tool; $0.latestToolDetail = detail; $0.turnHasEdits = edits; $0.lastToolAt = Date()
                $0.completionKey = id(name) + "." + tool + "." + String(Int(Date().timeIntervalSince1970 * 10))
            }
        }
        func select(_ name: String, panel: Bool) {
            let conversation = id(name)
            library.navigate(.project(project(conversation), conversation))
            library.spatial.focus = .agent(project: project(conversation), conversation: conversation, agent: identity(conversation), expanded: panel)
            library.spatial.conversationPanelVisible = panel
        }
        func deselect() {
            guard let current = library.spatial.focus.projectID else { return }
            library.spatial.focus = .project(current)
            library.spatial.conversationPanelVisible = false
        }
        func openList(_ projectID: String) { library.spatial.roster(for: projectID).collapsed = false }
        func kitchen() -> KitchenSceneView? { kitchenView(in: window) }
        func clickChef(_ name: String, panel: Bool) async throws {
            if let point = chefPoint(id(name), in: window) {
                try await glide(to: point, in: window, duration: 0.4)
                tap(point, in: window)
            }
            select(name, panel: panel)
        }
        /// Text dropped into a modal's answer field in one go, as a paste does (the field is a
        /// plain text view; the conversation composers are skipped).
        func paste(_ text: String) {
            func editor(_ view: NSView) -> NSTextView? {
                if let field = view as? NSTextView, !(field is ComposerNSTextView), field.isEditable, !view.isHiddenOrHasHiddenAncestor { return field }
                for child in view.subviews { if let found = editor(child) { return found } }
                return nil
            }
            let windows = [window.attachedSheet, window].compactMap { $0 }
            guard let host = windows.first(where: { $0.contentView.flatMap(editor) != nil }), let field = host.contentView.flatMap(editor) else { log.write("No field to paste into"); return }
            host.makeFirstResponder(field)
            field.insertText(text, replacementRange: field.selectedRange())
        }

        let atlas = "demo-atlas-api", insights = "demo-insights-dashboard", checkout = "demo-checkout-v2"
        // Making a task: a made-up conversation joins the project; its cook rides the elevator in.
        library.demoCreate = { [weak library] projectID, prompt in
            guard let library else { return "" }
            let conversation = projectID + "-new"
            var agent = DemoFixture.a("Pixel", .claude, "Add SSO login with Okta", .research("Sources/Auth/SessionController.swift"), minutes: 0)
            agent.feed = [(.started, "Started from your request", "")]
            let folder = library.projects.projects.first { $0.id == projectID }?.folder ?? ""
            library.demo?.agents[conversation] = [DemoFixture.agentValue(agent, id: conversation, updated: Date())]
            library.demo?.models[conversation] = agent.model
            var transcript = Transcript()
            transcript.entries = [.demo("n1", "You", prompt),
                                  .demo("n2", "Assistant", "Got it. I'll start by reading how sessions are created today, then plan the Okta OIDC flow, the callback route and the admin settings.")]
            library.demo?.transcripts[conversation] = transcript
            library.sessions.append(.demo(id: conversation, provider: .claude, title: "Add SSO login with Okta", folder: folder, modified: Date()))
            ids["Pixel"] = conversation
            library.demoRevision += 1
            return conversation
        }
        // Answering a question: your reply joins the conversation and the cook goes back to work.
        library.demoSend = { [weak library] session, text in
            guard let library, let name = library.demo?.agents[session.id]?.first?.name else { return }
            library.demo?.transcripts[session.id]?.entries.append(.demo("a1", "You", text))
            library.demo?.transcripts[session.id]?.entries.append(.demo("a2", "Assistant", "Perfect. Showing Apple Pay on desktop Safari too, behind the same flag. Building and running the checkout tests."))
            library.demo?.questions[session.id] = nil
            if let transcript = library.demo?.transcripts[session.id] { library.transcript = transcript; library.transcriptSessionID = session.id }
            use(name, tool: "Bash", detail: "npm run build:checkout")
        }

        // Warm up out of frame: every kitchen built and settled; only Atlas API's tab is left.
        KitchenAudio.shared.muted = true
        for projectID in [checkout, insights, atlas] {
            library.selectProjectTab(projectID)
            library.spatial.sceneKind = .kitchen
            openList(projectID)
            try await pause(4)
        }
        library.closeProjectTab(checkout); library.closeProjectTab(insights)
        library.selectProjectTab(atlas)
        deselect()
        try await pause(5)
        KitchenAudio.shared.muted = false

        guard #available(macOS 15.0, *) else { throw CocoaError(.featureUnsupported) }
        let started = Date()
        var beginAt: Date?
        let take = DemoTake(window: window) { Date().timeIntervalSince(beginAt ?? started) }
        await take.start()
        try await pause(2.2)
        let begin = Date()
        beginAt = begin
        log.write(String(format: "begin %.3f after capture start", begin.timeIntervalSince(started)))
        func at(_ seconds: Double) async throws { try await pause(max(0, seconds - Date().timeIntervalSince(begin))) }
        func mark(_ what: String) { log.write(String(format: "%.2f %@", Date().timeIntervalSince(begin), what)) }

        // 1. The whole kitchen, live: cooks change jobs and the list follows.
        mark("kitchen")
        try await at(0.6); use("Max", tool: "Edit", detail: "Sources/Telemetry/LatencyHistogram.swift", edits: true)
        try await at(1.4); use("Rex", tool: "mcp__sentry__search_issues")
        try await at(2.2); use("Eli", tool: "TodoWrite")

        // 2. Create: the list's button, the task pasted in, Create; the new cook steps out and waves.
        try await at(3.0)
        if try await pressButton("Create agent", window: window) { mark("create") }
        try await at(4.0)
        library.projects.update(atlas) { $0.draft = "Add SSO login with Okta for enterprise workspaces: OIDC sign-in, a callback route, and an admin toggle per workspace." }
        mark("pasted")
        try await at(4.7)
        if try await pressButton("Create", window: window) { mark("created") }
        try await at(5.6); hidePointer()

        // 3. Let go; glide over the prep counter where cooks read and plan.
        try await at(10.0)
        deselect()
        try await at(10.3)
        kitchen()?.focusCamera(on: SIMD2(3.4, -6.6), zoom: 2.3); mark("prep")
        try await at(12.6)
        kitchen()?.resetCamera()

        // 4. Home: Needs you is empty, Active has the work; the third project opens in a new tab.
        try await at(13.2)
        library.selectDesktopTab(.home); mark("home")
        try await at(14.0); press(126, in: window)
        try await at(14.6); press(125, in: window)
        try await at(15.3); press(124, in: window)
        try await at(15.9); press(124, in: window)
        try await at(16.7); press(49, in: window); mark("open insights")
        try await at(17.4); openList(insights); deselect()

        // 5. Cooking and stove up close; then a cook from each, with all three panels.
        try await at(17.6)
        kitchen()?.focusCamera(on: SIMD2(0, -0.6), zoom: 2.0); mark("cooking and stove")
        try await at(20.8)
        try await clickChef("Zoe", panel: true); mark("zoe")
        try await at(23.0)
        try await clickChef("Bea", panel: true); mark("bea")
        try await at(25.2)
        hidePointer(); deselect(); kitchen()?.resetCamera()

        // 6. The pantry: one cook fetches a connector (the blender), another a skill (the jar);
        // the tools bar lights up.
        try await at(25.6)
        use("Ruby", tool: "mcp__github__create_pull_request")
        use("Felix", tool: "Skill", detail: "frontend-design"); mark("pantry trips")
        try await at(26.4)
        try await clickChef("Ruby", panel: false); mark("follow ruby")
        try await at(31.0)
        use("Ruby", tool: "Edit", detail: "app/widgets/RevenueByPlan.tsx", edits: true)
        use("Felix", tool: "Edit", detail: "app/onboarding/Charts.tsx", edits: true); mark("carry")
        try await at(34.0)
        hidePointer(); deselect(); kitchen()?.resetCamera()
        try await at(34.6)
        use("Cal", tool: "mcp__figma__get_design_context"); mark("tools bar")
        try await at(36.0)
        use("Hana", tool: "mcp__claude_ai_Slack__send_message")

        // 7. Someone needs you: Home opens on Needs you; its Answer button goes straight there.
        try await at(37.6)
        update("Priya") {
            $0.status = .waiting; $0.attentionReason = .input; $0.reportedStatus = "waitingForInput"
            $0.latestTool = ""; $0.completionKey = id("Priya") + ".ask"
        }
        library.demo?.questions[id("Priya")] = "Should Apple Pay also show on desktop Safari, or only on mobile?"
        library.demo?.contexts[id("Priya")] = "The Apple Pay button works on iOS Safari and passes merchant validation."
        library.demo?.transcripts[id("Priya")]?.entries.append(.demo("q1", "Assistant", "The Apple Pay button works on iOS Safari and passes merchant validation. Should it also show on desktop Safari, or only on mobile?"))
        try await at(38.4)
        library.selectDesktopTab(.home); mark("home needs you")
        try await at(39.8)
        if try await pressButton("Answer", window: window) { mark("answer card") }
        else { press(49, in: window); mark("answer with space") }
        try await at(41.0)
        hidePointer(); deselect(); openList(checkout)

        // 8. The gong: she reaches it and strikes it; you answer and she gets back to work.
        try await at(46.4)
        try await clickChef("Priya", panel: true); mark("priya")
        try await at(47.4)
        if try await pressButton("Review request", window: window) { mark("review request") }
        try await at(48.4)
        paste("Yes, show it on desktop Safari too, behind the same feature flag.")
        try await at(49.2)
        if try await pressButton("Send answer", window: window) { mark("answered") }
        try await at(50.6)
        hidePointer(); deselect()

        // 9. Tasting, then the dish at the pass; merge it, and its cook heads for a break.
        try await at(51.0)
        kitchen()?.focusCamera(on: SIMD2(10.4, -2.0), zoom: 2.4); mark("tasting")
        try await at(53.2)
        kitchen()?.resetCamera()
        update("Maya") {
            $0.status = .done; $0.reportedStatus = "Done"; $0.completionKey = id("Maya") + ".done"
        }
        select("Maya", panel: false); mark("maya done")
        try await at(62.0)
        if try await pressButton("Review", window: window) { mark("review") }
        try await at(63.2)
        if try await pressButton("Merge into main", window: window) { mark("merge") }
        try await at(73.5)
        hidePointer()
        try await at(74.0)
        await take.stop()
        mark("stopped")
    }
}
