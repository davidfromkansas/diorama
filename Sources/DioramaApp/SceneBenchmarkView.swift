import SwiftUI
import SceneKit
import DioramaCore

/// Explicit diagnostic entry point; never substitutes fixtures in the normal workspace.
struct SceneBenchmarkView: View {
    @State private var run = SceneBenchmarkRun()
    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneBenchmarkSurface(run:run)
            Text(run.status).font(.system(.caption,design:.monospaced)).padding(12).background(.regularMaterial).padding()
        }.frame(minWidth:1080,minHeight:780)
    }
}
private struct SceneBenchmarkSurface: NSViewRepresentable {
    let run: SceneBenchmarkRun
    func makeNSView(context: Context) -> SpatialSceneView {
        let view=SpatialSceneView()
        Task { await run.capture(view) }
        return view
    }
    func updateNSView(_ view: SpatialSceneView, context: Context) {}
    static func dismantleNSView(_ view: SpatialSceneView, coordinator: ()) { view.tearDown() }
}
@Observable @MainActor private final class SceneBenchmarkRun {
    var status = "Preparing native frame capture…"
    func capture(_ view: SpatialSceneView) async {
        while view.window == nil { try? await Task.sleep(for:.milliseconds(50)) }
        NSApp.activate(ignoringOtherApps:true)
        view.window?.makeKeyAndOrderFront(nil)
        status = "Waiting for an unoccluded benchmark window…"
        while view.window?.occlusionState.contains(.visible) != true {
            let detail = "window=\(view.window?.windowNumber ?? -1) visible=\(view.window?.isVisible == true) mini=\(view.window?.isMiniaturized == true) activeSpace=\(view.window?.isOnActiveSpace == true) hidden=\(NSApp.isHidden) active=\(NSApp.isActive) screen=\(view.window?.screen?.localizedName ?? "nil") frame=\(String(describing:view.window?.frame))"
            try? detail.write(toFile:"/tmp/diorama-benchmark-visibility.txt",atomically:true,encoding:.utf8)
            try? await Task.sleep(for:.milliseconds(200))
        }
        for count in [16,64] {
            status = "Warming \(max(16,count))-desk fixture…"
            let agents=(0..<count).map { i in SpatialAgent(projectID:"fixture",conversationID:"c",value:WorkspaceAgent(id:"a\(i)",name:"Agent",provider:"Codex",task:"Performance fixture",action:"Editing",status:.working,reportedStatus:"working",freshness:.live,observedAt:Date())) }
            let session=AppServerHistory.session(["id":"c", "cwd":"/tmp/scene-fixture", "name":"Fixture", "threadSource":"user"], archived:false)!
            var world=SpatialWorld(projects:[.init(id:"fixture",name:"Performance fixture",teams:[.init(projectID:"fixture",session:session,agents:agents)])])
            let cold=CACurrentMediaTime()
            view.apply(world:world,focus:.project("fixture"),active:true,reducedMotion:false,reset:count)
            await view.meadow.settle()
            try? await Task.sleep(for:.seconds(2))
            let base=view.pose, start=CACurrentMediaTime()
            view.frameTelemetry.reset()
            status="Capturing \(max(16,count)) desks for 30 seconds at \(view.preferredFramesPerSecond) FPS…"
            var lastObservation=0
            view.frameObserved = { [weak view] now in
                guard let view else { return }
                let t=now-start
                if t>5 {
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
            for _ in 0..<300 {
                try? await Task.sleep(for:.milliseconds(100))
                remainedVisible = remainedVisible && view.window?.occlusionState.contains(.visible) == true
            }
            view.frameObserved=nil
            let samples=view.frameTelemetry.snapshot().intervals.sorted()
            let result: String
            if !remainedVisible || samples.isEmpty { result="INVALID capture: insufficient visible frames. Window visible=\(view.window?.occlusionState.contains(.visible) == true), playing=\(view.isPlaying)\n" }
            else {
                let p95=samples[Int(Double(samples.count-1)*0.95)]*1000
                result="\(max(16,count)) desks; target=\(view.preferredFramesPerSecond); backing=\(view.convertToBacking(view.bounds).size); cold+warmup=\(start-cold)s; frames=\(samples.count); median=\(samples[samples.count/2]*1000)ms; p95=\(p95)ms; >33ms=\(samples.filter{$0>0.033}.count); cache=\(view.meadow.cachedBytes); PASS=\(p95<17.5)\n"
            }
            try? result.write(toFile:"/tmp/diorama-native-\(max(16,count)).txt",atomically:true,encoding:.utf8)
            status=result
        }
        view.suspend()
        status="Capture complete. Results: /tmp/diorama-native-16.txt and /tmp/diorama-native-64.txt"
    }
}
