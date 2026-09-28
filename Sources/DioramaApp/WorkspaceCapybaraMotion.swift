import SceneKit
import simd

/// Owns the test character's body, navigation and contact correction in the actual workspace.
@MainActor final class WorkspaceCapybaraMotion {
    enum Gait: String, CaseIterable { case walk = "Walk", run = "Run" }
    let root = SCNNode()
    let character: WorkspaceCapybaraAsset.Instance
    var navigation = WorkspaceCapybaraNavigation()
    var gait: Gait = .walk
    var reducedMotion = false
    private(set) var path: [SIMD2<Float>] = []
    private(set) var speed: Float = 0
    private(set) var phase: Float = 0
    private(set) var state = "Idle"
    private(set) var rejectedDestination = false
    private(set) var contactError: Float = 0
    private var elapsed: Float = 0
    private var blend: Float = 0
    private var runBlend: Float = 0
    private var yawVelocity: Float = 0
    private var forwardLean: Float = 0
    private var bank: Float = 0
    private var heading: Float = 0
    private var turnTarget: Float?
    private var contacts: [String: SIMD3<Float>] = [:]
    private var wasStance: [String: Bool] = [:]
    private var pelvisDrop: Float = 0
    private var settling: [WorkspaceCapybaraAsset.Pose]?
    private var settleTime: Float = 0
    let scale: Float = 2.5
    var position: SIMD2<Float> { SIMD2(root.simdPosition.x,root.simdPosition.z) }
    var isMoving: Bool { !path.isEmpty || speed > 0.001 || turnTarget != nil || settleTime > 0 }
    var debug: String { "\(state) · \(String(format: "%.2f",speed)) units/s · contact \(String(format: "%.1f",contactError*1000)) mm" }

    init(asset: WorkspaceCapybaraAsset) {
        character = asset.makeInstance(); root.addChildNode(character.root); character.root.simdScale = SIMD3(repeating:scale)
        root.name = "capybaraMovementTest"; root.simdPosition = SIMD3(3,0,6)
        character.apply(character.pose("idle",time:0))
        let shadow = SCNPlane(width:1.25,height:0.9)
        let material = SCNMaterial();material.diffuse.contents = Self.shadowImage;material.lightingModel = .constant;material.writesToDepthBuffer = false
        shadow.materials = [material]
        let node = SCNNode(geometry:shadow);node.eulerAngles.x = -.pi/2;node.position.y = 0.015;node.renderingOrder = 1;root.addChildNode(node)
    }
    @discardableResult func move(to destination: SIMD2<Float>) -> Bool {
        guard destination.x.isFinite,destination.y.isFinite,let route = navigation.route(from:position,to:destination) else {
            rejectedDestination = true;return false
        }
        path=route;turnTarget=nil;rejectedDestination=false;settling=nil;settleTime=0;return true
    }
    func stop() { path=[];turnTarget=nil }
    func turn(by angle: Float) { guard angle.isFinite else { return };path=[];turnTarget=heading+angle }
    func reset() {
        stop();forwardLean=0;bank=0;contactError=0;rejectedDestination=false;speed=0;heading=0;yawVelocity=0;phase=0;blend=0;runBlend=0;contacts=[:];wasStance=[:];settling=nil;settleTime=0
        pelvisDrop=0;character.root.position.y=0
        root.simdPosition=SIMD3(3,0,6);root.simdOrientation=simd_quatf(angle:0,axis:SIMD3(0,1,0));character.apply(character.pose("idle",time:0));state="Idle"
    }
    func update(_ delta: TimeInterval) {
        guard delta.isFinite,delta>=0 else { return }
        var remaining = Float(min(delta,0.15))
        while remaining>0.000001 { let dt=min(remaining,1/120);step(dt);remaining-=dt }
    }
    private func step(_ dt: Float) {
        elapsed+=dt
        var targetHeading = turnTarget ?? heading, distance: Float = 0
        if let target = path.first {
            distance = simd_distance(position,target)
            if distance < (path.count>1 ? 0.12 : 0.018) {
                path.removeFirst()
                if let next = path.first { distance=simd_distance(position,next);targetHeading=atan2(next.x-position.x,next.y-position.y) }
            } else { targetHeading=atan2(target.x-position.x,target.y-position.y) }
        }
        let angle = atan2(sin(targetHeading-heading),cos(targetHeading-heading))
        // Damped angular velocity makes reversals interruptible; sharper corners slow travel.
        let desiredYaw = max(-2.8,min(2.8,angle*10))
        yawVelocity += (desiredYaw-yawVelocity)*(1-exp(-dt*18))
        let rotation = yawVelocity*dt
        heading += abs(rotation)>abs(angle) ? angle : rotation
        if turnTarget != nil && abs(angle)<0.008 && abs(yawVelocity)<0.05 { turnTarget=nil }
        root.simdOrientation=simd_quatf(angle:heading,axis:SIMD3(0,1,0))
        let walkSpeed: Float = 0.15456989*scale*1.6, runSpeed: Float = 0.6462585*scale*1.1
        let topSpeed = gait == .walk ? walkSpeed : runSpeed
        let acceleration: Float = 3.8, braking: Float = 5.2
        let goalSpeed = path.isEmpty ? 0 : min(topSpeed,sqrt(2*braking*max(0,distance-0.01))) * pow(max(0,cos(angle)),4)
        let previousSpeed=speed
        speed += max(-braking*dt,min(acceleration*dt,goalSpeed-speed))
        let proposed = position+SIMD2(sin(heading),cos(heading))*speed*dt
        if navigation.clear(position,proposed) { root.simdPosition.x=proposed.x;root.simdPosition.z=proposed.y }
        else { speed=0;path=[];rejectedDestination=true }
        let turning = abs(angle)>0.045 && speed<0.06
        let moving = speed>0.012 || turning
        let desiredBlend: Float = moving ? 1 : 0
        blend += (desiredBlend-blend)*(1-exp(-dt*18))
        let desiredRun = max(0,min(1,(speed-walkSpeed)/(runSpeed-walkSpeed)))
        runBlend += (desiredRun-runBlend)*(1-exp(-dt*12))
        let walkDuration = character.asset.clips["walk"]!.duration, runDuration = character.asset.clips["run"]!.duration
        let duration = walkDuration*(1-runBlend)+runDuration*runBlend
        let nominal: Float = (0.15456989*(1-runBlend)+0.6462585*runBlend)*scale
        phase += dt/duration * (turning ? 0.8 : speed/max(0.001,nominal))
        phase.formTruncatingRemainder(dividingBy:1)
        let idle = character.pose("idle",time:reducedMotion ? 0 : elapsed)
        let walk = character.pose("walk",time:phase*walkDuration), run = character.pose("run",time:phase*runDuration)
        let locomotion = zip(walk,run).map { $0.blended(with:$1,weight:runBlend) }
        var pose = zip(idle,locomotion).map { $0.blended(with:$1,weight:blend) }
        if !moving && settling == nil && state != "Idle" && state != "Settling" {
            settling = character.nodes.map { .init(position:$0.simdPosition,rotation:$0.simdOrientation,scale:$0.simdScale) };settleTime=0.22
        }
        if let from = settling {
            settleTime=max(0,settleTime-dt);let t=1-settleTime/0.22;let eased=t*t*(3-2*t)
            pose=zip(from,idle).map { $0.blended(with:$1,weight:eased) }
            if settleTime==0 { settling=nil;contacts=[:];wasStance=[:] }
        }
        character.apply(pose)
        // Small speed/acceleration lean and turn banking communicate weight without a rubbery body.
        let accelerationLean=max(-0.035,min(0.035,(speed-previousSpeed)/dt*0.012))
        let desiredLean: Float = reducedMotion ? 0 : runBlend*0.07+accelerationLean
        forwardLean += (desiredLean-forwardLean)*(1-exp(-dt*12))
        let desiredBank: Float = reducedMotion ? 0 : -yawVelocity*min(speed,1)*0.025
        bank += (desiredBank-bank)*(1-exp(-dt*12))
        if let spine=character.bone("spine") {
            spine.simdWorldOrientation=simd_quatf(angle:forwardLean,axis:root.simdWorldRight)
                * simd_quatf(angle:bank,axis: -root.simdWorldFront) * spine.simdWorldOrientation
        }
        // Anticipate a turn with the head; keep the big head stable over the gait.
        if !reducedMotion, let neck = character.bone("neck") {
            neck.simdOrientation = neck.simdOrientation * simd_quatf(angle:max(-0.18,min(0.18,angle*0.22)),axis:SIMD3(0,1,0))
        }
        if moving {
            contactError=0
            var planted: [(String, SIMD3<Float>)] = []
            var swinging: [(String, SIMD3<Float>)] = []
            for (side,offset) in [("L",Float(0)),("R",Float(0.5))] {
                let p=(phase+offset).truncatingRemainder(dividingBy:1)
                let stance=p < 0.62*(1-runBlend)+0.42*runBlend
                if let foot=character.bone("foot."+side) {
                    if stance && wasStance[side] != true {
                        var anchor=foot.simdWorldPosition;anchor.y=0.045*scale;contacts[side]=anchor
                    }
                    if !stance {
                        var target=foot.simdWorldPosition;target.y=max(0.045*scale,target.y+pelvisDrop);swinging.append((side,target))
                    }
                    if stance,let anchor=contacts[side] { planted.append((side,anchor)) }
                }
                wasStance[side]=stance
            }
            // Reach correction moves the pelvis before solving the legs. Without it,
            // a short-legged character overextends during a planted pivot or gait blend.
            var drop: Float = 0
            for (side,anchor) in planted {
                guard let upper=character.bone("upper_leg."+side), let lower=character.bone("lower_leg."+side), let foot=character.bone("foot."+side) else { continue }
                let hip=upper.simdWorldPosition+SIMD3(0,pelvisDrop,0)
                let reach=simd_distance(upper.simdWorldPosition,lower.simdWorldPosition)+simd_distance(lower.simdWorldPosition,foot.simdWorldPosition)-0.005
                let horizontal=simd_length_squared(SIMD2(hip.x-anchor.x,hip.z-anchor.z))
                let height=sqrt(max(0.001,reach*reach-horizontal))
                drop=max(drop,hip.y-anchor.y-height)
            }
            let desiredDrop=min(0.30,max(0,drop))
            pelvisDrop = desiredDrop>pelvisDrop ? desiredDrop : pelvisDrop+(desiredDrop-pelvisDrop)*(1-exp(-dt*15))
            character.root.position.y = CGFloat(-pelvisDrop)
            for (side,target) in swinging { plant(side,at:target) }
            for (side,anchor) in planted {
                plant(side,at:anchor)
                if let foot=character.bone("foot."+side) { contactError=max(contactError,simd_distance(foot.simdWorldPosition,anchor)) }
            }
        } else {
            contacts=[:];wasStance=[:]
            pelvisDrop *= exp(-dt*15);character.root.position.y=CGFloat(-pelvisDrop)
        }
        state = settleTime>0 ? "Settling" : turning ? "Turning" : speed>0.012 ? (path.isEmpty ? "Stopping" : runBlend>0.5 ? "Running" : "Walking") : "Idle"
    }
    /// Two-bone IK in world space, with an anatomical forward knee pole and flat ankle orientation.
    private func plant(_ side: String, at anchor: SIMD3<Float>) {
        guard let upper=character.bone("upper_leg."+side),let lower=character.bone("lower_leg."+side),let foot=character.bone("foot."+side) else { return }
        let hip=upper.simdWorldPosition,knee=lower.simdWorldPosition,ankle=foot.simdWorldPosition
        let a=simd_distance(hip,knee),b=simd_distance(knee,ankle),delta=anchor-hip
        let length=max(0.001,min(simd_length(delta),a+b-0.0001)),direction=simd_normalize(delta)
        let forward = -root.simdWorldFront
        var pole=forward-direction*simd_dot(forward,direction)
        if simd_length_squared(pole)<0.001 { pole=SIMD3(0,0,1) };pole=simd_normalize(pole)
        let along=(a*a-b*b+length*length)/(2*length)
        let bend=hip+direction*along+pole*sqrt(max(0,a*a-along*along))
        let ankleRotation=foot.simdWorldOrientation
        upper.simdWorldOrientation=simd_quatf(from:simd_normalize(knee-hip),to:simd_normalize(bend-hip))*upper.simdWorldOrientation
        let now=lower.simdWorldPosition
        lower.simdWorldOrientation=simd_quatf(from:simd_normalize(foot.simdWorldPosition-now),to:simd_normalize(anchor-now))*lower.simdWorldOrientation
        foot.simdWorldOrientation=ankleRotation
    }
    private static let shadowImage: NSImage = {
        let image=NSImage(size:NSSize(width:128,height:128));image.lockFocus()
        NSGradient(starting:NSColor(white:0,alpha:0.30),ending:NSColor(white:0,alpha:0))?.draw(in:NSBezierPath(ovalIn:NSRect(x:0,y:0,width:128,height:128)),relativeCenterPosition:.zero)
        image.unlockFocus();return image
    }()
}
