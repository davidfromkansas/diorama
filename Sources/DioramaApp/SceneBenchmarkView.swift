import SwiftUI
import SceneKit
import DioramaCore

/// Explicit diagnostic entry point; never substitutes fixtures in the normal workspace.
struct SceneBenchmarkView: View {
    var withInbox = false
    var withRoster = false
    var allFinished = false
    var mixedLeisure = false
    @State private var inboxExpanded = true
    @State private var inboxSelection: InboxThread?
    @State private var run = SceneBenchmarkRun()
    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if withRoster {
                    LiveAgentRosterPanel(model: run.roster, agents: [], active: true, paused: false, open: { _ in }).frame(width: 300)
                }
                SceneBenchmarkSurface(run:run, withInbox:withInbox, withRoster:withRoster, allFinished:allFinished, mixedLeisure:mixedLeisure)
            }
            if let model = run.inboxModel {
                VStack { Spacer(); HStack { Spacer(); ProjectInboxView(model: model, project: "fixture", height: 460,
                    expanded: $inboxExpanded, selected: $inboxSelection, reply: { _ in }, canReply: { _ in false }).frame(width: 400) } }.padding(16)
            }
            Text(run.status).font(.system(.caption,design:.monospaced)).padding(12).background(.regularMaterial).padding()
        }.frame(minWidth:1080,minHeight:780)
    }
}
private struct SceneBenchmarkSurface: NSViewRepresentable {
    let run: SceneBenchmarkRun
    let withInbox: Bool
    let withRoster: Bool
    let allFinished: Bool
    let mixedLeisure: Bool
    func makeCoordinator() -> SceneBenchmarkRun { run }
    func makeNSView(context: Context) -> SpatialSceneView {
        let view=SpatialSceneView()
        Task { if withInbox { await run.prepareInbox() }; await run.capture(view, withRoster: withRoster, allFinished: allFinished, mixedLeisure: mixedLeisure) }
        return view
    }
    func updateNSView(_ view: SpatialSceneView, context: Context) {}
    static func dismantleNSView(_ view: SpatialSceneView, coordinator: SceneBenchmarkRun) { coordinator.cancelled = true; view.tearDown() }
}
@Observable @MainActor private final class SceneBenchmarkRun {
    var status = "Preparing native frame capture…"
    var inboxModel: ProjectInboxModel?
    let roster = LiveAgentRosterModel()
    var cancelled = false
    private var fixtureDirectory: URL?
    func prepareInbox() async {
        status = "Preparing 10,000 inbox threads…"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DioramaInboxBenchmark-" + UUID().uuidString)
        fixtureDirectory = directory
        let store = ProjectInboxStore(directory: directory), now = Date()
        do {
            for i in 0..<10_000 {
                try await store.ingest(project: "fixture", conversation: "thread-\(i)", title: "Project deliverable \(i)",
                    updates: [.init(id: "update-\(i)", text: "A completed agent update with a report and an image attached.",
                        outputs: [.init(id: "image", name: "Fixture image", kind: "image", encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")],
                        date: now.addingTimeInterval(Double(-i)))], historicalBefore: now)
            }
            let history = (0..<200).map { InboxUpdate(id: "long-\($0)", text: String(repeating: "A detailed Markdown report with findings.\n\n", count: 100), date: now.addingTimeInterval(Double(-$0))) }
            try await store.ingest(project: "fixture", conversation: "long", title: "Long report history", updates: history, historicalBefore: now)
            inboxModel = ProjectInboxModel(store: store)
        } catch { status = "Inbox fixture failed: " + error.localizedDescription }
    }
    private func inboxScroll(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.hasVerticalScroller { return scroll }
        for child in view.subviews { if let found = inboxScroll(child) { return found } }
        return nil
    }
    func capture(_ view: SpatialSceneView, withRoster: Bool = false, allFinished: Bool = false, mixedLeisure: Bool = false) async {
        while view.window == nil && !cancelled { try? await Task.sleep(for:.milliseconds(50)) }
        guard !cancelled else { return }
        NSApp.activate(ignoringOtherApps:true)
        view.window?.makeKeyAndOrderFront(nil)
        status = "Waiting for an unoccluded benchmark window…"
        while view.window?.occlusionState.contains(.visible) != true {
            guard !cancelled else { return }
            let detail = "window=\(view.window?.windowNumber ?? -1) visible=\(view.window?.isVisible == true) mini=\(view.window?.isMiniaturized == true) activeSpace=\(view.window?.isOnActiveSpace == true) hidden=\(NSApp.isHidden) active=\(NSApp.isActive) screen=\(view.window?.screen?.localizedName ?? "nil") frame=\(String(describing:view.window?.frame))"
            try? detail.write(toFile:"/tmp/diorama-benchmark-visibility.txt",atomically:true,encoding:.utf8)
            try? await Task.sleep(for:.milliseconds(200))
        }
        for count in (withRoster || mixedLeisure ? [64] : [16,64]) {
            guard !cancelled else { return }
            status = "Warming \(max(16,count))-desk fixture…"
            var agents=(0..<count).map { i in SpatialAgent(projectID:"fixture",conversationID:"c",value:WorkspaceAgent(id:"a\(i)",name:"Agent",provider:"Codex",task:"Performance fixture",action:"Editing",status: allFinished || mixedLeisure && i >= count/2 ? .done : .working,reportedStatus: allFinished || mixedLeisure && i >= count/2 ? "done" : "working",freshness:.live,observedAt:Date())) }
            if withRoster {
                for i in agents.indices {
                    agents[i].value.name = ["Milo", "Iris", "Ada", "Otto"][i % 4] + " \(i)"
                    agents[i].value.latestActivity = "Editing a file in the performance fixture"
                    agents[i].value.branch = "fixture-branch"; agents[i].value.worktree = "/tmp/fixture/\(i)"
                }
                roster.ingest(agents); roster.flushForTesting()
            }
            let session=AppServerHistory.session(["id":"c", "cwd":"/tmp/scene-fixture", "name":"Fixture", "threadSource":"user"], archived:false)!
            var world=SpatialWorld(projects:[.init(id:"fixture",name:"Performance fixture",teams:[.init(projectID:"fixture",session:session,agents:agents)])])
            let cold=CACurrentMediaTime()
            view.apply(world:world,focus:.project("fixture"),active:true,reducedMotion:false,reset:count)
            await view.meadow.settle()
            try? await Task.sleep(for:.seconds(2))
            let base=view.pose, start=CACurrentMediaTime()
            view.frameTelemetry.reset()
            status="Capturing \(count) roster agents / \(view.officeWorkstations.count) avatars for 30 seconds at \(view.preferredFramesPerSecond) FPS…"
            var lastObservation=0
            view.frameObserved = { [weak view] now in
                guard let view else { return }
                let t=now-start
                if (self.inboxModel != nil || withRoster), let content = view.window?.contentView, let scroll = self.inboxScroll(content), let document = scroll.documentView {
                    let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
                    let cycle = t.truncatingRemainder(dividingBy: 12) / 12
                    let fraction = cycle < 0.8 ? cycle / 0.8 : 1 - (cycle - 0.8) / 0.2
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum * fraction)); scroll.reflectScrolledClipView(scroll.contentView)
                } else if t>5 {
                    var pose=base; pose.yaw += sin(t*0.45)*0.8; pose.scale *= 1+0.2*sin(t*0.8)
                    if t>20 { pose.x += sin(t*0.6)*2 }
                    view.move(to:pose,animated:false)
                }
                let observation=Int(t/3)
                if observation != lastObservation && !world.projects[0].teams[0].agents.isEmpty {
                    lastObservation=observation
                    let old = world.projects[0].teams[0].agents[0]
                    var value = old.value
                    value.action="Editing \(observation)"
                    world.projects[0].teams[0].agents[0] = SpatialAgent(projectID:old.projectID, conversationID:old.conversationID, value:value)
                    view.apply(world:world,focus:.project("fixture"),active:true,reducedMotion:false,reset:count)
                }
            }
            var remainedVisible = true
            var tick = 0
            while mixedLeisure ? CACurrentMediaTime()-start < 30 : tick < 300 {
                tick += 1
                guard !cancelled else { view.frameObserved = nil; return }
                try? await Task.sleep(for:.milliseconds(100))
                if withRoster {
                    for j in 0..<8 {
                        let i = (tick * 8 + j) % count
                        agents[i].value.meaningfulEventID = "burst-\(tick)-\(j)"
                        agents[i].value.meaningfulUpdatedAt = Date()
                        agents[i].value.latestActivity = "Reported update \(tick) for agent \(i)"
                    }
                    roster.ingest(agents)
                }
                remainedVisible = remainedVisible && view.window?.occlusionState.contains(.visible) == true
            }
            view.frameObserved=nil
            let samples=view.frameTelemetry.snapshot().intervals.sorted()
            let result: String
            if !remainedVisible || samples.isEmpty { result="INVALID capture: insufficient visible frames. Window visible=\(view.window?.occlusionState.contains(.visible) == true), playing=\(view.isPlaying)\n" }
            else {
                let p95=samples[Int(Double(samples.count-1)*0.95)]*1000
                result="\(count) roster agents; \(view.officeWorkstations.count) avatars; 16 desks; target=\(view.preferredFramesPerSecond); backing=\(view.convertToBacking(view.bounds).size); cold+warmup=\(start-cold)s; frames=\(samples.count); median=\(samples[samples.count/2]*1000)ms; p95=\(p95)ms; >33ms=\(samples.filter{$0>0.033}.count); cache=\(view.meadow.cachedBytes); PASS=\(p95<17.5)\n"
            }
            let file = mixedLeisure ? "/tmp/diorama-fixed-native-64.txt" : allFinished ? "/tmp/diorama-standing-native-\(count).txt" : withRoster ? "/tmp/diorama-roster-native-64.txt" : self.inboxModel == nil ? "/tmp/diorama-native-\(max(16,count)).txt" : "/tmp/diorama-inbox-native-\(max(16,count)).txt"
            try? result.write(toFile:file,atomically:true,encoding:.utf8)
            status=result
        }
        view.suspend()
        roster.setActive(false)
        status = mixedLeisure ? "Capture complete: /tmp/diorama-fixed-native-64.txt" : withRoster ? "Roster capture complete. Results: /tmp/diorama-roster-native-64.txt" : inboxModel == nil ? "Capture complete. Results: /tmp/diorama-native-16.txt and /tmp/diorama-native-64.txt" : "Inbox capture complete. Results: /tmp/diorama-inbox-native-16.txt and /tmp/diorama-inbox-native-64.txt"
        if let fixtureDirectory { try? FileManager.default.removeItem(at: fixtureDirectory) }
    }
}

/// Development-only diagnostic window in the already running app. No provider actions.
@MainActor enum AgentRosterBenchmarkWindow {
    private static var window: NSWindow?
    static func open() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 1200, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Diorama roster performance fixture"
        window.contentView = NSHostingView(rootView: SceneBenchmarkView(withRoster: true))
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

@MainActor enum StandingOfficeBenchmarkWindow {
    private static var window: NSWindow?
    static func open() {
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 1200, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Diorama standing office performance fixture"
        window.contentView = NSHostingView(rootView: SceneBenchmarkView(allFinished: true))
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

/// Maximum mixed occupancy in the fixed office, with no provider sessions.
@MainActor enum FixedOfficeBenchmarkWindow {
    private static var window: NSWindow?
    static func open() {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 60,y: 60,width: 1200,height: 800), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Diorama fixed office performance fixture"
        window.contentView = NSHostingView(rootView: SceneBenchmarkView(mixedLeisure: true))
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
