import AppKit
import ScreenCaptureKit
import SwiftUI
import DioramaCore

/// The development demo recording: `--record-demo <output folder>`, launched with
/// `CFFIXED_USER_HOME` pointing at a scratch home so the made-up projects never read or write
/// your real Diorama files. It plays a scripted run through Home and into a project's kitchen
/// in the real window, through the real key and click handling (so Home's and the kitchen's
/// sounds play), and records the window with its sound to `<output folder>/raw.mov`.
enum DemoMode {
    static let active = CommandLine.arguments.contains("--record-demo") || interactive
    /// The demo you drive yourself: no script, no recording (`DemoPlayground`).
    static let interactive = CommandLine.arguments.contains("--demo-interactive")
    /// The scratch home; the demo refuses to run against your real one.
    static var home: String? { ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] }
    /// "home" (Home, then into a kitchen), "kitchen" (a day in one kitchen: `--demo-scene kitchen`)
    /// or "office" (the same day in the office).
    static var scene: String {
        let arguments = CommandLine.arguments
        return arguments.firstIndex(of: "--demo-scene").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "home"
    }
    static var output: URL {
        let arguments = CommandLine.arguments
        let path = arguments.firstIndex(of: "--record-demo").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        return URL(fileURLWithPath: path ?? NSTemporaryDirectory())
    }

    /// A library holding only the demo's projects; it never starts discovery.
    @MainActor static func library() -> LibraryModel {
        guard let home else { return LibraryModel(navigation: WorkspaceNavigation(defaults: defaults, namespace: "demo")) }
        // Each run starts clean: no tabs, reviews or read marks left from the last one.
        UserDefaults.standard.removePersistentDomain(forName: "diorama.demo-recording")
        let library = LibraryModel(navigation: WorkspaceNavigation(defaults: defaults, namespace: "demo"))
        TaskLabels.shared.generator = nil
        let root = URL(fileURLWithPath: home).appendingPathComponent("Projects")
        let fixture = ["kitchen", "office", "gong"].contains(scene) && !interactive ? DemoFixture.kitchen(root: root)
            : scene == "reel" || interactive ? DemoFixture.reel(root: URL(fileURLWithPath: home).appendingPathComponent("Projects-reel")) : DemoFixture.make(root: root)
        for id in fixture.agents.keys { KitchenReviews.shared.clear(id) }
        library.demo = fixture
        library.projects.projects = fixture.projects
        library.sessions = fixture.sessions
        library.portfolio = PortfolioStore(cache: nil)
        let sunday = Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 1), matchingPolicy: .nextTime) ?? Date()
        library.portfolio.home.weekly = [.claude: LimitWindow(provider: .claude, usedPercent: 38, resetsAt: sunday, status: .ok, observedAt: Date()),
                                         .codex: LimitWindow(provider: .codex, usedPercent: 61, resetsAt: sunday.addingTimeInterval(-86_400 * 2), status: .ok, observedAt: Date())]
        library.portfolio.home.projectDays = fixture.projectDays
        library.portfolio.usages = fixture.usages
        AgentConnections.shared.showConnectedForDemo()
        GitHubConnection.shared.showConnectedForDemo(login: "northwind-labs")
        DemoLog().write("library ready: \(fixture.projects.count) projects, \(fixture.agents.count) agents")
        return library
    }
    /// The demo's tabs, layout, reviews and read marks stay out of the app's own settings.
    private static let defaults = UserDefaults(suiteName: "diorama.demo-recording") ?? .standard
    /// Settings shared stores use: the demo's own while recording, else the app's.
    static var sharedDefaults: UserDefaults { active ? defaults : .standard }
}

/// The demo window: the real project shell, a drawn pointer for the click, and the director.
struct DemoRecorderView: View {
    let library: LibraryModel
    @State private var director = DemoDirector()
    @State private var playing = false
    var body: some View {
        Group {
            if DemoMode.home == nil {
                Text("Launch the demo with CFFIXED_USER_HOME set to a scratch folder.").padding(40)
            } else {
                ProjectsRootView(library: library).focusedSceneValue(\.desktopLibrary, library)
            }
        }
        .onAppear { DemoLog().write("window content appeared") }
        .background(DemoWindowReader { window in
            guard DemoMode.home != nil else { return }
            if DemoMode.interactive {
                guard !playing else { return }
                playing = true
                DemoPlayground.start(window: window, library: library)
            } else { director.start(window: window, library: library) }
        })
    }
}

/// The drawn pointer, in its own see-through window over the demo window (and its sheets).
private struct DemoPointer: View {
    let director: DemoDirector
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let point = director.pointer {
                ZStack(alignment: .topLeading) {
                    Image(systemName: "cursorarrow").font(.system(size: 30, weight: .black)).foregroundStyle(.white).offset(x: -1, y: -1)
                    Image(systemName: "cursorarrow").font(.system(size: 26)).foregroundStyle(.black)
                }
                .scaleEffect(director.pressed ? 0.86 : 1, anchor: .topLeading)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .offset(x: point.x - 6, y: point.y - 4)
            }
        }
        .ignoresSafeArea().allowsHitTesting(false)
    }
}

/// Runs the script once the window exists.
@Observable @MainActor final class DemoDirector {
    /// The drawn pointer, in window points from the top left.
    var pointer: CGPoint?
    var pressed = false
    @ObservationIgnored private var started = false
    let log = DemoLog()
    @ObservationIgnored weak var currentLibrary: LibraryModel?

    func start(window: NSWindow, library: LibraryModel) {
        guard !started, let fixture = library.demo else { return }
        started = true
        currentLibrary = library
        Task { @MainActor in
            do { try await run(window: window, library: library, fixture: fixture) }
            catch { log.write("Failed: \(error)") }
            try? await Task.sleep(for: .milliseconds(400))
            if ProcessInfo.processInfo.environment["DIORAMA_DEMO_HOLD"] == nil {
                NSApp.terminate(nil)
                // An open sheet can hold termination up; the recording is already written.
                try? await Task.sleep(for: .seconds(3)); exit(0)
            }
        }
    }

    private func run(window: NSWindow, library: LibraryModel, fixture: DemoFixture) async throws {
        // A 16:9 window centred on the screen.
        // Shown over whatever is on screen, full-screen apps included, so it renders and records.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.setContentSize(NSSize(width: 1392, height: 783))
        window.center()
        NSApp.activate()
        // Launched from a shell, the app may not become active; order the window in over the
        // current Space (a full-screen app's included) anyway, or the capture records nothing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let pointerWindow = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pointerWindow.isOpaque = false; pointerWindow.backgroundColor = .clear; pointerWindow.hasShadow = false
        pointerWindow.ignoresMouseEvents = true
        pointerWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        pointerWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pointerWindow.contentView = NSHostingView(rootView: DemoPointer(director: self))
        pointerWindow.orderFront(nil)
        if DemoMode.scene == "kitchen" { try await kitchen(window: window, library: library, fixture: fixture); return }
        if DemoMode.scene == "office" { try await kitchen(window: window, library: library, fixture: fixture, scene: .office); return }
        if DemoMode.scene == "gong" { try await gong(window: window, library: library, fixture: fixture); return }
        if DemoMode.scene == "reel" { try await reel(window: window, library: library); return }

        // Warm up: open two projects so their tabs show and the target's kitchen is built and
        // its chefs are at their stations, quietly; then go Home.
        KitchenAudio.shared.muted = true
        library.selectProjectTab("demo-checkout-v2")
        try await pause(1.5)
        library.selectProjectTab(fixture.target.project)
        library.spatial.sceneKind = .kitchen
        try await pause(9)
        library.selectDesktopTab(.home)
        try await pause(2.5)
        window.makeKeyAndOrderFront(nil)

        guard #available(macOS 15.0, *) else { throw CocoaError(.featureUnsupported) }
        // Without screen recording permission the run still plays, for checking the script.
        var capture: DemoCapture?
        do { capture = try await DemoCapture.start(window: window, to: DemoMode.output.appendingPathComponent("raw.mov")) }
        catch { log.write("Not recording: \(error.localizedDescription)") }
        try await pause(0.4)
        let begin = Date()
        func at(_ seconds: Double) async throws { try await pause(max(0, seconds - Date().timeIntervalSince(begin))) }

        // Needs you → Recent projects → Needs review → Active (↑ wraps from the top).
        let script: [(Double, UInt16)] = [
            (0.9, 124),
            (1.8, 126), (2.5, 124), (3.1, 124), (3.7, 124),
            (4.5, 126), (5.2, 124), (5.9, 124),
            (6.7, 126), (7.4, 124), (8.1, 124), (8.8, 123), (9.3, 123),
        ]
        for (time, key) in script {
            try await at(time)
            press(key, in: window)
            log.write(String(format: "%.2f key %d", Date().timeIntervalSince(begin), key))
        }

        // The pointer glides to the target's row and clicks it.
        try await at(9.55)
        let row = rowCenter(in: window, title: "Rate Limiter") ?? CGPoint(x: 400, y: 302)
        log.write("row \(row)")
        let height = window.contentView?.bounds.height ?? 783
        pointer = CGPoint(x: row.x + 260, y: min(height - 40, row.y + 200))
        try await pause(0.05)
        withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.55)) { pointer = CGPoint(x: row.x + 40, y: row.y + 2) }
        try await at(10.25)
        KitchenAudio.shared.muted = false
        HomeSound.shared.select()
        withAnimation(.easeOut(duration: 0.08)) { pressed = true }
        click(CGPoint(x: row.x + 40, y: row.y + 2), in: window)
        log.write(String(format: "%.2f click", Date().timeIntervalSince(begin)))
        try await pause(0.12)
        withAnimation(.easeOut(duration: 0.12)) { pressed = false }
        try await pause(0.5)
        withAnimation(.easeOut(duration: 0.3)) { pointer = nil }

        try await at(12.9)
        try await capture?.stop()
        log.write(String(format: "%.2f stopped", Date().timeIntervalSince(begin)))
    }

    func pause(_ seconds: Double) async throws { try await Task.sleep(for: .milliseconds(Int(seconds * 1000))) }

    /// A key press, through the app's event queue like a real one.
    func press(_ code: UInt16, in window: NSWindow) {
        let scalar: Int = switch code { case 36: 13; case 49: 32; case 123: NSLeftArrowFunctionKey; case 124: NSRightArrowFunctionKey; case 125: NSDownArrowFunctionKey; default: NSUpArrowFunctionKey }
        let characters = String(Character(UnicodeScalar(UInt16(scalar))!))
        let flags: NSEvent.ModifierFlags = code == 36 || code == 49 ? [] : [.function, .numericPad]
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                            isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }
    /// A left click at a point in window coordinates from the top left.
    func click(_ point: CGPoint, in window: NSWindow) {
        let height = window.contentView?.bounds.height ?? 0
        let location = NSPoint(x: point.x, y: height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }
    /// Where a Home row is, found through the window's accessibility tree, in window points from the top left.
    func rowCenter(in window: NSWindow, title: String) -> CGPoint? {
        func search(_ element: Any, depth: Int) -> NSRect? {
            guard depth < 40 else { return nil }
            if let element = element as? NSAccessibilityElementProtocol & NSObjectProtocol,
               let label = (element as AnyObject).accessibilityLabel?() ?? nil, label.hasPrefix(title) {
                return (element as AnyObject).accessibilityFrame?()
            }
            let children = ((element as AnyObject).accessibilityChildren?() ?? nil) ?? []
            for child in children { if let found = search(child, depth: depth + 1) { return found } }
            return nil
        }
        guard let content = window.contentView, let frame = search(content, depth: 0) else { return nil }
        let inWindow = window.convertFromScreen(frame)
        return CGPoint(x: inWindow.minX + 24, y: content.bounds.height - inWindow.midY)
    }
}

/// Records the window and the app's own sound with ScreenCaptureKit.
@available(macOS 15.0, *)
final class DemoCapture: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    /// Around the window: a deep plum.
    private static let margin = CGColor(srgbRed: 0.13, green: 0.11, blue: 0.19, alpha: 1)
    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Never>?
    /// Told (on the main queue) when the system stops the stream on its own.
    var onSystemStop: (@MainActor () -> Void)?

    @MainActor static func start(window: NSWindow, to url: URL) async throws -> DemoCapture {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screen = window.screen ?? NSScreen.main!
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { throw CocoaError(.featureUnsupported) }
        // Only this process's windows (launched from a terminal it may not be listed as an application).
        let filter: SCContentFilter
        if let app = content.applications.first(where: { $0.processID == pid }) {
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, including: content.windows.filter { $0.owningApplication?.processID == pid })
        }
        DemoLog().write("Capturing \(content.windows.filter { $0.owningApplication?.processID == pid }.count) windows; listed as app: \(content.applications.contains { $0.processID == pid })")
        // The window with a margin around it, 16:9, top-left origin in display points.
        let frame = window.frame, margin = NSSize(width: (1512 - frame.width) / 2, height: (850.5 - frame.height) / 2)
        let rect = CGRect(x: frame.minX - screen.frame.minX - margin.width, y: screen.frame.maxY - frame.maxY - margin.height,
                          width: frame.width + margin.width * 2, height: frame.height + margin.height * 2)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = 3024; configuration.height = 1700
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = false
        configuration.backgroundColor = Self.margin
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = 48_000; configuration.channelCount = 2
        configuration.queueDepth = 8
        let capture = DemoCapture()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: capture)
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mov
        recording.videoCodecType = .hevc
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: capture))
        try await stream.startCapture()
        capture.stream = stream
        return capture
    }
    func stop() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream?.stopCapture { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
        // The file is complete once the recording output says so.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finished = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finish() }
        }
    }
    private func finish() { finished?.resume(); finished = nil }
    // ScreenCaptureKit calls these on its own queue.
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { DemoLog().write("Recording finished"); self.finish() }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let text = "\(error)"
        DispatchQueue.main.async { DemoLog().write("Recording failed: " + text); self.finish() }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let text = "\(error)"
        DispatchQueue.main.async { DemoLog().write("Stream stopped: " + text); self.onSystemStop?() }
    }
}

/// A take that keeps recording: when the system stops the stream, the next file starts at once
/// (raw.mov, raw2.mov, …) and the log says when, so the edit can stitch them.
@available(macOS 15.0, *)
@MainActor final class DemoTake {
    private let window: NSWindow
    private var capture: DemoCapture?
    private var part = 0
    private var stopping = false
    private let begin: () -> Double
    init(window: NSWindow, begin: @escaping () -> Double) { self.window = window; self.begin = begin }
    func start() async {
        guard !stopping else { return }
        part += 1
        let name = part == 1 ? "raw.mov" : "raw\(part).mov"
        do {
            let next = try await DemoCapture.start(window: window, to: DemoMode.output.appendingPathComponent(name))
            next.onSystemStop = { [weak self] in Task { await self?.start() } }
            capture = next
            DemoLog().write(String(format: "part %d (%@) started at %.2f", part, name, begin()))
        } catch { DemoLog().write("Couldn't record \(name): \(error.localizedDescription)") }
    }
    func stop() async {
        stopping = true
        try? await capture?.stop()
    }
}

/// What the run did and when, next to the recording.
struct DemoLog {
    func write(_ line: String) {
        let url = DemoMode.output.appendingPathComponent("demo.log")
        let text = Date().formatted(.iso8601) + " " + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// Hands the hosting window to the demo once it exists.
private struct DemoWindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void
    init(_ found: @escaping (NSWindow) -> Void) { self.found = found }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in if let window = view?.window { found(window) } }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in if let window = view?.window { found(window) } }
    }
}
