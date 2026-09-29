import AppKit
import SceneKit

/// World-space generation keeps surviving blades fixed when the office footprint grows.
nonisolated struct MeadowBounds: Equatable, Sendable {
    var minX: Double, maxX: Double, minZ: Double, maxZ: Double
    func contains(_ x: Double, _ z: Double, clearance: Double = 0) -> Bool {
        x >= minX - clearance && x <= maxX + clearance && z >= minZ - clearance && z <= maxZ + clearance
    }
}

nonisolated struct MeadowBlade: Equatable, Sendable {
    var x: Float, z: Float, height: Float, width: Float, angle: Float, phase: Float, tone: Float
}

nonisolated struct MeadowPatchKey: Hashable, Sendable {
    var x: Int, z: Int, size: Int, density: Int
    var distanceFalloff = false
    var segments = 4
}

nonisolated struct MeadowWindClock {
    private(set) var time = 0.0
    private var previous: TimeInterval?
    mutating func setRunning(_ running: Bool, now: TimeInterval) {
        if !running { previous = nil }
        else if previous == nil { previous = now }
    }
    mutating func advance(now: TimeInterval) {
        guard let previous else { return }
        time += max(0, now - previous)
        self.previous = now
    }
}

/// No randomized Swift Hasher: seeds must survive process restarts.
nonisolated enum MeadowGenerator {
    static let bladeLimit = 48_000
    static let clearance = 0.60 // maximum shader bend + authored curve is < 0.50 m
    static func seed(_ identity: String) -> UInt64 {
        identity.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    static func noise(_ seed: UInt64, _ x: Int, _ z: Int, _ index: Int) -> Float {
        var n = seed ^ (UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15)
        n ^= UInt64(bitPattern: Int64(z)) &* 0xBF58476D1CE4E5B9
        n ^= UInt64(index) &* 0x94D049BB133111EB
        n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
        return Float((n ^ (n >> 31)) & 0xFFFFFF) / Float(0x1000000)
    }
    /// Each square metre has its own ordered candidate set. LOD removes candidates,
    /// never relocates them; changing patch size does not change their world positions.
    static func blades(seed: UInt64, key: MeadowPatchKey, office: MeadowBounds) -> [MeadowBlade] {
        var result: [MeadowBlade] = []
        for z in key.z..<(key.z + key.size) {
            if Task.isCancelled { return [] }
            for x in key.x..<(key.x + key.size) {
                let stride = max(1, -key.density)
                if key.density < 0 && (x % stride != 0 || z % stride != 0) { continue }
                for i in 0..<max(1, key.density) {
                    func r(_ channel: Int) -> Float { noise(seed, x, z, i * 8 + channel) }
                    // A shared metre-scale clump centre plus dispersed edges.
                    let cx = noise(seed, x, z, 900), cz = noise(seed, x, z, 901)
                    let bx = Float(x) + Float(stride) * (0.65 * r(0) + 0.35 * cx)
                    let bz = Float(z) + Float(stride) * (0.65 * r(1) + 0.35 * cz)
                    guard !office.contains(Double(bx), Double(bz), clearance: clearance) else { continue }
                    // Continuous world-space thinning has no patch-boundary step.
                    if key.distanceFalloff && r(7) > 1 / (1 + (bx * bx + bz * bz) / 1600) { continue }
                    let h: Float = r(2) > 0.97 ? 0.75 : 0.35 + r(2) * 0.30
                    result.append(MeadowBlade(x: bx, z: bz, height: h, width: 0.025 + r(3) * 0.025,
                                              angle: r(4) * .pi * 2, phase: r(5) * .pi * 2, tone: r(6)))
                }
            }
        }
        return result
    }
}

/// One draw node per patch, not per blade. Geometry and bounds are in world space.
/// The only per-frame CPU work is advancing one shared material uniform.
final class OfficeMeadow {
    let root = SCNNode()
    private let ground = SCNNode()
    private let material = SCNMaterial()
    private var project = ""
    private var office = MeadowBounds(minX: 0, maxX: 0, minZ: 0, maxZ: 0)
    private struct Entry {
        let node: SCNNode
        let bytes: Int
        let blades: Int
        var access: UInt64
        var prepared: Bool
    }
    private var cache: [MeadowPatchKey: Entry] = [:]
    private var desired: [MeadowPatchKey] = []
    private var visible = Set<MeadowPatchKey>()
    private var ready: [(MeadowPatchKey, MeadowMeshBuffers)] = []
    private var worker: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var access: UInt64 = 0
    private var previousDensity = 0
    private var previousSize = 8
    private var streaming = true
    private var settling = false
    private(set) var bladeCount = 0
    private(set) var clock = MeadowWindClock()
    private(set) var cachedBytes = 0
    var cachedPatchCount: Int { cache.count }
    var pending: Bool { worker != nil || !ready.isEmpty || Set(desired) != visible || desired.contains { cache[$0]?.prepared != true } }
    var changed: (() -> Void)?
    var prepare: ((SCNNode, @escaping @MainActor @Sendable () -> Void) -> Void)?
    var reducedDetail = false
    static let cacheLimit = 512
    static let byteLimit = 128 * 1024 * 1024

    init() {
        root.name = "officeMeadow"; root.categoryBitMask = 2
        ground.name = "meadowGround"; ground.categoryBitMask = 2; ground.castsShadow = false
        let floor = SCNPlane(width: 1, height: 1)
        let soil = SCNMaterial(); soil.diffuse.contents = NSColor(srgbRed: 0.32, green: 0.40, blue: 0.23, alpha: 1)
        soil.lightingModel = .lambert; soil.isDoubleSided = true
        floor.materials = [soil]; ground.geometry = floor; ground.eulerAngles.x = -.pi / 2
        ground.position.y = -0.395; root.addChildNode(ground)
        material.name = "Matte meadow • shared wind"
        material.lightingModel = .lambert; material.isDoubleSided = true
        material.diffuse.contents = NSColor(white: 0.80, alpha: 1); material.specular.contents = NSColor.black
        material.shaderModifiers = [.geometry: """
        uniform float meadowTime;
        #pragma body
        float t = _geometry.texcoords[0].y;
        float phase = _geometry.texcoords[0].x;
        float2 p = _geometry.position.xz;
        float gust = pow(0.5 + 0.5 * sin(meadowTime * 0.628 - dot(p, float2(0.23, 0.16))), 3.0);
        float sway = sin(meadowTime * 1.14 + dot(p, float2(0.15, 0.12)) + phase * 0.22);
        float flutter = sin(meadowTime * 1.55 + phase) * 0.025;
        float bend = t * t * (0.10 + 0.20 * gust + 0.065 * sway);
        _geometry.position.x += bend + flutter * t * t;
        _geometry.position.z += bend * 0.55 + sin(meadowTime * 0.93 + phase) * 0.025 * t * t;
        _geometry.position.y -= abs(bend) * 0.12;
        """]
        material.setValue(Float(0), forKey: "meadowTime")
    }

    func configure(project: String, office: MeadowBounds) {
        guard self.project != project || self.office != office else { root.isHidden = false; return }
        generation &+= 1; worker?.cancel(); worker = nil; ready = []; desired = []
        // Footprint changes must not leave old blades intersecting the enlarged base.
        cache.values.forEach { $0.node.removeFromParentNode() }
        cache = [:]; visible = []; cachedBytes = 0; bladeCount = 0
        self.project = project; self.office = office; root.isHidden = false
    }

    /// Covers the camera's ground intersection, including a blade-height margin.
    /// Coarsen only distant sampling when zoomed far out; cache and blade work stay bounded.
    func updateVisibility(bounds: MeadowBounds, centre: SIMD2<Double>) {
        guard !root.isHidden else { return }
        ground.position.x = (bounds.minX + bounds.maxX) / 2
        ground.position.z = (bounds.minZ + bounds.maxZ) / 2
        ground.scale = SCNVector3(bounds.maxX - bounds.minX + 32, bounds.maxZ - bounds.minZ + 32, 1)
        var size = previousSize
        while (Int((bounds.maxX - bounds.minX) / Double(size)) + 3) * (Int((bounds.maxZ - bounds.minZ) / Double(size)) + 3) > 400 { size *= 2 }
        while size > 8 && (Int((bounds.maxX-bounds.minX)/Double(size/2))+5) * (Int((bounds.maxZ-bounds.minZ)/Double(size/2))+5) < 280 { size /= 2 }
        previousSize = size
        var candidates: [(Int, Int, Double)] = []
        for z in Int(floor(bounds.minZ / Double(size)))-1...Int(floor(bounds.maxZ / Double(size)))+1 {
            for x in Int(floor(bounds.minX / Double(size)))-1...Int(floor(bounds.maxX / Double(size)))+1 {
                let px = x * size, pz = z * size
                if office.contains(Double(px), Double(pz), clearance: MeadowGenerator.clearance),
                   office.contains(Double(px + size), Double(pz + size), clearance: MeadowGenerator.clearance) { continue }
                let d = hypot(Double(px + size / 2) - centre.x, Double(pz + size / 2) - centre.y)
                candidates.append((px, pz, d))
            }
        }
        candidates.sort { $0.2 == $1.2 ? ($0.1, $0.0) < ($1.1, $1.0) : $0.2 < $1.2 }
        // Orthographic blades have the same screen size across the field. Use one
        // candidate budget for the region, then thin distant roots continuously.
        // Segmentation can still fall with distance without changing silhouette coverage.
        let cells = size * size
        let allowance = MeadowGenerator.bladeLimit / max(1, candidates.count)
        var density = min(40, allowance / cells)
        if density == 0 {
            var stride = 2
            while (size / stride) * (size / stride) > max(1, allowance) { stride *= 2 }
            density = -stride
        }
        if density > 0 {
            let tier = [1, 2, 4, 8, 16, 24, 32, 40].last { $0 <= density } ?? 1
            // Upgrade only with 25% spare room; downgrade immediately to respect the cap.
            density = previousDensity > 0 && tier > previousDensity && Double(density) < Double(tier)*1.25 ? previousDensity : tier
        }
        previousDensity = density
        let keys = candidates.map { item -> MeadowPatchKey in
            let prior = desired.first { $0.x == item.0 && $0.z == item.1 && $0.size == size }
            let detailed = item.2 < (prior?.segments == 4 ? 28 : 20)
            return MeadowPatchKey(x: item.0, z: item.1, size: size, density: density, distanceFalloff: true, segments: detailed && !reducedDetail ? 4 : 2)
        }
        guard Set(keys) != Set(desired) else { return }
        desired = keys
        ready.removeAll { !keys.contains($0.0) }
        schedule()
        changed?()
    }

    func setStreaming(_ enabled: Bool) {
        if settling && !enabled { return }
        guard streaming != enabled else { if enabled { schedule() }; return }
        streaming = enabled
        if !enabled {
            worker?.cancel(); worker = nil; generation &+= 1; ready = []
            cache = cache.filter { $0.value.prepared }
            cachedBytes = cache.values.reduce(0) { $0 + $1.bytes }
        }
        else { schedule() }
    }

    private func schedule() {
        guard streaming, worker == nil, ready.count < 8 else { return }
        let queued = Set(ready.map { $0.0 })
        let keys = Array(desired.filter { cache[$0] == nil && !queued.contains($0) }.prefix(4))
        guard !keys.isEmpty else { return }
        let seed = MeadowGenerator.seed(project), footprint = office, revision = generation
        worker = Task { [weak self] in
            let computation = Task.detached(priority: .utility) {
                keys.map { key in (key, MeadowMeshBuffers.build(seed: seed, key: key, office: footprint)) }
            }
            let results = await withTaskCancellationHandler { await computation.value } onCancel: { computation.cancel() }
            guard !Task.isCancelled, let self, revision == self.generation else { return }
            self.worker = nil
            self.ready += results.filter { self.desired.contains($0.0) }
            self.changed?()
        }
    }

    /// Called at most once per display frame. Mesh arithmetic never runs here.
    func uploadReady(budget: TimeInterval = 0.002) {
        guard !ready.isEmpty || Set(desired) != visible else { schedule(); return }
        let start = CACurrentMediaTime()
        while !ready.isEmpty && CACurrentMediaTime()-start < budget {
            let (key, buffers) = ready.removeFirst()
            guard desired.contains(key) else { continue }
            let interval = ScenePerformance.begin("Meadow upload")
            let node = SCNNode(geometry: buffers.geometry(material: material))
            node.name = "meadowPatch"; node.categoryBitMask = 2; node.castsShadow = false
            access &+= 1
            cache[key] = Entry(node: node, bytes: buffers.bytes, blades: buffers.bladeCount, access: access, prepared: prepare == nil)
            cachedBytes += buffers.bytes
            let revision = generation
            prepare?(node) { [weak self, weak node] in
                guard let self, revision == self.generation, self.cache[key]?.node === node else { return }
                self.cache[key]?.prepared = true
                self.changed?()
            }
            ScenePerformance.end("Meadow upload", interval)
        }
        if Set(desired) != visible && !desired.isEmpty && desired.allSatisfy({ cache[$0]?.prepared == true }) {
            // Commit a complete coverage set: no duplicate blades or half-built meadow.
            let next = Set(desired)
            for key in visible.subtracting(next) { cache[key]?.node.removeFromParentNode() }
            bladeCount = 0
            for key in desired {
                guard var entry = cache[key] else { continue }
                access &+= 1; entry.access = access; cache[key] = entry
                bladeCount += entry.blades
                if entry.node.parent == nil { root.addChildNode(entry.node) }
            }
            visible = next
        }
        let protected = visible.union(desired)
        for (key, entry) in cache.sorted(by: { $0.value.access < $1.value.access }) where !protected.contains(key) && (cachedBytes > Self.byteLimit || cache.count > Self.cacheLimit) {
            cache.removeValue(forKey: key); cachedBytes -= entry.bytes
        }
        schedule()
    }

    /// Fixtures await the real asynchronous path, without bypassing production generation.
    func settle() async {
        let wasStreaming = streaming
        settling = true
        defer { settling = false; setStreaming(wasStreaming) }
        setStreaming(true)
        while pending && !Task.isCancelled {
            uploadReady()
            try? await Task.sleep(for: .milliseconds(2))
        }
        uploadReady()
    }

    func setRunning(_ running: Bool, now: TimeInterval = CACurrentMediaTime()) { clock.setRunning(running, now: now) }
    func advance(now: TimeInterval = CACurrentMediaTime()) {
        clock.advance(now: now); material.setValue(Float(clock.time), forKey: "meadowTime")
    }

}

nonisolated struct MeadowMeshBuffers: Sendable {
    let vertices: Data
    let indices: Data
    let vertexCount: Int
    let bladeCount: Int
    let key: MeadowPatchKey
    var bytes: Int { vertices.count + indices.count }
    static func build(seed: UInt64, key: MeadowPatchKey, office: MeadowBounds) -> Self {
        let interval = ScenePerformance.begin("Meadow generation")
        defer { ScenePerformance.end("Meadow generation", interval) }
        let blades = MeadowGenerator.blades(seed: seed, key: key, office: office)
        var vertices: [Float] = [], indices: [UInt32] = []
        vertices.reserveCapacity(blades.count * (key.segments+1) * 24)
        indices.reserveCapacity(blades.count * key.segments * 6)
        for blade in blades {
            if Task.isCancelled { break }
            let base = UInt32(vertices.count / 12)
            let dx = cos(blade.angle), dz = sin(blade.angle)
            for segment in 0...key.segments {
                let t = Float(segment) / Float(key.segments), light = 0.72 + tLight(segment, key.segments)
                let w = blade.width * (1-t)*0.5
                for side: Float in [-1,1] {
                    vertices += [blade.x+side*dx*w+dz*t*t*0.10, -0.39+blade.height*t, blade.z+side*dz*w-dx*t*t*0.10,
                                 -dz*0.35, 0.8, dx*0.35, blade.phase, t,
                                 (0.25+blade.tone*0.16)*light, (0.39+blade.tone*0.16)*light, (0.15+blade.tone*0.12)*light, 1]
                }
                if segment < key.segments {
                    let a = base+UInt32(segment*2); indices += [a,a+1,a+2,a+1,a+3,a+2]
                }
            }
        }
        return Self(vertices: vertices.withUnsafeBufferPointer { Data(buffer:$0) }, indices: indices.withUnsafeBufferPointer { Data(buffer:$0) }, vertexCount: vertices.count/12, bladeCount: blades.count, key: key)
    }
    private static func tLight(_ i: Int, _ n: Int) -> Float { Float(i)/Float(n)*0.28 }
    @MainActor func geometry(material: SCNMaterial) -> SCNGeometry {
        func source(_ semantic: SCNGeometrySource.Semantic, _ components: Int, _ offset: Int) -> SCNGeometrySource {
            SCNGeometrySource(data: vertices, semantic: semantic, vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: components, bytesPerComponent: 4, dataOffset: offset*4, dataStride: 48)
        }
        let geometry = SCNGeometry(sources: [source(.vertex,3,0),source(.normal,3,3),source(.texcoord,2,6),source(.color,4,8)], elements: [SCNGeometryElement(data:indices,primitiveType:.triangles,primitiveCount:indices.count/12,bytesPerIndex:4)])
        geometry.materials = [material]
        geometry.boundingBox = (SCNVector3(Double(key.x)-0.5,-0.4,Double(key.z)-0.5), SCNVector3(Double(key.x+key.size)+0.5,0.4,Double(key.z+key.size)+0.5))
        return geometry
    }
}
