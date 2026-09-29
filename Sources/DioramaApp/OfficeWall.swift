import AppKit
import SceneKit

/// A full-height wall with a mitred corner option. Local X is its length, +Y is up.
/// All detail stays within the nominal thickness, except the small cap overhang.
enum OfficeWall {
    static let height = 2.90
    static let thickness = 0.64
    static let panelHeight = 1.16
    static func moduleCount(length: Double) -> Int { max(1, Int((length / 1.8).rounded())) }

    static let cream = material(NSColor(srgbRed: 0.88, green: 0.84, blue: 0.76, alpha: 1))
    static let walnutHorizontal = walnut(vertical: false)
    static let walnutVertical = walnut(vertical: true)
    static let walnutInset: SCNMaterial = {
        let result = walnut(vertical: false)
        result.diffuse.contents = NSColor(srgbRed: 0.43, green: 0.29, blue: 0.19, alpha: 1)
        return result
    }()

    private static func material(_ color: NSColor) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = color
        result.lightingModel = .physicallyBased
        result.roughness.contents = 0.86
        result.metalness.contents = 0
        return result
    }
    /// Analytic grain is continuous in local wall coordinates; it has no image tile seams.
    private static func walnut(vertical: Bool) -> SCNMaterial {
        let result = material(NSColor(srgbRed: 0.48, green: 0.34, blue: 0.23, alpha: 1))
        result.shaderModifiers = [.surface: """
        #pragma body
        float2 p = _surface.diffuseTexcoord;
        float along = \(vertical ? "p.y" : "p.x");
        float across = \(vertical ? "p.x" : "p.y");
        float warp = sin(along * 2.3 + sin(along * 0.71)) * 0.065;
        float grain = sin((across + warp) * 145.0 + sin(along * 6.0) * 0.8);
        float fine = sin((across + warp * 0.6) * 430.0 + sin(along * 3.1));
        float broad = sin(across * 19.0 + sin(along * 1.5));
        _surface.diffuse.rgb *= 0.96 + grain * 0.055 + fine * 0.025 + broad * 0.075;
        """]
        return result
    }

    static func make(length: Double, yaw: CGFloat = 0, startMiter: Bool = false, endMiter: Bool = false) -> SCNNode {
        let root = SCNNode(); root.eulerAngles.y = yaw
        let half = length / 2, t = thickness / 2
        // Clip every horizontal piece to the same corner planes. The joined walls
        // share a diagonal boundary rather than overlapping two solid boxes.
        func piece(_ name: String, x0: Double, x1: Double, y0: Double, y1: Double,
                   z0: Double, z1: Double, material: SCNMaterial) {
            var polygon = [SIMD2(x0,z0), SIMD2(x1,z0), SIMD2(x1,z1), SIMD2(x0,z1)]
            func clip(_ distance: (SIMD2<Double>) -> Double) {
                var output: [SIMD2<Double>] = []
                guard let last = polygon.last else { return }
                var previous = last, previousD = distance(last)
                for point in polygon {
                    let d = distance(point)
                    if (d >= 0) != (previousD >= 0) {
                        output.append(previous + (point-previous) * (previousD / (previousD-d)))
                    }
                    if d >= 0 { output.append(point) }
                    previous = point; previousD = d
                }
                polygon = output
            }
            if startMiter { clip { $0.x - $0.y + half - t } }
            if endMiter { clip { half - t - $0.x - $0.y } }
            guard polygon.count >= 3 else { return }
            var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt32] = []
            func face(_ points: [SCNVector3], normal: SCNVector3) {
                let offset = UInt32(vertices.count)
                vertices += points; normals += Array(repeating: normal, count: points.count)
                for i in 1..<(points.count-1) { indices += [offset, offset+UInt32(i), offset+UInt32(i+1)] }
            }
            face(polygon.reversed().map { SCNVector3($0.x,y1,$0.y) }, normal: SCNVector3(0,1,0))
            face(polygon.map { SCNVector3($0.x,y0,$0.y) }, normal: SCNVector3(0,-1,0))
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i+1) % polygon.count], delta = b-a
                let magnitude = max(0.00001, sqrt(delta.x*delta.x+delta.y*delta.y))
                face([SCNVector3(a.x,y0,a.y), SCNVector3(a.x,y1,a.y), SCNVector3(b.x,y1,b.y), SCNVector3(b.x,y0,b.y)], normal: SCNVector3(delta.y/magnitude,0,-delta.x/magnitude))
            }
            let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals), .init(textureCoordinates: vertices.map { CGPoint(x: $0.x + $0.z, y: $0.y) })], elements: [.init(indices: indices, primitiveType: .triangles)])
            geometry.materials = [material]
            let node: SCNNode
            if name == "creamCap" {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: polygon[0].x, y: -polygon[0].y))
                for point in polygon.dropFirst() { path.line(to: NSPoint(x: point.x, y: -point.y)) }
                path.close()
                let cap = SCNShape(path: path, extrusionDepth: y1-y0)
                cap.chamferRadius = 0.003; cap.materials = [material]
                node = SCNNode(geometry: cap); node.eulerAngles.x = -.pi/2; node.position.y = (y0+y1)/2
            } else { node = SCNNode(geometry: geometry) }
            node.name = name; root.addChildNode(node)
        }
        // A continuous recessed backing is also the finish on free ends.
        piece("walnutBacking", x0: -half, x1: half, y0: 0, y1: panelHeight, z0: -t+0.024, z1: t-0.024, material: walnutHorizontal)
        piece("creamCore", x0: -half, x1: half, y0: panelHeight, y1: height-0.045, z0: -t+0.006, z1: t-0.006, material: cream)
        for side in [-1.0, 1.0] {
            let z = side * t
            let left = startMiter ? -half+t+z : -half
            let right = endMiter ? half-t-z : half
            let count = moduleCount(length: right-left)
            let span = (right-left)/Double(count)
            let z0 = side > 0 ? t-0.025 : -t
            let z1 = side > 0 ? t : -t+0.025
            // Rails and stiles surround inset panels, with a 20 mm physical reveal.
            for (name,lo,hi) in [("bottomRail",0.0,0.10),("topRail",panelHeight-0.10,panelHeight-0.035)] {
                piece(name, x0:left,x1:right,y0:lo,y1:hi,z0:z0,z1:z1,material:walnutHorizontal)
            }
            for i in 0...count {
                let x = left + Double(i)*span
                piece("walnutStile",x0:max(left,x-0.05),x1:min(right,x+0.05),y0:0.10,y1:panelHeight-0.10,z0:z0,z1:z1,material:walnutVertical)
            }
            for i in 0..<count {
                let lo = left+Double(i)*span+0.055, hi = left+Double(i+1)*span-0.055
                piece("walnutInset",x0:lo,x1:hi,y0:0.105,y1:panelHeight-0.105,z0:side > 0 ? t-0.023 : -t+0.020,z1:side > 0 ? t-0.020 : -t+0.023,material:walnutInset)
                piece("creamModule",x0:lo-0.052,x1:hi+0.052,y0:panelHeight+0.025,y1:height-0.045,z0:side > 0 ? t-0.007 : -t,z1:side > 0 ? t : -t+0.007,material:cream)
            }
        }
        piece("walnutChairRail",x0:-half,x1:half,y0:panelHeight-0.035,y1:panelHeight+0.025,z0:-t-0.008,z1:t+0.008,material:walnutHorizontal)
        piece("creamCap",x0:-half-0.012,x1:half+0.012,y0:height-0.045,y1:height,z0:-t-0.012,z1:t+0.012,material:cream)
        // Free ends get matching full-thickness finishes; corner ends are sealed by the mitre.
        for (x, enabled) in [(-half,!startMiter),(half,!endMiter)] where enabled {
            piece("walnutEnd",x0:x < 0 ? x : x-0.02,x1:x < 0 ? x+0.02 : x,y0:0,y1:panelHeight-0.035,z0:-t,z1:t,material:walnutVertical)
        }
        return root
    }
}
