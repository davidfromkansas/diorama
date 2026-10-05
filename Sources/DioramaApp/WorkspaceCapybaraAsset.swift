import AppKit
import SceneKit
import simd

/// A deliberately narrow reader for bundled, validated skinned GLBs (the capybara and the chef).
/// No external URLs or extensions. Geometry/materials are shared; every instance owns its skeleton
/// and sampled pose.
/// Immutable after init, so poses can be sampled from SceneKit's render thread.
nonisolated final class WorkspaceCapybaraAsset: @unchecked Sendable {
    /// What a bundled character must provide; anything else is rejected rather than half-rendered.
    struct Spec {
        let skeletonRoot: String
        let jointCount: Int
        let requiredClips: [String]
        let instanceName: String
        static let capybara = Spec(skeletonRoot: "Capybara_Rig", jointCount: 25, requiredClips: ["idle", "walk", "run"], instanceName: "capybara")
    }
    struct Pose {
        var position: SIMD3<Float>
        var rotation: simd_quatf
        var scale: SIMD3<Float>
        func blended(with other: Pose, weight: Float) -> Pose {
            Pose(position: simd_mix(position, other.position, SIMD3(repeating: weight)),
                 rotation: simd_slerp(rotation, other.rotation, weight),
                 scale: simd_mix(scale, other.scale, SIMD3(repeating: weight)))
        }
    }
    struct Track { let node: Int; let path: String; let stepped: Bool; let times: [Float]; let values: [[Float]] }
    struct Clip { let duration: Float; let tracks: [Track] }
    struct Instance {
        let root: SCNNode
        let nodes: [SCNNode]
        let asset: WorkspaceCapybaraAsset
        func pose(_ clip: String, time: Float) -> [Pose] { asset.pose(clip, time: time) }
        func apply(_ pose: [Pose]) {
            for (node, p) in zip(nodes, pose) {
                node.simdPosition = p.position; node.simdOrientation = p.rotation; node.simdScale = p.scale
            }
        }
        func bone(_ name: String) -> SCNNode? { nodes.first { $0.name == name } }
    }
    enum AssetError: Error { case invalid(String) }
    @MainActor static let shared: Result<WorkspaceCapybaraAsset, Error> = Result {
        try load("Capybara", subdirectory: "Capybara", spec: .capybara)
    }
    @MainActor static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Diorama_DioramaApp.bundle"), let packaged = Bundle(url: url) {
            return packaged
        }
        return Bundle.module
    }
    @MainActor static func load(_ resource: String, subdirectory: String, spec: Spec) throws -> WorkspaceCapybaraAsset {
        guard let url = resourceBundle.url(forResource: resource, withExtension: "glb", subdirectory: subdirectory) else {
            throw AssetError.invalid("Bundled \(resource).glb is missing")
        }
        return try WorkspaceCapybaraAsset(data: Data(contentsOf: url), spec: spec)
    }
    let spec: Spec
    private let glb: GLBDocument
    private let definitions: [[String: Any]]
    private(set) var clips: [String: Clip] = [:]
    private(set) var rest: [Pose] = []
    private var geometry: SCNGeometry!
    private var weights: SCNGeometrySource!
    private var indices: SCNGeometrySource!
    private var jointIDs: [Int] = []
    private var inverseBinds: [NSValue] = []
    private var meshID = 0

    init(data: Data, spec: Spec = .capybara) throws {
        self.spec = spec
        glb = try GLBDocument(data: data)
        let json = glb.json
        guard let nodes = json["nodes"] as? [[String: Any]] else { throw AssetError.invalid("Invalid GLB chunks") }
        definitions = nodes
        for n in nodes { rest.append(GLBDocument.restPose(n)) }
        guard let meshes = json["meshes"] as? [[String: Any]], meshes.count == 1,
              let primitives = meshes[0]["primitives"] as? [[String: Any]], primitives.count == 1,
              let attrs = primitives[0]["attributes"] as? [String: Int],
              let position = attrs["POSITION"], let normal = attrs["NORMAL"], let uv = attrs["TEXCOORD_0"],
              let weight = attrs["WEIGHTS_0"], let joint = attrs["JOINTS_0"], let element = primitives[0]["indices"] as? Int,
              let skins = json["skins"] as? [[String: Any]], skins.count == 1,
              let joints = skins[0]["joints"] as? [Int], let bind = skins[0]["inverseBindMatrices"] as? Int,
              let meshNode = nodes.firstIndex(where: { $0["mesh"] as? Int == 0 }) else { throw AssetError.invalid("Unsupported \(spec.instanceName) mesh") }
        meshID = meshNode; jointIDs = joints
        let faces = try glb.accessor(element)
        geometry = SCNGeometry(sources: [try glb.source(position,.vertex), try glb.source(normal,.normal), try glb.source(uv,.texcoord)],
                               elements: [SCNGeometryElement(data: faces.data, primitiveType: .triangles, primitiveCount: faces.count / 3, bytesPerIndex: faces.bytes)])
        weights = try glb.source(weight,.boneWeights); indices = try glb.source(joint,.boneIndices)
        inverseBinds = try glb.floats(bind).map { v in
            NSValue(scnMatrix4: SCNMatrix4(simd_float4x4(columns: (SIMD4(v[0],v[1],v[2],v[3]),SIMD4(v[4],v[5],v[6],v[7]),SIMD4(v[8],v[9],v[10],v[11]),SIMD4(v[12],v[13],v[14],v[15])))))
        }
        geometry.materials = [try material()]
        for animation in json["animations"] as? [[String: Any]] ?? [] {
            guard let name = animation["name"] as? String, let samplers = animation["samplers"] as? [[String: Any]], let channels = animation["channels"] as? [[String: Any]] else { continue }
            var tracks: [Track] = []
            for channel in channels {
                guard let index = channel["sampler"] as? Int, let target = channel["target"] as? [String: Any], let node = target["node"] as? Int, let path = target["path"] as? String,
                      ["translation", "rotation", "scale"].contains(path),
                      let input = samplers[index]["input"] as? Int, let output = samplers[index]["output"] as? Int,
                      ["LINEAR", "STEP"].contains(samplers[index]["interpolation"] as? String ?? "LINEAR") else { throw AssetError.invalid("Unsupported animation channel") }
                let values = try glb.floats(output)
                // Baked exports key a constant unit scale on every joint; sampling it is wasted work.
                if path == "scale", rest.indices.contains(node), simd_reduce_max(abs(rest[node].scale - 1)) < 0.0001,
                   values.allSatisfy({ $0.allSatisfy { abs($0 - 1) < 0.0001 } }) { continue }
                tracks.append(Track(node: node, path: path, stepped: samplers[index]["interpolation"] as? String == "STEP", times: try glb.floats(input).map { $0[0] }, values: values))
            }
            clips[name] = Clip(duration: tracks.compactMap { $0.times.last }.max() ?? 0, tracks: tracks)
        }
        guard spec.requiredClips.allSatisfy({ clips[$0] != nil }), jointIDs.count == spec.jointCount,
              nodes.contains(where: { $0["name"] as? String == spec.skeletonRoot }) else { throw AssetError.invalid("Missing motion foundation") }
    }
    func makeInstance() -> Instance {
        let nodes = definitions.map { definition in let n = SCNNode(); n.name = definition["name"] as? String; return n }
        var children = Set<Int>()
        for (i, definition) in definitions.enumerated() {
            for child in definition["children"] as? [Int] ?? [] { nodes[i].addChildNode(nodes[child]); children.insert(child) }
        }
        let root = SCNNode(); root.name = spec.instanceName
        for i in nodes.indices where !children.contains(i) { root.addChildNode(nodes[i]) }
        let skin = SCNSkinner(baseGeometry: geometry, bones: jointIDs.map { nodes[$0] }, boneInverseBindTransforms: inverseBinds, boneWeights: weights, boneIndices: indices)
        skin.skeleton = nodes.first { $0.name == spec.skeletonRoot }
        nodes[meshID].geometry = geometry; nodes[meshID].skinner = skin
        let result = Instance(root: root, nodes: nodes, asset: self); result.apply(rest); return result
    }
    func pose(_ name: String, time: Float) -> [Pose] {
        guard let clip = clips[name], clip.duration > 0 else { return rest }
        let t = max(0,time).truncatingRemainder(dividingBy: clip.duration)
        var result = rest
        for track in clip.tracks {
            let times = track.times, last = times.count-1
            // Last key at or before t; exact at keys, independent of sampling density.
            var low = 0, high = last
            while low < high { let mid = (low+high+1)/2; if times[mid] <= t { low = mid } else { high = mid-1 } }
            let a = low, b = min(a+1,last)
            let fraction = a == b || track.stepped ? 0 : max(0,min(1,(t-times[a])/(times[b]-times[a])))
            let x = track.values[a], y = track.values[b]
            if track.path == "rotation" {
                result[track.node].rotation = simd_slerp(simd_quatf(ix:x[0],iy:x[1],iz:x[2],r:x[3]),simd_quatf(ix:y[0],iy:y[1],iz:y[2],r:y[3]),fraction)
            } else {
                let v = SIMD3(x[0],x[1],x[2]) + (SIMD3(y[0],y[1],y[2])-SIMD3(x[0],x[1],x[2])) * fraction
                if track.path == "translation" { result[track.node].position = v }
                if track.path == "scale" { result[track.node].scale = v }
            }
        }
        return result
    }
    private func material() throws -> SCNMaterial {
        guard let materials = glb.json["materials"] as? [[String: Any]], let pbr = materials[0]["pbrMetallicRoughness"] as? [String: Any],
              let base = pbr["baseColorTexture"] as? [String: Int], let baseID = base["index"],
              let normal = materials[0]["normalTexture"] as? [String: Int], let normalID = normal["index"],
              let rough = pbr["metallicRoughnessTexture"] as? [String: Int], let roughID = rough["index"] else { throw AssetError.invalid("Missing PBR textures") }
        let material = SCNMaterial(); material.lightingModel = .physicallyBased; material.isDoubleSided = true
        material.diffuse.contents = try glb.image(baseID); material.normal.contents = try glb.image(normalID)
        let packed = try glb.image(roughID); material.roughness.contents = packed; material.roughness.textureComponents = .green
        material.metalness.contents = packed; material.metalness.textureComponents = .blue
        // NSImage preserves the embedded image orientation used by the GLB UVs.
        for property in [material.diffuse,material.normal,material.roughness,material.metalness] {
            property.wrapS = .repeat; property.wrapT = .repeat
        }
        return material
    }
}

/// Static meshes from a bundled GLB (chef props, kitchen food), keyed by root node name.
/// Supports several primitives per mesh with PBR materials (embedded base colour,
/// metal/roughness and normal textures, or flat factors); node transforms below each root are
/// preserved. Templates are shared; callers `clone()` them.
@MainActor enum GLBStaticMeshes {
    static func load(_ resource: String, subdirectory: String) throws -> [String: SCNNode] {
        guard let url = WorkspaceCapybaraAsset.resourceBundle.url(forResource: resource, withExtension: "glb", subdirectory: subdirectory) else {
            throw WorkspaceCapybaraAsset.AssetError.invalid("Bundled \(resource).glb is missing")
        }
        return try read(Data(contentsOf: url))
    }
    static func read(_ data: Data) throws -> [String: SCNNode] {
        let glb = try GLBDocument(data: data)
        guard let nodes = glb.json["nodes"] as? [[String: Any]], let meshes = glb.json["meshes"] as? [[String: Any]] else {
            throw WorkspaceCapybaraAsset.AssetError.invalid("Invalid static GLB")
        }
        let materials = (glb.json["materials"] as? [[String: Any]] ?? []).map { material($0, glb: glb) }
        var geometries: [Int: SCNGeometry] = [:]
        func geometry(_ id: Int) throws -> SCNGeometry {
            if let cached = geometries[id] { return cached }
            var sources: [SCNGeometrySource] = [], elements: [SCNGeometryElement] = [], used: [SCNMaterial] = []
            // One SCNGeometry per mesh: primitives become elements over concatenated sources.
            var positions = Data(), normals = Data(), uvs = Data(), vertexCount = 0
            let primitives = meshes[id]["primitives"] as? [[String: Any]] ?? []
            // Texture coordinates are kept only when every primitive has them.
            let textured = primitives.allSatisfy { ($0["attributes"] as? [String: Int])?["TEXCOORD_0"] != nil }
            for primitive in primitives {
                guard let attrs = primitive["attributes"] as? [String: Int], let p = attrs["POSITION"], let n = attrs["NORMAL"],
                      let i = primitive["indices"] as? Int else { throw WorkspaceCapybaraAsset.AssetError.invalid("Unsupported static primitive") }
                let pa = try glb.accessor(p), na = try glb.accessor(n), ia = try glb.accessor(i)
                guard pa.floating, na.floating, pa.width == 3, na.width == 3, pa.count == na.count else { throw WorkspaceCapybaraAsset.AssetError.invalid("Unsupported static attributes") }
                var shifted = [UInt32](); shifted.reserveCapacity(ia.count)
                for k in 0..<ia.count {
                    let raw: UInt32 = ia.bytes == 1 ? UInt32(ia.data[k]) : ia.bytes == 2 ? UInt32(ia.data.u16(k*2)) : ia.data.u32(k*4)
                    shifted.append(raw + UInt32(vertexCount))
                }
                elements.append(SCNGeometryElement(data: shifted.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles, primitiveCount: ia.count/3, bytesPerIndex: 4))
                used.append((primitive["material"] as? Int).flatMap { materials.indices.contains($0) ? materials[$0] : nil } ?? SCNMaterial())
                positions.append(pa.data); normals.append(na.data); vertexCount += pa.count
                if textured, let t = attrs["TEXCOORD_0"] {
                    let ta = try glb.accessor(t)
                    guard ta.floating, ta.width == 2, ta.count == pa.count else { throw WorkspaceCapybaraAsset.AssetError.invalid("Unsupported texture coordinates") }
                    uvs.append(ta.data)
                }
            }
            sources.append(SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12))
            sources.append(SCNGeometrySource(data: normals, semantic: .normal, vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12))
            if textured {
                sources.append(SCNGeometrySource(data: uvs, semantic: .texcoord, vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8))
            }
            let result = SCNGeometry(sources: sources, elements: elements); result.materials = used
            geometries[id] = result
            return result
        }
        func build(_ index: Int) throws -> SCNNode {
            let definition = nodes[index], node = SCNNode(), rest = GLBDocument.restPose(definition)
            node.name = definition["name"] as? String
            node.simdPosition = rest.position; node.simdOrientation = rest.rotation; node.simdScale = rest.scale
            if let mesh = definition["mesh"] as? Int { node.geometry = try geometry(mesh) }
            for child in definition["children"] as? [Int] ?? [] { node.addChildNode(try build(child)) }
            return node
        }
        let children = Set(nodes.flatMap { $0["children"] as? [Int] ?? [] })
        var result: [String: SCNNode] = [:]
        for index in nodes.indices where !children.contains(index) {
            let node = try build(index)
            if let name = node.name { result[name] = node }
        }
        return result
    }
    private static func material(_ definition: [String: Any], glb: GLBDocument) -> SCNMaterial {
        let pbr = definition["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let color = (pbr["baseColorFactor"] as? [Double]) ?? [1, 1, 1, 1]
        let material = SCNMaterial(); material.lightingModel = .physicallyBased
        material.name = definition["name"] as? String
        func texture(_ info: Any?) -> NSImage? { ((info as? [String: Any])?["index"] as? Int).flatMap { try? glb.image($0) } }
        // Embedded textures win over flat factors (SceneKit can't multiply the two).
        material.diffuse.contents = texture(pbr["baseColorTexture"]) ?? NSColor(srgbRed: color[0], green: color[1], blue: color[2], alpha: color.count > 3 ? color[3] : 1)
        if let packed = texture(pbr["metallicRoughnessTexture"]) {
            material.roughness.contents = packed; material.roughness.textureComponents = .green
            material.metalness.contents = packed; material.metalness.textureComponents = .blue
        } else {
            material.metalness.contents = (pbr["metallicFactor"] as? Double) ?? 1
            material.roughness.contents = (pbr["roughnessFactor"] as? Double) ?? 1
        }
        if let normal = texture(definition["normalTexture"]) { material.normal.contents = normal }
        for property in [material.diffuse, material.normal, material.roughness, material.metalness] { property.wrapS = .repeat; property.wrapT = .repeat }
        material.isDoubleSided = definition["doubleSided"] as? Bool ?? false
        return material
    }
}

/// GLB container parsing shared by the skinned and static readers.
nonisolated struct GLBDocument {
    struct Accessor { let data: Data; let count: Int; let width: Int; let bytes: Int; let floating: Bool }
    let json: [String: Any]
    let binary: Data
    // Parsed once: casting these JSON arrays per accessor made loading quadratic.
    private let accessors: [[String: Any]]
    private let views: [[String: Any]]
    init(data: Data) throws {
        guard data.count > 28, data.u32(0) == 0x46546C67, data.u32(4) == 2,
              Int(data.u32(8)) == data.count else { throw WorkspaceCapybaraAsset.AssetError.invalid("Invalid GLB header") }
        let count = Int(data.u32(12))
        guard count > 0, count + 28 <= data.count, data.u32(16) == 0x4E4F534A,
              data.u32(24 + count) == 0x004E4942,
              let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20+count)) as? [String: Any] else { throw WorkspaceCapybaraAsset.AssetError.invalid("Invalid GLB chunks") }
        guard (json["extensionsRequired"] as? [String] ?? []).isEmpty else { throw WorkspaceCapybaraAsset.AssetError.invalid("Unsupported GLB extensions") }
        self.json = json; binary = data.subdata(in: count+28..<data.count)
        accessors = json["accessors"] as? [[String: Any]] ?? []
        views = json["bufferViews"] as? [[String: Any]] ?? []
    }
    static func restPose(_ n: [String: Any]) -> WorkspaceCapybaraAsset.Pose {
        let p = n["translation"] as? [Float] ?? [0,0,0], q = n["rotation"] as? [Float] ?? [0,0,0,1], s = n["scale"] as? [Float] ?? [1,1,1]
        return .init(position: SIMD3(p[0],p[1],p[2]), rotation: simd_quatf(ix:q[0],iy:q[1],iz:q[2],r:q[3]), scale: SIMD3(s[0],s[1],s[2]))
    }
    func accessor(_ index: Int) throws -> Accessor {
        guard accessors.indices.contains(index) else { throw WorkspaceCapybaraAsset.AssetError.invalid("Invalid accessor") }
        let a = accessors[index]
        guard let viewID = a["bufferView"] as? Int, views.indices.contains(viewID), let count = a["count"] as? Int,
              let component = a["componentType"] as? Int, let type = a["type"] as? String,
              let width = ["SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16][type],
              let bytes = [5121:1,5123:2,5125:4,5126:4][component] else { throw WorkspaceCapybaraAsset.AssetError.invalid("Unsupported accessor") }
        let view = views[viewID], offset = (views[viewID]["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? width*bytes
        guard count > 0, offset >= 0, offset+(count-1)*stride+width*bytes <= binary.count else { throw WorkspaceCapybaraAsset.AssetError.invalid("Accessor out of bounds") }
        var packed = Data(); packed.reserveCapacity(count*width*bytes)
        if stride == width*bytes { packed = binary.subdata(in: offset..<offset+count*stride) }
        else { for i in 0..<count { packed.append(binary.subdata(in: offset+i*stride..<offset+i*stride+width*bytes)) } }
        return Accessor(data: packed, count: count, width: width, bytes: bytes, floating: component == 5126)
    }
    func source(_ index: Int, _ semantic: SCNGeometrySource.Semantic) throws -> SCNGeometrySource {
        let a = try accessor(index)
        return SCNGeometrySource(data: a.data, semantic: semantic, vectorCount: a.count, usesFloatComponents: a.floating, componentsPerVector: a.width, bytesPerComponent: a.bytes, dataOffset: 0, dataStride: a.bytes*a.width)
    }
    func floats(_ index: Int) throws -> [[Float]] {
        let a = try accessor(index)
        guard a.floating else { throw WorkspaceCapybaraAsset.AssetError.invalid("Expected float accessor") }
        // Bulk copy, then slice per element (glTF floats are little-endian, like the host).
        let flat = a.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return stride(from: 0, to: flat.count, by: a.width).map { Array(flat[$0..<$0 + a.width]) }
    }
    func image(_ textureIndex: Int) throws -> NSImage {
        guard let textures = json["textures"] as? [[String: Any]], let images = json["images"] as? [[String: Any]], let views = json["bufferViews"] as? [[String: Any]],
              let source = textures[textureIndex]["source"] as? Int, let view = images[source]["bufferView"] as? Int,
              let length = views[view]["byteLength"] as? Int else { throw WorkspaceCapybaraAsset.AssetError.invalid("Missing embedded texture") }
        let offset = views[view]["byteOffset"] as? Int ?? 0
        guard offset+length <= binary.count, let image = NSImage(data:binary.subdata(in: offset..<offset+length)) else { throw WorkspaceCapybaraAsset.AssetError.invalid("Unreadable texture") }
        return image
    }
}
nonisolated extension Data {
    func u32(_ offset: Int) -> UInt32 { withUnsafeBytes { UInt32(littleEndian:$0.loadUnaligned(fromByteOffset:offset,as:UInt32.self)) } }
    func u16(_ offset: Int) -> UInt16 { withUnsafeBytes { UInt16(littleEndian:$0.loadUnaligned(fromByteOffset:offset,as:UInt16.self)) } }
}
