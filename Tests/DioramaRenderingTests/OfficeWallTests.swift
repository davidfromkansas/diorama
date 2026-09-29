import AppKit
import SceneKit
import Testing
@testable import DioramaApp

@MainActor struct OfficeWallTests {
    @Test func modulesDimensionsAndCornerPlanes() {
        for length in [11.86, 13.26, 21.26, 24.06] {
            let count = OfficeWall.moduleCount(length: length)
            #expect(abs(length / Double(count) - 1.8) < 0.2)
            let wall = OfficeWall.make(length: length, endMiter: true)
            #expect(abs(wall.boundingBox.max.y - 2.9) < 0.001)
            #expect(abs(wall.boundingBox.min.y) < 0.001)
            #expect(wall.childNodes.filter { $0.name == "creamCap" }.count == 1)
            for node in wall.childNodes {
                guard let source = node.geometry?.sources(for: .vertex).first else { continue }
                source.data.withUnsafeBytes { bytes in
                    for i in 0..<source.vectorCount {
                        let offset = source.dataOffset + i * source.dataStride
                        let x = bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
                        let z = bytes.loadUnaligned(fromByteOffset: offset+8, as: Float.self)
                        #expect(Double(x+z) <= length / 2 - 0.32 + 0.00001)
                    }
                }
            }
        }
    }
    @Test func referenceAndReverseSnapshots() throws {
        let scene = SCNScene()
        let back = OfficeWall.make(length: 5.4, endMiter: true); back.position = SCNVector3(0,0,-2.38)
        let side = OfficeWall.make(length: 5.4, yaw: -.pi/2, startMiter: true); side.position = SCNVector3(2.38,0,0)
        scene.rootNode.addChildNode(back); scene.rootNode.addChildNode(side)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 4
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 450; scene.rootNode.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 650; sun.eulerAngles = SCNVector3(-0.8,-0.5,0); scene.rootNode.addChildNode(sun)
        let view = SCNView(frame: NSRect(x:0,y:0,width:1000,height:800)); view.scene = scene; view.pointOfView = camera; view.backgroundColor = .white; view.antialiasingMode = .multisampling4X
        for (index, position) in [SCNVector3(-8,6,8), SCNVector3(8,6,-8), SCNVector3(-8,4,-8), SCNVector3(8,4,8)].enumerated() {
            camera.position = position; camera.look(at: SCNVector3(0,1.4,0))
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let image = try #require(NSBitmapImageRep(data:tiff))
            // Catch SceneKit's magenta fallback when a shader fails to compile.
            var magenta = 0
            for y in stride(from:0,to:image.pixelsHigh,by:8) {
                for x in stride(from:0,to:image.pixelsWide,by:8) {
                    if let color = image.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.9 && color.blueComponent > 0.9 && color.greenComponent < 0.1 { magenta += 1 }
                }
            }
            #expect(magenta == 0)
            try #require(image.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/diorama-walls-\(index).png"))
        }
    }
}
