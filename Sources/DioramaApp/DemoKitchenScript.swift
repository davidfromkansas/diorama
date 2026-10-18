import AppKit
import SwiftUI
import DioramaCore

/// The kitchen demo (`--demo-scene kitchen`), about 16 s: a new cook steps out of the elevator and
/// waves; the camera pulls back on a full kitchen; a cook strikes the gong and you answer it, so
/// it changes course; you review a finished dish and send its cook to the break room; and you
/// drop an idle cook in the trash. `--demo-scene office` plays the same day in the office (the
/// desk bell instead of the gong, a deliverable instead of a dish, the lounge).
extension DemoDirector {
    func kitchen(window: NSWindow, library: LibraryModel, fixture: DemoFixture, scene: SceneKind = .kitchen) async throws {
        let project = fixture.target.project
        let sam = "demo-atlas-api-1", jade = "demo-atlas-api-7", ben = "demo-atlas-api-12", pixel = "demo-atlas-api-new"
        func identity(_ conversation: String) -> String {
            let provider = library.demo?.agents[conversation]?.first?.provider ?? ""
            return SpatialAgent.identity(project: project, conversation: conversation, provider: provider, agent: "main")
        }
        func update(_ conversation: String, _ change: (inout WorkspaceAgent) -> Void) {
            guard var value = library.demo?.agents[conversation]?.first else { return }
            change(&value)
            library.demo?.agents[conversation] = [value]
            library.demoRevision += 1
        }
        func select(_ conversation: String, panel: Bool) {
            library.navigate(.project(project, conversation))
            library.spatial.focus = .agent(project: project, conversation: conversation, agent: identity(conversation), expanded: panel)
            library.spatial.conversationPanelVisible = panel
        }
        func deselect() {
            library.spatial.focus = .project(project)
            library.spatial.conversationPanelVisible = false
        }

        // Warm up out of frame: the kitchen is built and every cook is at its station, quietly.
        KitchenAudio.shared.muted = true
        library.selectProjectTab("demo-checkout-v2")
        try await pause(1)
        library.setScene(scene, project: project)
        library.selectProjectTab(project)
        library.spatial.sceneKind = scene
        deselect()
        try await pause(10)
        KitchenAudio.shared.muted = false

        guard #available(macOS 15.0, *) else { throw CocoaError(.featureUnsupported) }
        var capture: DemoCapture?
        do { capture = try await DemoCapture.start(window: window, to: DemoMode.output.appendingPathComponent("raw.mov")) }
        catch { log.write("Not recording: \(error.localizedDescription)") }
        // Starting the capture briefly takes the kitchen out of view; a cook added in the next
        // moment would skip the elevator. This lead-in is trimmed from the video.
        let started = Date()
        try await pause(2.2)
        let begin = Date()
        log.write(String(format: "begin %.3f after capture start", begin.timeIntervalSince(started)))
        func at(_ seconds: Double) async throws { try await pause(max(0, seconds - Date().timeIntervalSince(begin))) }
        func mark(_ what: String) { log.write(String(format: "%.2f %@", Date().timeIntervalSince(begin), what)) }

        // 1. A new cook takes the elevator up, steps out and waves, the camera on it.
        let session = Session.demo(id: pixel, provider: .claude, title: DemoFixture.arrival.title, folder: library.projects.projects.first { $0.id == project }?.folder ?? "", modified: Date())
        library.demo?.agents[pixel] = [DemoFixture.agentValue(DemoFixture.arrival, id: pixel, updated: Date())]
        library.demo?.models[pixel] = DemoFixture.arrival.model
        library.sessions.append(session)
        library.demoRevision += 1
        mark("arrival")
        try await at(0.25)
        select(pixel, panel: false)

        // 2. Meanwhile a cook needs an answer: it heads for the gong (a long walk) and strikes it.
        try await at(0.8)
        update(sam) {
            $0.status = .waiting; $0.attentionReason = .input; $0.reportedStatus = "waitingForInput"
            $0.completionKey = sam + ".ask"; $0.meaningfulUpdatedAt = Date(); $0.latestTool = ""; $0.latestToolDetail = ""
        }
        library.demo?.questions[sam] = "Retry failed webhooks for 24 hours or 72 hours?"
        library.demo?.transcripts[sam]?.entries.append(.demo("w3", "Assistant", "Backoff is in. One decision before I wire the alert: should failed webhooks keep retrying for 24 hours or 72 hours?"))
        mark("gong")

        // 3. Let go of the new cook: the whole kitchen, every station busy, the agent list on the left.
        try await at(3.0)
        library.spatial.roster(for: project).collapsed = false
        deselect(); mark("overview")

        // 4. Click it: its panels open with the question; answer, and it changes course.
        try await at(6.6)
        if try await pressButton("Retry Failed Webhooks", window: window, prefix: true) { mark("row sam") }
        try await pause(0.2)
        if library.spatial.focus.conversationID != sam || !library.spatial.conversationPanelVisible { select(sam, panel: true); mark("select sam") }
        try await at(7.5)
        hidePointer()
        library.demoSend = { [weak library] session, text in
            guard let library, session.id == sam else { return }
            library.demo?.transcripts[sam]?.entries.append(.demo("w4", "You", text))
            library.demo?.transcripts[sam]?.entries.append(.demo("w5", "Assistant", "72 hours it is, then I'll page on-call. Running the retry tests now."))
            if let transcript = library.demo?.transcripts[sam] { library.transcript = transcript; library.transcriptSessionID = sam }
            update(sam) {
                $0.status = .working; $0.attentionReason = .other; $0.reportedStatus = "Working"
                $0.latestTool = "Bash"; $0.latestToolDetail = "swift test --filter WebhookRetryTests"
                $0.completionKey = sam + ".answered"; $0.meaningfulUpdatedAt = Date()
            }
            library.demo?.questions[sam] = nil
        }
        guard let editor = composer(in: window) else { log.write("No composer"); return }
        window.makeFirstResponder(editor)
        for character in "72 hours, then page on-call" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            try await pause(0.03)
        }
        try await at(8.7)
        editor.sendMessage?(); mark("sent")

        // 5. A finished dish at the pass: open its review and mark it done; its cook celebrates
        // and heads for the break room.
        try await at(9.8)
        if let point = chefPoint(jade, in: window) { try await glide(to: point, in: window, duration: 0.45); tap(point, in: window) }
        select(jade, panel: false); mark("select jade")
        try await at(10.4)
        if try await pressButton("Review", window: window) { mark("review") }
        try await at(11.3)
        if try await pressButton("Mark done", window: window) { mark("mark done") }
        try await at(11.9)
        deselect()

        // 6. Pick an idle cook up from the break room and drop it in the trash.
        try await at(12.2)
        if let from = chefPoint(ben, in: window), let kitchen = kitchenView(in: window) {
            let frame = kitchen.convert(kitchen.bounds, to: nil)
            let height = window.contentView?.bounds.height ?? 0
            let trash = CGPoint(x: frame.maxX - 62, y: height - frame.maxY + 62)
            try await glide(to: from, in: window, duration: 0.4)
            try await carry(identity(ben), from: from, to: trash, kitchen: kitchen, window: window, duration: 0.85)
            mark("trash")
        }
        try await at(15.1)
        hidePointer()
        try await at(15.8)
        try await capture?.stop()
        mark("stopped")
    }

    /// A short clip (`--demo-scene gong`): the camera close on the gong, a cook that needs an
    /// answer runs over, strikes it and waits in front of it, and the head chef comes in to talk.
    func gong(window: NSWindow, library: LibraryModel, fixture: DemoFixture) async throws {
        let project = fixture.target.project, sam = "demo-atlas-api-1"
        KitchenAudio.shared.muted = true
        library.setScene(.kitchen, project: project)
        library.selectProjectTab(project)
        library.spatial.sceneKind = .kitchen
        library.spatial.focus = .project(project); library.spatial.conversationPanelVisible = false
        try await pause(10)
        kitchenView(in: window)?.focusCamera(on: SIMD2(0.8, 5.4), zoom: 2.2)
        try await pause(2)
        KitchenAudio.shared.muted = false
        guard #available(macOS 15.0, *) else { throw CocoaError(.featureUnsupported) }
        var capture: DemoCapture?
        do { capture = try await DemoCapture.start(window: window, to: DemoMode.output.appendingPathComponent("raw.mov")) }
        catch { log.write("Not recording: \(error.localizedDescription)") }
        let started = Date()
        func mark(_ what: String) { log.write(String(format: "%.2f %@", Date().timeIntervalSince(started), what)) }
        try await pause(1.5)
        guard var value = library.demo?.agents[sam]?.first else { log.write("No cook"); return }
        value.status = .waiting; value.attentionReason = .input; value.reportedStatus = "waitingForInput"
        value.completionKey = sam + ".ask"; value.meaningfulUpdatedAt = Date(); value.latestTool = ""; value.latestToolDetail = ""
        library.demo?.agents[sam] = [value]
        library.demo?.questions[sam] = "Retry failed webhooks for 24 hours or 72 hours?"
        library.demoRevision += 1
        mark("asks")
        // Until the head chef has talked with it for a while.
        var talkingSince: Date?
        while Date().timeIntervalSince(started) < 30 {
            try await pause(0.1)
            let talking = kitchenView(in: window)?.managerTalking != nil
            if talking, talkingSince == nil { talkingSince = Date(); mark("talking") }
            if let since = talkingSince, Date().timeIntervalSince(since) > 3 { break }
        }
        try await capture?.stop()
        mark("stopped")
    }

    // MARK: Pointer and input

    /// A chef's position in window points from the top left.
    func chefPoint(_ conversation: String, in window: NSWindow) -> CGPoint? {
        guard let library = currentLibrary, let kitchen = kitchenView(in: window),
              let provider = library.demo?.agents[conversation]?.first?.provider,
              let point = kitchen.windowPoint(ofAgent: SpatialAgent.identity(project: library.demo?.target.project, conversation: conversation, provider: provider, agent: "main"))
        else { return nil }
        return CGPoint(x: point.x, y: (window.contentView?.bounds.height ?? 0) - point.y)
    }
    func kitchenView(in window: NSWindow) -> DioramaSceneView? {
        func find(_ view: NSView) -> DioramaSceneView? {
            if let kitchen = view as? DioramaSceneView, kitchen.window != nil, !kitchen.isHiddenOrHasHiddenAncestor { return kitchen }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        return window.contentView.flatMap(find)
    }
    func glide(to point: CGPoint, in window: NSWindow, duration: Double) async throws {
        if pointer == nil {
            let height = window.contentView?.bounds.height ?? 783
            pointer = CGPoint(x: min(point.x + 220, 1300), y: min(point.y + 160, height - 30))
            try await pause(0.03)
        }
        withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: duration)) { pointer = point }
        try await pause(duration)
    }
    func hidePointer() { withAnimation(.easeOut(duration: 0.25)) { pointer = nil } }
    /// The drawn pointer's press; `send` also clicks there for real (the kitchen's own clicks
    /// are made directly, since a click on a chef's name tag opens its progress instead).
    func tap(_ point: CGPoint, in window: NSWindow, send: Bool = false) {
        withAnimation(.easeOut(duration: 0.08)) { pressed = true }
        if send { click(point, in: window) }
        Task { @MainActor in try? await pause(0.14); withAnimation(.easeOut(duration: 0.12)) { pressed = false } }
    }
    /// Presses a button by its title (in the window or its sheet), the pointer gliding to it first.
    func pressButton(_ title: String, window: NSWindow, prefix: Bool = false) async throws -> Bool {
        func search(_ element: Any, depth: Int) -> (NSAccessibilityElementProtocol & NSObjectProtocol)? {
            guard depth < 50 else { return nil }
            let object = element as AnyObject
            if (object.accessibilityRole?() ?? nil) == .button,
               [(object.accessibilityLabel?() ?? nil), (object.accessibilityTitle?() ?? nil)].contains(where: { $0.map { prefix ? $0.hasPrefix(title) : $0 == title } ?? false }),
               let found = element as? NSAccessibilityElementProtocol & NSObjectProtocol { return found }
            for child in ((object.accessibilityChildren?() ?? nil) ?? []) { if let found = search(child, depth: depth + 1) { return found } }
            return nil
        }
        let windows = [window.attachedSheet, window].compactMap { $0 }
        for candidate in windows {
            guard let content = candidate.contentView, let button = search(content, depth: 0) else { continue }
            let frame = (button as AnyObject).accessibilityFrame?() ?? .zero
            let inWindow = window.convertFromScreen(frame)
            let height = window.contentView?.bounds.height ?? 0
            try await glide(to: CGPoint(x: inWindow.midX, y: height - inWindow.midY), in: window, duration: 0.45)
            withAnimation(.easeOut(duration: 0.08)) { pressed = true }
            _ = (button as AnyObject).accessibilityPerformPress?()
            try await pause(0.14)
            withAnimation(.easeOut(duration: 0.12)) { pressed = false }
            return true
        }
        log.write("No button titled \(title)")
        return false
    }
    /// Press, hold, carry and let go, as a person drags a chef.
    func drag(from: CGPoint, to: CGPoint, in window: NSWindow, duration: Double) async throws {
        let height = window.contentView?.bounds.height ?? 0
        func post(_ type: NSEvent.EventType, _ point: CGPoint) {
            if let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x, y: height - point.y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        withAnimation(.easeOut(duration: 0.08)) { pressed = true }
        post(.leftMouseDown, from)
        try await pause(0.35)
        let steps = 30
        for step in 1...steps {
            let t = Double(step) / Double(steps), eased = t * t * (3 - 2 * t)
            let point = CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
            pointer = point
            post(.leftMouseDragged, point)
            try await pause(duration / Double(steps))
        }
        try await pause(0.25)
        post(.leftMouseUp, to)
        withAnimation(.easeOut(duration: 0.12)) { pressed = false }
    }
    /// The visible conversation's composer.
    func composer(in window: NSWindow) -> ComposerNSTextView? {
        func find(_ view: NSView) -> ComposerNSTextView? {
            guard !view.isHiddenOrHasHiddenAncestor else { return nil }
            if let editor = view as? ComposerNSTextView { return editor }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        return window.contentView.flatMap(find)
    }
    /// Picks a chef up, carries it along with the pointer and lets go.
    func carry(_ id: String, from: CGPoint, to: CGPoint, kitchen: DioramaSceneView, window: NSWindow, duration: Double) async throws {
        let height = window.contentView?.bounds.height ?? 0
        func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: height - point.y) }
        withAnimation(.easeOut(duration: 0.08)) { pressed = true }
        try await pause(0.25)
        kitchen.demoPickUp(id, at: flipped(from))
        let steps = 36
        for step in 1...steps {
            let t = Double(step) / Double(steps), eased = t * t * (3 - 2 * t)
            let point = CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased - sin(.pi * t) * 60)
            pointer = point
            kitchen.demoCarry(to: flipped(point))
            try await pause(duration / Double(steps))
        }
        try await pause(0.3)
        kitchen.demoDrop()
        withAnimation(.easeOut(duration: 0.12)) { pressed = false }
    }
    /// Types one character into whatever has the keyboard.
    func type(_ character: Character, in window: NSWindow) {
        let text = String(character)
        for kind in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }
}
