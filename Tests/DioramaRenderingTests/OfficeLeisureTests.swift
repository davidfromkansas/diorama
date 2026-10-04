import AppKit
import SceneKit
import simd
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct OfficeLeisureTests {
    private func occupants(_ count: Int) -> [OfficeOccupant] {
        (0..<count).map { i in
            .init(agent:.init(projectID:"leisure",conversationID:"c",value:.init(id:String(format:"a%03d",i),name:"Agent \(i)",provider:"Codex",task:"Leisure fixture",action:"Finished",status:.done,reportedStatus:"done",freshness:.live,observedAt:Date())),assignment:"Fixture")
        }
    }
    @Test func capacitiesPersistenceAndStableVacancies() throws {
        for count in [0,1,2,6,14,18,19,64] {
            var layout=SharedOfficeLayout();let roster=occupants(count);layout.place(roster)
            #expect(layout.leisureSlots.count == min(count,18))
            #expect(Set(layout.leisureSlots.values) == Set(0..<min(count,18)))
            let saved=try JSONDecoder().decode(SharedOfficeLayout.Saved.self,from:JSONEncoder().encode(layout.saved))
            #expect(SharedOfficeLayout(saved:saved).leisureSlots == layout.leisureSlots)
            if count>1 {
                let first=roster[0].id;let old=layout.leisureSlots
                layout.place(Array(roster.dropFirst()))
                #expect(layout.leisureSlots[first] == nil)
                for (id,slot) in old where id != first { #expect(layout.leisureSlots[id] == slot) }
            }
        }
    }
    @Test func bakedDefaultsAndAnchorsFollowEdits() throws {
        let leisure=OfficeLoungeAssets.make()
        let nodes=leisure.childNodes.flatMap { $0.name == "officeTVLounge" ? $0.childNodes : [$0] }
        for node in nodes {
            let baked=try #require(OfficeBakedLayout.transforms[node.name!])
            #expect(abs(Double(node.position.x)-baked.x)<0.0001)
            #expect(abs(Double(node.position.z)-baked.z)<0.0001)
            #expect(abs(Double(node.eulerAngles.y)-baked.rotationRadians)<0.0001)
        }
        let anchors=OfficeLeisureAnchors.targets(furniture:nodes,overflow:8)
        #expect(anchors.prefix(18).map(\.kind) == [.arcade,.pinball]+Array(repeating:.foosball,count:4)+Array(repeating:.sofa,count:8)+Array(repeating:.chair,count:4))
        let arcade=try #require(nodes.first { $0.name == "officeArcade" });arcade.position.x-=1
        let moved=OfficeLeisureAnchors.targets(furniture:nodes,overflow:8)
        #expect(abs(moved[0].point.x-anchors[0].point.x+1)<0.0001)
        #expect(moved[1] == anchors[1])
    }
    @Test func bakeMigrationPreservesOtherProjectEditsAndOldSavedState() throws {
        let suite="leisure-bake-"+UUID().uuidString
        let defaults=try #require(UserDefaults(suiteName:suite));defer { defaults.removePersistentDomain(forName:suite) }
        let project=try #require(OfficeBakedLayout.sourceProject)
        let value=try #require(OfficeBakedLayout.transforms["loungeTV"])
        let values=[project:["loungeTV":value],"other":["loungeTV":value]]
        defaults.set(try JSONEncoder().encode(values),forKey:"officeLayoutDraft.v1")
        let node=SCNNode();node.name="loungeTV";OfficeBakedLayout.apply(to:node)
        let editor=OfficeLayoutEditor();editor.defaults=defaults
        let item=OfficeLayoutEditor.Item(id:"loungeTV",label:"TV",node:node,ignored:nil,width:1,depth:1,apply:{ _ in })
        editor.configure(project:project,items:[item],floor:.init(minX:-10,maxX:10,minZ:-5,maxZ:30))
        #expect(editor.drafts[project]?["loungeTV"] == nil)
        #expect(editor.drafts["other"]?["loungeTV"] == value)
        let old="{\"order\":[],\"standingSlots\":{},\"standing\":[],\"knownPlacements\":[],\"centralRadius\":0}"
        let saved=try JSONDecoder().decode(SharedOfficeLayout.Saved.self,from:Data(old.utf8))
        #expect(saved.leisureSlots == nil)
    }

    @Test func walkingPausesRedirectsAndRejectsBlockedRoutes() async throws {
        let station=OfficeWorkstation(id:"motion"), scene=SCNScene()
        scene.rootNode.addChildNode(station.root)
        let motion=try #require(station.leisureMotion)
        var nav=WorkspaceCapybaraNavigation()
        let desk=OfficeLeisureTarget(id:"desk",kind:.desk,point:.zero,approach:.zero,yaw:0)
        let leisure=OfficeLeisureTarget(id:"leisure",kind:.conversation,point:SIMD2(2,0),approach:SIMD2(2,0),yaw:0)
        motion.setTarget(desk,navigation:nav,animated:false)
        motion.setRunning(true,reduced:false,distant:false)
        motion.setTarget(leisure,navigation:nav,animated:true)
        for _ in 0..<20 { await Task.yield();try await Task.sleep(for:.milliseconds(5));if !motion.path.isEmpty { break } }
        for _ in 0..<20 { motion.step(1.0/60) }
        #expect(motion.point.x > 0 && motion.point.x < 2)
        let paused=motion.point
        motion.setRunning(false,reduced:false,distant:false);motion.step(1)
        #expect(motion.point == paused)
        motion.setRunning(true,reduced:false,distant:false)
        motion.setTarget(desk,navigation:nav,animated:true)
        for _ in 0..<20 { await Task.yield();try await Task.sleep(for:.milliseconds(5));if !motion.path.isEmpty { break } }
        for _ in 0..<180 { motion.step(1.0/60) }
        #expect(motion.atDesk && simd_distance(motion.point,.zero)<0.01)
        nav.obstacles=[.init(min:SIMD2(1,-1),max:SIMD2(3,1))]
        var blocked=false;motion.blocked={ blocked=true }
        motion.setTarget(leisure,navigation:nav,animated:true)
        for _ in 0..<20 { await Task.yield();try await Task.sleep(for:.milliseconds(5));if blocked { break } }
        #expect(blocked && motion.point == .zero)
        motion.setRunning(true,reduced:true,distant:false)
        #expect(!motion.animating)
    }

    @Test func allFurnitureDestinationsHaveRoutesFromWorkArea() async throws {
        let leisure=OfficeLoungeAssets.make()
        let furniture=leisure.childNodes.flatMap { $0.name == "officeTVLounge" ? $0.childNodes : [$0] }
        let desks=(0..<18).map { index in
            let node=SCNNode(),p=SharedOfficeLayout.desk(slot:index)
            node.position=SCNVector3(p.x,0,p.z);node.eulerAngles.y=p.yaw;return node
        }
        let nav=OfficeLeisureAnchors.navigation(furniture:furniture,desks:desks,bounds:.init(minX:-10,maxX:10,minZ:-8.2,maxZ:23.1))
        let targets=OfficeLeisureAnchors.targets(furniture:furniture,overflow:8)
        for original in targets.prefix(18) {
            let target=try #require(OfficeLeisureAnchors.accessible(original,navigation:nav),Comment(rawValue:original.id))
            let route=await OfficeLeisureRouteWorker.shared.route(nav,from:SIMD2(-6.65,-2.6),to:target.approach)
            #expect(route != nil,Comment(rawValue:original.id))
        }
    }

    @Test func nativeAnimatedPerformance() async throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_LEISURE_PERF"] == "1" else { return }
        var reports:[String]=[]
        for count in [16,64] {
            let roster=occupants(count)
            let session=Session(id:"c",provider:.codex,url:nil,sessionID:"c",title:"Fixture",project:"/tmp/leisure",modified:Date(),bytes:0,archived:false,parentID:nil,classification:.conversation)
            let world=SpatialWorld(projects:[.init(id:"leisure",name:"Leisure",teams:[.init(projectID:"leisure",session:session,agents:roster.map(\.agent))])])
            let view=SpatialSceneView()
            let size=NSScreen.main?.visibleFrame.size ?? NSSize(width:1440,height:900)
            let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=view;window.title="Diorama leisure performance fixture"
            NSApp.setActivationPolicy(.regular);window.makeKeyAndOrderFront(nil);window.orderFrontRegardless();NSApp.activate(ignoringOtherApps:true)
            view.apply(world:world,focus:.project("leisure"),active:true,reducedMotion:false,reset:0)
            await view.meadow.settle();try await Task.sleep(for:.seconds(4))
            view.frameTelemetry.reset()
            var visible=true
            for _ in 0..<300 { try await Task.sleep(for:.milliseconds(100));visible = visible && window.occlusionState.contains(.visible) }
            let times=view.frameTelemetry.snapshot().intervals.sorted()
            let p95=times.isEmpty ? 0 : times[Int(Double(times.count-1)*0.95)]*1000
            reports.append("\(count) agents: visible=\(visible), backing=\(view.convertToBacking(view.bounds).size), frames=\(times.count), p95=\(p95)ms, >33ms=\(times.filter { $0>0.033 }.count), PASS=\(visible && !times.isEmpty && p95<=17.5)")
            view.tearDown();window.close()
        }
        try reports.joined(separator:"\n").write(toFile:"/tmp/diorama-leisure-performance.txt",atomically:true,encoding:.utf8)
    }

    @Test func sceneCapacityAndActivitySnapshots() throws {
        for count in [18,64] {
            let roster=occupants(count)
            let session=Session(id:"c",provider:.codex,url:nil,sessionID:"c",title:"Leisure fixture",project:"/tmp/leisure",modified:Date(),bytes:0,archived:false,parentID:nil,classification:.conversation)
            let world=SpatialWorld(projects:[.init(id:"leisure",name:"Leisure",teams:[.init(projectID:"leisure",session:session,agents:roster.map(\.agent))])])
            let view=SpatialSceneView();view.frame=NSRect(x:0,y:0,width:1440,height:1000)
            view.apply(world:world,focus:.project("leisure"),active:false,reducedMotion:true,reset:0)
            #expect(view.officeWorkstations.count == 18)
            #expect(view.emptyOfficeDesks.count == 16)
            #expect(view.officeWorkstations.values.allSatisfy { !$0.showsFurniture })
            let kinds=view.officeWorkstations.values.compactMap { $0.leisureMotion?.target?.kind }
            #expect(kinds.filter { $0 == .arcade }.count == 1)
            #expect(kinds.filter { $0 == .pinball }.count == 1)
            #expect(kinds.filter { $0 == .foosball }.count == 4)
            #expect(kinds.filter { $0 == .sofa }.count == 8)
            #expect(kinds.filter { $0 == .chair }.count == 4)
            for angle in 0..<4 {
                view.move(to:.init(x:5,y:0.7,z:16.7,scale:6.5,yaw:Double(angle) * .pi/2 - .pi/4,elevation:.pi/5),animated:false)
                let tiff=try #require(view.snapshot().tiffRepresentation)
                let bitmap=try #require(NSBitmapImageRep(data:tiff))
                try #require(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/diorama-leisure-\(count)-\(angle).png"))
            }
            let targets=view.officeWorkstations.sorted { $0.key<$1.key }.map { "\($0.key): \(String(describing:$0.value.leisureMotion?.target))" }.joined(separator:"\n")
            try targets.write(toFile:"/tmp/diorama-leisure-targets-\(count).txt",atomically:true,encoding:.utf8)
            view.suspend()
        }
    }
}
