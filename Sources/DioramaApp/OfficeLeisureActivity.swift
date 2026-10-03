import SceneKit
import simd

nonisolated enum OfficeLeisureKind: String, Codable, Sendable { case desk, arcade, pinball, foosball, sofa, chair, conversation }
nonisolated struct OfficeLeisureTarget: Equatable, Sendable {
    var id: String
    var kind: OfficeLeisureKind
    var point: SIMD2<Float>
    var approach: SIMD2<Float>
    var yaw: Float
    var seatHeight: Float = 0
}

/// Interaction anchors are authored in each model's local coordinates and follow edits.
enum OfficeLeisureAnchors {
    static func targets(furniture: [SCNNode], overflow: Int) -> [OfficeLeisureTarget] {
        let nodes = Dictionary(uniqueKeysWithValues: furniture.compactMap { node in node.name.map { ($0,node) } })
        var result: [OfficeLeisureTarget] = []
        func add(_ id: String, _ index: Int, _ kind: OfficeLeisureKind, _ x: Float, _ z: Float, _ yaw: Float, seat: Float = 0, approach: Float = 0.7, authored: Bool = true) {
            guard let parent = nodes[id], let asset = authored ? parent.childNodes.first : parent else { return }
            let p = asset.convertPosition(SCNVector3(x,0,z), to: nil)
            let q = asset.convertPosition(SCNVector3(x+sin(yaw)*approach,0,z+cos(yaw)*approach), to: nil)
            let facing = asset.convertVector(SCNVector3(sin(yaw),0,cos(yaw)), to: nil)
            result.append(.init(id: "\(id):\(index)", kind: kind, point: SIMD2(Float(p.x),Float(p.z)), approach: SIMD2(Float(q.x),Float(q.z)), yaw: atan2(Float(facing.x),Float(facing.z)), seatHeight: seat))
        }
        for (name,kind) in [("officeArcade",OfficeLeisureKind.arcade),("officePinball",.pinball)] {
            if let node = nodes[name]?.childNodes.first {
                add(name,0,kind,0,Float(node.boundingBox.max.z)+0.30,.pi,approach:-0.35)
            }
        }
        // Handles run across Z; pairs stand on opposite Z sides and face inward.
        if let node = nodes["loungeFoosball"]?.childNodes.first {
            let edge = Float(node.boundingBox.max.z)+0.22
            for side in 0..<2 { for i in 0..<2 {
                let sign: Float = side == 0 ? -1 : 1
                add("loungeFoosball",side*2+i,.foosball,Float(i)*1.1-0.55,sign*edge,side == 0 ? 0 : .pi,approach:-0.35)
            }}
        }
        for side in 0..<2 {
            // Four cushion centers around the L; each faces out from its backrest.
            for (i,position) in [SIMD2<Float>(-0.6,0.85),SIMD2(-0.6,0),SIMD2(0.2,-0.65),SIMD2(0.95,-0.65)].enumerated() {
                add("loungeSofa\(side)",i,.sofa,position.x,position.y,i < 2 ? .pi/2 : 0,seat:0.43,approach:1.0)
            }
        }
        for side in 0..<2 { for i in 0..<2 { add("loungeChair\(side)-\(i)",0,.chair,0,0.04,0,seat:0.40,approach:0.9) } }
        for index in 0..<max(overflow,0) {
            let group = index/4, member = index%4
            let center = SIMD2<Float>(-3-Float(group%2)*3.3,11+Float(group/2)*3.3)
            let angle = Float(member) * .pi/2
            let point = center + SIMD2(sin(angle),cos(angle))*0.9
            result.append(.init(id:"conversation:\(index)",kind:.conversation,point:point,approach:point,yaw:angle + .pi))
        }
        return result
    }

    static func accessible(_ target: OfficeLeisureTarget, navigation: WorkspaceCapybaraNavigation) -> OfficeLeisureTarget? {
        if navigation.isFree(target.approach) { return target }
        guard target.kind == .chair else { return nil }
        var other=navigation
        other.obstacles.removeAll { $0.contains(target.point) }
        for distance: Float in [0.9,1.2,1.5] {
            for index in 0..<24 {
                let step = Float((index+1)/2) * .pi/12
                let offset = index % 2 == 0 ? -step : step
                let point=target.point+SIMD2(sin(target.yaw+offset),cos(target.yaw+offset))*distance
                if navigation.isFree(point) && other.clear(target.point,point) { var result=target;result.approach=point;return result }
            }
        }
        return nil
    }

    static func navigation(furniture: [SCNNode], desks: [SCNNode], bounds: LeisureBounds) -> WorkspaceCapybaraNavigation {
        var nav = WorkspaceCapybaraNavigation()
        nav.min = SIMD2(Float(bounds.minX+0.4),Float(bounds.minZ+0.95))
        nav.max = SIMD2(Float(bounds.maxX-0.95),Float(bounds.maxZ-0.4))
        @MainActor func obstacle(_ node: SCNNode, _ minX: CGFloat, _ maxX: CGFloat, _ minZ: CGFloat, _ maxZ: CGFloat) {
            let corners = [node.convertPosition(SCNVector3(minX,0,minZ),to:nil), node.convertPosition(SCNVector3(maxX,0,minZ),to:nil), node.convertPosition(SCNVector3(minX,0,maxZ),to:nil), node.convertPosition(SCNVector3(maxX,0,maxZ),to:nil)]
            nav.obstacles.append(.init(min:SIMD2(Float(corners.map(\.x).min()!)-0.23,Float(corners.map(\.z).min()!)-0.23),max:SIMD2(Float(corners.map(\.x).max()!)+0.23,Float(corners.map(\.z).max()!)+0.23)))
        }
        for node in furniture {
            if node.name?.hasPrefix("loungeSofa") == true, let asset = node.childNodes.first {
                obstacle(asset,-1.47,-0.3,-1.47,1.47)
                obstacle(asset,-0.3,1.47,-1.47,-0.3)
            } else {
                let box=node.boundingBox
                obstacle(node,box.min.x,box.max.x,box.min.z,box.max.z)
            }
        }
        for node in desks { obstacle(node,-0.9,0.9,-0.75,0.8) }
        return nav
    }
}

actor OfficeLeisureRouteWorker {
    static let shared = OfficeLeisureRouteWorker()
    func route(_ nav: WorkspaceCapybaraNavigation, from: SIMD2<Float>, to: SIMD2<Float>) -> [SIMD2<Float>]? {
        guard !Task.isCancelled else { return nil }
        return nav.route(from: from, to: to)
    }
}

/// Uses the scene's display clock, never a timer or provider task.
final class OfficeLeisureMotion {
    let person: SCNNode
    let avatar: WorkspaceAvatar
    private let seated: [WorkspaceCapybaraAsset.Pose]
    private(set) var target: OfficeLeisureTarget?
    private(set) var path: [SIMD2<Float>] = []
    private var job: Task<Void,Never>?
    private var generation = 0
    private var initialized = false
    private var phase: Float
    private var poseTime: Float = 0
    private var running = false
    private var distant = false
    private var requesting = false
    private var arrived = false
    private var blendPose: [WorkspaceCapybaraAsset.Pose]?
    private var blendOffset = SIMD3<Float>.zero
    private var blendTime: Float = 0
    var changed: (() -> Void)?
    var blocked: (() -> Void)?
    var moving: Bool { requesting || !path.isEmpty }
    var atDesk: Bool { target?.kind == .desk && arrived && !moving && blendPose == nil }
    var animating: Bool { running && (moving || blendPose != nil || target?.kind != .desk) }
    var point: SIMD2<Float> { SIMD2(Float(person.worldPosition.x),Float(person.worldPosition.z)) }

    init(person: SCNNode, avatar: WorkspaceAvatar, seed: String) {
        self.person=person;self.avatar=avatar
        seated=avatar.capybaraRig?.nodes.map { .init(position:$0.simdPosition,rotation:$0.simdOrientation,scale:$0.simdScale) } ?? []
        phase=Float(seed.utf8.reduce(0) { ($0*31+Int($1))%997 })/997 * .pi*2
    }
    func setRunning(_ value: Bool, reduced: Bool, distant: Bool) {
        running=value && !reduced;self.distant=distant
        if reduced { job?.cancel();requesting=false;path=[];settle() }
    }
    func setTarget(_ next: OfficeLeisureTarget, navigation: WorkspaceCapybaraNavigation, animated: Bool, revisionChanged: Bool = false) {
        guard target != next || revisionChanged else { return }
        generation+=1;let token=generation;job?.cancel();requesting=false
        let previous=target, wasArrived=arrived;target=next;arrived=false;blendPose=nil
        if !initialized || !animated { initialized=true;path=[];settle();changed?();return }
        var start=point
        // Exit a seat/desk through its reserved approach before normal floor navigation.
        if let previous, wasArrived, previous.kind == .desk || previous.kind == .sofa || previous.kind == .chair { start=previous.approach }
        path=[];requesting=true;changed?()
        job=Task { [weak self] in
            let route=await OfficeLeisureRouteWorker.shared.route(navigation,from:start,to:next.approach)
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.requesting=false
            if let route { self.path = (simd_distance(self.point,start)>0.02 ? [start] : []) + route + (next.point == next.approach ? [] : [next.point]) }
            else { self.blocked?() }
            self.changed?()
        }
    }
    func stop() { generation+=1;job?.cancel();requesting=false;running=false }
    func step(_ delta: TimeInterval) {
        guard running, let target else { return }
        let dt=Float(min(0.05,max(0,delta)));phase+=dt;poseTime+=dt
        if let next=path.first {
            let offset=next-point, distance=simd_length(offset), amount=min(distance,dt*0.65)
            if distance<0.025 { path.removeFirst();if path.isEmpty { settle(blending:true);changed?() };return }
            let p=point+offset/distance*amount
            person.worldPosition=SCNVector3(p.x,0,p.y)
            person.worldOrientation=SCNQuaternion(0,sin(atan2(offset.x,offset.y)/2),0,cos(atan2(offset.x,offset.y)/2))
            avatar.root.position=SCNVector3Zero
            if let rig=avatar.capybaraRig { rig.apply(rig.pose("walk",time:phase*3.6)) }
        } else if !requesting && (target.kind != .desk || blendPose != nil) && (!distant || poseTime>=0.1 || blendPose != nil) {
            poseTime=0;applyPose(target,animated:true)
        }
        if let from=blendPose, let rig=avatar.capybaraRig {
            blendTime+=dt;let weight=min(1,blendTime/0.22)
            let to=rig.nodes.map { WorkspaceCapybaraAsset.Pose(position:$0.simdPosition,rotation:$0.simdOrientation,scale:$0.simdScale) }
            rig.apply(zip(from,to).map { $0.blended(with:$1,weight:weight) })
            avatar.root.simdPosition=simd_mix(blendOffset,avatar.root.simdPosition,SIMD3(repeating:weight))
            if weight>=1 { blendPose=nil;changed?() }
        }
    }
    private func settle(blending: Bool = false) {
        guard let target else { return }
        arrived=true
        blendPose=blending ? avatar.capybaraRig?.nodes.map { .init(position:$0.simdPosition,rotation:$0.simdOrientation,scale:$0.simdScale) } : nil
        blendOffset=avatar.root.simdPosition;blendTime=0
        person.worldPosition=SCNVector3(target.point.x,0,target.point.y)
        person.worldOrientation=SCNQuaternion(0,sin(target.yaw/2),0,cos(target.yaw/2))
        applyPose(target,animated:false)
    }
    private func applyPose(_ target: OfficeLeisureTarget, animated: Bool) {
        guard let rig=avatar.capybaraRig else { return }
        let sitting = target.kind == .desk || target.kind == .sofa || target.kind == .chair
        rig.apply(sitting ? seated : rig.pose("idle",time:0))
        avatar.root.position = sitting ? SCNVector3(0,target.kind == .desk ? 0.2364 : target.seatHeight-0.39,target.kind == .desk ? -0.10 : 0) : SCNVector3Zero
        if target.kind == .desk { return }
        for side in ["L","R"] {
            guard let upper=rig.bone("upper_arm."+side),let lower=rig.bone("lower_arm."+side),let hand=rig.bone("hand."+side) else { continue }
            let sign: Float=side == "L" ? 1 : -1
            let playing = target.kind == .arcade || target.kind == .pinball || target.kind == .foosball
            let sway: Float=animated ? sin(phase*(playing ? 3.5 : 1.4)+sign)*0.025 : 0
            let height: Float=playing ? (target.kind == .pinball ? 0.93 : 0.85) : (sitting ? target.seatHeight+0.2 : 0.67)
            let local=SCNVector3(sign*(playing ? 0.22 : 0.25),height+sway,playing ? 0.27+sway : 0.13)
            let p=person.convertPosition(local,to:nil)
            let goal=SIMD3<Float>(Float(p.x),Float(p.y),Float(p.z))
            let a=upper.simdWorldPosition,b=lower.simdWorldPosition,c=hand.simdWorldPosition
            let lengthA=simd_distance(a,b),lengthB=simd_distance(b,c),delta=goal-a
            let length=min(lengthA+lengthB-0.001,max(abs(lengthA-lengthB)+0.001,simd_length(delta)))
            let direction=simd_normalize(delta), along=(lengthA*lengthA-lengthB*lengthB+length*length)/(2*length)
            var bend=simd_cross(direction,SIMD3<Float>(0,1,0));if simd_length(bend)<0.01 { bend=SIMD3(1,0,0) };bend=simd_normalize(bend)*sign
            let elbow=a+direction*along+bend*sqrt(max(0,lengthA*lengthA-along*along))
            upper.simdWorldOrientation=simd_quatf(from:simd_normalize(b-a),to:simd_normalize(elbow-a))*upper.simdWorldOrientation
            lower.simdWorldOrientation=simd_quatf(from:simd_normalize(hand.simdWorldPosition-lower.simdWorldPosition),to:simd_normalize(a+direction*length-lower.simdWorldPosition))*lower.simdWorldOrientation
        }
    }
}
