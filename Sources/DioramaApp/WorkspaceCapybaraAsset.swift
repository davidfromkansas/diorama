import AppKit
import SceneKit
import simd

/// A deliberately narrow reader for the bundled, validated GLB. No external URLs or extensions.
/// Geometry/materials are shared; every instance owns its skeleton and sampled pose.
@MainActor final class WorkspaceCapybaraAsset {
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
    static let shared: Result<WorkspaceCapybaraAsset, Error> = Result {
        let bundle: Bundle
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Diorama_DioramaApp.bundle"), let packaged = Bundle(url: url) {
            bundle = packaged
        } else { bundle = Bundle.module }
        guard let url = bundle.url(forResource: "Capybara", withExtension: "glb", subdirectory: "Capybara") else {
            throw AssetError.invalid("Bundled capybara is missing")
        }
        return try WorkspaceCapybaraAsset(data: Data(contentsOf: url))
    }
    private let document: [String: Any]
    private let binary: Data
    private let definitions: [[String: Any]]
    private(set) var clips: [String: Clip] = [:]
    private(set) var rest: [Pose] = []
    private var geometry: SCNGeometry!
    private var weights: SCNGeometrySource!
    private var indices: SCNGeometrySource!
    private var jointIDs: [Int] = []
    private var inverseBinds: [NSValue] = []
    private var meshID = 0

    init(data: Data) throws {
        guard data.count > 28, data.u32(0) == 0x46546C67, data.u32(4) == 2,
              Int(data.u32(8)) == data.count else { throw AssetError.invalid("Invalid GLB header") }
        let count = Int(data.u32(12))
        guard count > 0, count + 28 <= data.count, data.u32(16) == 0x4E4F534A,
              data.u32(24 + count) == 0x004E4942,
              let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20+count)) as? [String: Any],
              let nodes = json["nodes"] as? [[String: Any]] else { throw AssetError.invalid("Invalid GLB chunks") }
        document = json; definitions = nodes; binary = data.subdata(in: count+28..<data.count)
        for n in nodes {
            let p = n["translation"] as? [Float] ?? [0,0,0], q = n["rotation"] as? [Float] ?? [0,0,0,1], s = n["scale"] as? [Float] ?? [1,1,1]
            rest.append(Pose(position: SIMD3(p[0],p[1],p[2]), rotation: simd_quatf(ix:q[0],iy:q[1],iz:q[2],r:q[3]), scale: SIMD3(s[0],s[1],s[2])))
        }
        guard let meshes = json["meshes"] as? [[String: Any]], meshes.count == 1,
              let primitives = meshes[0]["primitives"] as? [[String: Any]], primitives.count == 1,
              let attrs = primitives[0]["attributes"] as? [String: Int],
              let position = attrs["POSITION"], let normal = attrs["NORMAL"], let uv = attrs["TEXCOORD_0"],
              let weight = attrs["WEIGHTS_0"], let joint = attrs["JOINTS_0"], let element = primitives[0]["indices"] as? Int,
              let skins = json["skins"] as? [[String: Any]], skins.count == 1,
              let joints = skins[0]["joints"] as? [Int], let bind = skins[0]["inverseBindMatrices"] as? Int,
              let meshNode = nodes.firstIndex(where: { $0["mesh"] as? Int == 0 }) else { throw AssetError.invalid("Unsupported capybara mesh") }
        meshID = meshNode; jointIDs = joints
        let faces = try accessor(element)
        geometry = SCNGeometry(sources: [try source(position,.vertex), try source(normal,.normal), try source(uv,.texcoord)],
                               elements: [SCNGeometryElement(data: faces.data, primitiveType: .triangles, primitiveCount: faces.count / 3, bytesPerIndex: faces.bytes)])
        weights = try source(weight,.boneWeights); indices = try source(joint,.boneIndices)
        inverseBinds = try floats(bind).map { v in
            NSValue(scnMatrix4: SCNMatrix4(simd_float4x4(columns: (SIMD4(v[0],v[1],v[2],v[3]),SIMD4(v[4],v[5],v[6],v[7]),SIMD4(v[8],v[9],v[10],v[11]),SIMD4(v[12],v[13],v[14],v[15])))))
        }
        geometry.materials = [try material()]
        for animation in json["animations"] as? [[String: Any]] ?? [] {
            guard let name = animation["name"] as? String, let samplers = animation["samplers"] as? [[String: Any]], let channels = animation["channels"] as? [[String: Any]] else { continue }
            var tracks: [Track] = []
            for channel in channels {
                guard let index = channel["sampler"] as? Int, let target = channel["target"] as? [String: Any], let node = target["node"] as? Int, let path = target["path"] as? String,
                      let input = samplers[index]["input"] as? Int, let output = samplers[index]["output"] as? Int,
                      ["LINEAR", "STEP"].contains(samplers[index]["interpolation"] as? String ?? "LINEAR") else { throw AssetError.invalid("Unsupported animation channel") }
                tracks.append(Track(node: node, path: path, stepped: samplers[index]["interpolation"] as? String == "STEP", times: try floats(input).map { $0[0] }, values: try floats(output)))
            }
            clips[name] = Clip(duration: tracks.compactMap { $0.times.last }.max() ?? 0, tracks: tracks)
        }
        guard ["idle","walk","run"].allSatisfy({ clips[$0] != nil }), jointIDs.count == 25 else { throw AssetError.invalid("Missing motion foundation") }
    }
    func makeInstance() -> Instance {
        let nodes = definitions.map { definition in let n = SCNNode(); n.name = definition["name"] as? String; return n }
        var children = Set<Int>()
        for (i, definition) in definitions.enumerated() {
            for child in definition["children"] as? [Int] ?? [] { nodes[i].addChildNode(nodes[child]); children.insert(child) }
        }
        let root = SCNNode(); root.name = "capybara"
        for i in nodes.indices where !children.contains(i) { root.addChildNode(nodes[i]) }
        let skin = SCNSkinner(baseGeometry: geometry, bones: jointIDs.map { nodes[$0] }, boneInverseBindTransforms: inverseBinds, boneWeights: weights, boneIndices: indices)
        skin.skeleton = nodes.first { $0.name == "Capybara_Rig" }
        nodes[meshID].geometry = geometry; nodes[meshID].skinner = skin
        let result = Instance(root: root, nodes: nodes, asset: self); result.apply(rest); return result
    }
    func pose(_ name: String, time: Float) -> [Pose] {
        guard let clip = clips[name], clip.duration > 0 else { return rest }
        let t = max(0,time).truncatingRemainder(dividingBy: clip.duration)
        var result = rest
        for track in clip.tracks {
            // Exported tracks are short, uniformly sampled at 30 Hz.
            let last = track.times.count-1
            let a = min(last, max(0, Int(t / clip.duration * Float(last))))
            let b = min(a+1,last)
            let fraction = a == b || track.stepped ? 0 : max(0,min(1,(t-track.times[a])/(track.times[b]-track.times[a])))
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
    private struct Accessor { let data: Data; let count: Int; let width: Int; let bytes: Int; let floating: Bool }
    private func accessor(_ index: Int) throws -> Accessor {
        guard let accessors = document["accessors"] as? [[String: Any]], accessors.indices.contains(index), let views = document["bufferViews"] as? [[String: Any]] else { throw AssetError.invalid("Invalid accessor") }
        let a = accessors[index]
        guard let viewID = a["bufferView"] as? Int, views.indices.contains(viewID), let count = a["count"] as? Int,
              let component = a["componentType"] as? Int, let type = a["type"] as? String,
              let width = ["SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16][type],
              let bytes = [5121:1,5123:2,5125:4,5126:4][component] else { throw AssetError.invalid("Unsupported accessor") }
        let view = views[viewID], offset = (views[viewID]["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? width*bytes
        guard count > 0, offset >= 0, offset+(count-1)*stride+width*bytes <= binary.count else { throw AssetError.invalid("Accessor out of bounds") }
        var packed = Data(); packed.reserveCapacity(count*width*bytes)
        for i in 0..<count { packed.append(binary.subdata(in: offset+i*stride..<offset+i*stride+width*bytes)) }
        return Accessor(data: packed, count: count, width: width, bytes: bytes, floating: component == 5126)
    }
    private func source(_ index: Int, _ semantic: SCNGeometrySource.Semantic) throws -> SCNGeometrySource {
        let a = try accessor(index)
        return SCNGeometrySource(data: a.data, semantic: semantic, vectorCount: a.count, usesFloatComponents: a.floating, componentsPerVector: a.width, bytesPerComponent: a.bytes, dataOffset: 0, dataStride: a.bytes*a.width)
    }
    private func floats(_ index: Int) throws -> [[Float]] {
        let a = try accessor(index)
        guard a.floating else { throw AssetError.invalid("Expected float accessor") }
        return (0..<a.count).map { i in (0..<a.width).map { Float(bitPattern:a.data.u32((i*a.width+$0)*4)) } }
    }
    private func image(_ textureIndex: Int) throws -> NSImage {
        guard let textures = document["textures"] as? [[String: Any]], let images = document["images"] as? [[String: Any]], let views = document["bufferViews"] as? [[String: Any]],
              let source = textures[textureIndex]["source"] as? Int, let view = images[source]["bufferView"] as? Int,
              let length = views[view]["byteLength"] as? Int else { throw AssetError.invalid("Missing embedded texture") }
        let offset = views[view]["byteOffset"] as? Int ?? 0
        guard offset+length <= binary.count, let image = NSImage(data:binary.subdata(in: offset..<offset+length)) else { throw AssetError.invalid("Unreadable texture") }
        return image
    }
    private func material() throws -> SCNMaterial {
        guard let materials = document["materials"] as? [[String: Any]], let pbr = materials[0]["pbrMetallicRoughness"] as? [String: Any],
              let base = pbr["baseColorTexture"] as? [String: Int], let baseID = base["index"],
              let normal = materials[0]["normalTexture"] as? [String: Int], let normalID = normal["index"],
              let rough = pbr["metallicRoughnessTexture"] as? [String: Int], let roughID = rough["index"] else { throw AssetError.invalid("Missing PBR textures") }
        let material = SCNMaterial(); material.lightingModel = .physicallyBased; material.isDoubleSided = true
        material.diffuse.contents = try image(baseID); material.normal.contents = try image(normalID)
        let packed = try image(roughID); material.roughness.contents = packed; material.roughness.textureComponents = .green
        material.metalness.contents = packed; material.metalness.textureComponents = .blue
        // NSImage preserves the embedded image orientation used by the GLB UVs.
        for property in [material.diffuse,material.normal,material.roughness,material.metalness] {
            property.wrapS = .repeat; property.wrapT = .repeat
        }
        return material
    }
}
private extension Data {
    func u32(_ offset: Int) -> UInt32 { withUnsafeBytes { UInt32(littleEndian:$0.loadUnaligned(fromByteOffset:offset,as:UInt32.self)) } }
}
