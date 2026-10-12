import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

/// A provider fixture: both accounts connected, a Claude model without effort levels and an OpenAI
/// model with them.
private actor ModelsTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    func connect() {}
    func request(_ method: String, _ params: WireValue) throws -> WireValue {
        switch method {
        case "diorama/connections": return .object(["codex": .bool(true), "claude": .bool(true)])
        case "model/list": return .object(["data": .array([
            .object(["model": .string("claude/opus"), "displayName": .string("Opus 5.5"), "isDefault": .bool(true)]),
            .object(["model": .string("gpt-astra"), "displayName": .string("GPT-6-Astra"),
                     "supportedReasoningEfforts": .array([.object(["reasoningEffort": .string("low")]), .object(["reasoningEffort": .string("high")])])]),
        ])])
        case "turn/start": throw AppServerFailure("Fixture must never start a turn")
        default: return .object([:])
        }
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}

/// Records what the panel asks for; the conversation can't be read, so connecting fails.
private actor UnreachableTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    private(set) var methods: [String] = []
    func connect() {}
    func request(_ method: String, _ params: WireValue) throws -> WireValue {
        methods.append(method)
        switch method {
        case "diorama/connections": return .object(["codex": .bool(true), "claude": .bool(true)])
        case "thread/read": throw AppServerFailure("Provider unreachable")
        case "turn/start", "thread/resume": throw AppServerFailure("Fixture must never start or claim a turn")
        default: return .object([:])
        }
    }
    func respond(id: WireValue, result: WireValue) {}
    func reject(id: WireValue, message: String) {}
    func shutdown() {}
}

@MainActor struct IMessageComposerTests {
    @Test func openingADetachedConversationConnectsItAndReportsFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = UnreachableTransport()
        let controller = ExecutionController(transport: transport)
        // As restored after a relaunch: detached and idle, with the mode last set in Diorama.
        var task = ExecutedTask(id: "restored", title: "Restored", folder: root.path, parentID: nil, phase: .disconnected)
        task.permissionPreference = .user
        controller.tasks[task.id] = task
        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")))
        model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        let host = NSHostingView(rootView: AnyView(
            SessionView(session: task.session, model: model, hasLocalReview: true, shellContent: true, embeddedWorkScreen: true)
                .environment(\.avatarMessages, true).environment(\.colorScheme, .light)))
        host.frame = NSRect(x: 0, y: 0, width: 410, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(60)); host.layoutSubtreeIfNeeded() }
        #expect(await transport.methods.contains("thread/read"), "Opening the conversation connects it")
        #expect(controller.resumeErrors["restored"] == "Provider unreachable")
        #expect(controller.tasks["restored"]?.attached == false && controller.tasks["restored"]?.error == nil)
        window.contentView = nil
    }

    /// Permissions never block Send (unset, a message goes out in your Codex or Claude default):
    /// only a change that didn't apply asks for attention.
    @Test func permissionsOnlyAskForAttentionWhenAChangeDidNotApply() {
        func picker(policy: WireValue = .null, stale: Bool = false, unconfirmed: Bool = false, notice: String? = nil, lastKnown: ApprovalReviewChoice? = nil) -> ApprovalReviewPicker {
            ApprovalReviewPicker(selection: .constant(.inherit), reviewer: "user", policy: policy,
                                 sandbox: .object(["type": .string("workspaceWrite")]), stale: stale, unconfirmed: unconfirmed,
                                 notice: notice, capsule: true, lastKnown: lastKnown)
        }
        #expect(!picker(policy: .string("on-request")).unsettled, "Connected with reported settings")
        #expect(!picker(stale: true, lastKnown: .user).unsettled, "Connecting, showing the last known mode")
        #expect(!picker(stale: true).unsettled, "Connecting, nothing known yet")
        #expect(!picker(policy: .string("on-request"), unconfirmed: true).unsettled, "Not yet confirmed: sending still uses your default")
        #expect(picker(policy: .string("on-request"), notice: "Changed").unsettled, "A change that didn't apply")
        #expect(!picker().unsettled, "Nothing reported: your provider default")
    }

    @Test func planGoalAndQueueKeepTheirRules() {
        var mode = "default", goal = false, queue = false
        let modeBinding = Binding(get: { mode }, set: { mode = $0 })
        let goalBinding = Binding(get: { goal }, set: { goal = $0 })
        let queueBinding = Binding(get: { queue }, set: { queue = $0 })
        ComposerModeToggles.goal(mode: modeBinding, goal: goalBinding, queue: queueBinding).wrappedValue = true
        #expect(goal && mode == "default")
        // Plan and goal exclude each other; a goal isn't queued.
        ComposerModeToggles.plan(mode: modeBinding, goal: goalBinding).wrappedValue = true
        #expect(mode == "plan" && !goal)
        ComposerModeToggles.queue(goal: goalBinding, queue: queueBinding).wrappedValue = true
        ComposerModeToggles.goal(mode: modeBinding, goal: goalBinding, queue: queueBinding).wrappedValue = true
        #expect(goal && !queue && mode == "default")
    }

    @Test func theComposerAndTheHeaderShareTheModelChoice() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = LibraryModel(execution: ExecutionController(transport: MessagesFixtureTransport()),
                                 projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")))
        let session = Session(id: "Codex:s", provider: .codex, url: nil, sessionID: "s", title: "T", project: "/", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let choices = model.composerChoices(session)
        choices.model = "gpt-astra"
        #expect(model.composerChoices(session) === choices && model.composerChoices(session).model == "gpt-astra")
    }

    @Test func theModelCapsuleNamesTheModelAndItsEffortOnlyWhenItHasOne() async {
        let controller = ExecutionController(transport: ModelsTransport())
        _ = await controller.onboardingSnapshot()
        #expect(controller.models.map(\.id) == ["claude/opus", "gpt-astra"])
        let choices = ComposerChoices()
        func label(_ effective: String, effort: String = "") -> String {
            HeaderModelMenu(controller: controller, choices: choices, effectiveModel: effective, effectiveEffort: effort).label
        }
        #expect(label("claude/opus") == "Opus 5.5")
        #expect(label("gpt-astra") == "GPT-6-Astra · Default")
        #expect(label("gpt-astra", effort: "low") == "GPT-6-Astra · Low")
        choices.model = "gpt-astra"; choices.effort = "high"
        #expect(label("claude/opus") == "GPT-6-Astra · High")
    }

    @Test func theLoaderStaysStillUnderReduceMotion() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        let still = LoaderLayers.View(kind: .ripple)
        still.frame = NSRect(x: 0, y: 0, width: 78, height: 30)
        window.contentView = still
        still.layoutSubtreeIfNeeded()
        #expect(still.layer?.sublayers?.allSatisfy { ($0.animationKeys() ?? []).isEmpty } == true)
        still.animated = true; still.layoutSubtreeIfNeeded()
        #expect(still.layer?.sublayers?.contains { !($0.animationKeys() ?? []).isEmpty } == true)
        window.contentView = nil
    }

    /// The conversation panel as the kitchen shows it, header included.
    private func panel(width: CGFloat) async throws -> (NSHostingView<AnyView>, LibraryModel, Session) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = ExecutionController(transport: ModelsTransport())
        _ = await controller.onboardingSnapshot()
        var task = ExecutedTask(id: "imessage-fixture", title: "Boss chef", folder: root.path, turnID: "turn", attached: true)
        task.phase = .finished; task.model = "claude/opus"
        task.transcript.entries = (0..<40).map { index in
            Entry(id: "e\(index)", kind: index.isMultiple(of: 2) ? "You" : "Assistant", text: "Message \(index) about the boss chef's animations.", timestamp: "2026-10-01T12:\(String(format: "%02d", index)):00Z")
        }
        controller.tasks[task.id] = task
        let model = LibraryModel(execution: controller, projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")))
        model.sessions = [task.session]; model.selectedID = task.session.id
        model.transcriptSessionID = task.session.id; model.viewMode = .conversation; model.paused = true
        let header = AvatarHeaderInfo(name: "Felix", task: "Boss Chef Animation", taskDetail: "Animate the boss chef", branch: "animate-model-similar-chefs-in-addition", close: {})
        let host = NSHostingView(rootView: AnyView(
            SessionView(session: task.session, model: model, hasLocalReview: true, shellContent: true, embeddedWorkScreen: true)
                .environment(\.avatarMessages, true).environment(\.avatarHeader, header)
                .environment(\.colorScheme, .light).tint(.blue).background(.white)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<6 { try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded() }
        return (host, model, task.session)
    }
    private func editors(_ view: NSView) -> [ComposerNSTextView] { (view as? ComposerNSTextView).map { [$0] } ?? view.subviews.flatMap(editors) }

    @Test(arguments: [340.0, 410.0, 700.0]) func thePanelFitsEveryWidthItCanBe(width: Double) async throws {
        let (host, _, _) = try await panel(width: width)
        let editor = try #require(editors(host).first)
        #expect(host.bounds.contains(editor.convert(editor.bounds, to: host)))
        #expect(editor.enclosingScrollView!.frame.height <= 128)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-imessage-\(Int(width)).png"))
        host.window?.contentView = nil
    }

    @Test func typingNeverRebuildsTheTranscript() async throws {
        let (host, model, session) = try await panel(width: 410)
        let editor = try #require(editors(host).first)
        let before = model.conversationPresentation.rows(for: session.id).revision
        for character in "Make the boss chef point at the stove while he talks." { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
        for _ in 0..<3 { try await Task.sleep(for: .milliseconds(30)); host.layoutSubtreeIfNeeded() }
        #expect(model.conversationPresentation.rows(for: session.id).revision == before)
        host.window?.contentView = nil
    }
}
