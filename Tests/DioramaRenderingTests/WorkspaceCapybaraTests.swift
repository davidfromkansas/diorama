import AppKit
import SceneKit
import Testing
import simd
@testable import DioramaApp

@MainActor struct WorkspaceCapybaraTests {
    @Test func nativeRigLoadsAndInstancesHaveIndependentBones() throws {
        let asset = try WorkspaceCapybaraAsset.shared.get()
        let a = asset.makeInstance(), b = asset.makeInstance()
        #expect(Set(asset.clips.keys) == ["idle","walk","run"])
        a.apply(a.pose("run",time:0.21));b.apply(b.pose("idle",time:0))
        let left = try #require(a.bone("foot.L")), right = try #require(b.bone("foot.L"))
        #expect(left !== right)
        #expect(simd_distance(left.simdPosition,right.simdPosition)>0.00001 || left.simdOrientation != right.simdOrientation)
        #expect(a.nodes.contains { $0.skinner?.bones.count == 25 })
    }
    @Test func routingAvoidsFurnitureAndRejectsBlockedTargets() {
        var nav = WorkspaceCapybaraNavigation()
        nav.obstacles = [.init(min:SIMD2(-1,-1),max:SIMD2(1,1))]
        let start=SIMD2<Float>(-3,0),goal=SIMD2<Float>(3,0)
        let route=nav.route(from:start,to:goal)
        #expect(route != nil)
        var previous=start
        for p in route ?? [] { #expect(nav.clear(previous,p));previous=p }
        #expect(previous==goal)
        #expect(nav.route(from:start,to:.zero)==nil)
        #expect(nav.route(from:start,to:SIMD2(50,50))==nil)
    }
    @Test func nativeMovementArrivesWithoutCrossingFurniture() async throws {
        let asset=try WorkspaceCapybaraAsset.shared.get()
        for fps in [30,60,120] {
            let character=WorkspaceCapybaraMotion(asset:asset)
            let scene=SCNScene();scene.rootNode.addChildNode(character.root)
            character.navigation.obstacles=[.init(min:SIMD2(-1,1),max:SIMD2(1,5))]
            character.gait = .run
            #expect(character.move(to:SIMD2(-3,2)))
            var maxContact: Float = 0
            for frame in 0..<fps*15 {
                if frame.isMultiple(of:60) { await Task.yield() }
                character.update(1/Double(fps));maxContact=max(maxContact,character.contactError);#expect(character.navigation.isFree(character.position))
                #expect(character.root.simdTransform.columns.3.x.isFinite)
            }
            #expect(simd_distance(character.position,SIMD2(-3,2))<0.06)
            #expect(maxContact < 0.002)
            #expect(character.state=="Idle")
            #expect(character.path.isEmpty)
            #expect(!character.move(to: SIMD2(50,50)))
            character.reset()
            #expect(!character.rejectedDestination && character.speed == 0)
            character.turn(by:.pi);character.update(0.1);let before=character.root.simdOrientation
            character.turn(by:-.pi/2);character.update(1/60)
            #expect(abs(simd_dot(before.vector,character.root.simdOrientation.vector))>0.99)
        }
    }
    @Test func labCanSuspendAndRestoreTheWorkspaceCamera() throws {
        let view=WorkspaceSceneNSView()
        view.apply(agents:[.ready],selectedID:nil,reduceMotion:false,active:true)
        let original=view.pointOfView?.simdTransform
        view.configureMovementLab(enabled:true,gait:.walk,command:0,action:"reset")
        #expect(view.preferredFramesPerSecond==60)
        #expect(view.movementCharacter != nil)
        view.stopRendering()
        #expect(!view.isPlaying && !view.rendersContinuously)
        view.configureMovementLab(enabled:false,gait:.walk,command:1,action:"stop")
        #expect(view.movementCharacter?.root.isHidden==true)
        #expect(view.pointOfView?.simdTransform==original)
    }
    @Test func renderMovementInsideWorkspace() async throws {
        let view=WorkspaceSceneNSView();view.frame=NSRect(x:0,y:0,width:1000,height:750)
        view.apply(agents:[.ready],selectedID:nil,reduceMotion:false,active:false)
        view.configureMovementLab(enabled:true,gait:.run,command:0,action:"reset")
        let character=try #require(view.movementCharacter)
        view.zoom(delta: log(16.0/22.0)/0.015)
        let renderer=SCNRenderer(device:nil,options:nil);renderer.scene=view.scene;renderer.pointOfView=view.pointOfView
        let output=URL(fileURLWithPath:"/tmp/diorama-capybara-workspace",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        // Deterministic native rendering, the same scene, furniture, skinning and controller as the app.
        for frame in 0...720 {
            if frame==30 { character.gait = .walk; #expect(character.move(to:SIMD2(4.5,3))) }
            if frame==210 { character.gait = .run; #expect(character.move(to:SIMD2(-3,-2))) }
            if frame==570 { character.stop() }
            if frame==630 { character.turn(by: .pi) }
            if frame>0 { character.update(1/60) }
            if ProcessInfo.processInfo.environment["DIORAMA_CAPTURE_CAPYBARA"] != "1" && ![0,120,240,360,480,600,720].contains(frame) { continue }
            await Task.yield()
            let image=renderer.snapshot(atTime:Double(frame)/60,with:CGSize(width:1000,height:750),antialiasingMode:.multisampling4X)
            let tiff=try #require(image.tiffRepresentation),bitmap=try #require(NSBitmapImageRep(data:tiff)),png=try #require(bitmap.representation(using:.png,properties:[:]))
            try png.write(to:output.appendingPathComponent(String(format:"frame-%04d.png",frame)))
        }
        view.stopRendering()
    }
}
