import AppKit
import SceneKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct OfficeMeadowTests {
    let office = MeadowBounds(minX: -6, maxX: 6, minZ: -7, maxZ: 7)
    @Test func deterministicWorldPlacementExclusionAndExpansion() {
        let key = MeadowPatchKey(x: 0, z: 0, size: 16, density: 40)
        let seed = MeadowGenerator.seed("project")
        let original = MeadowGenerator.blades(seed: seed, key: key, office: office)
        #expect(original == MeadowGenerator.blades(seed: seed, key: key, office: office))
        #expect(original != MeadowGenerator.blades(seed: MeadowGenerator.seed("other"), key: key, office: office))
        #expect(original.allSatisfy { !office.contains(Double($0.x), Double($0.z), clearance: 0.6) })
        #expect(original.allSatisfy { $0.height >= 0.35 && $0.height <= 0.75 })
        let expanded = MeadowBounds(minX: -8, maxX: 8, minZ: -9, maxZ: 9)
        #expect(MeadowGenerator.blades(seed: seed, key: key, office: expanded) == original.filter { !expanded.contains(Double($0.x), Double($0.z), clearance: 0.6) })
        let low = MeadowGenerator.blades(seed: seed, key: .init(x: 0, z: 0, size: 16, density: 4), office: office)
        let positions = Set(original.map { "\($0.x):\($0.z)" })
        #expect(low.allSatisfy { positions.contains("\($0.x):\($0.z)") })
    }
    @Test func clockFreezesAndResumesWithoutHiddenElapsedTime() {
        var clock = MeadowWindClock()
        clock.setRunning(true, now: 10); clock.advance(now: 11)
        #expect(clock.time == 1)
        clock.setRunning(false, now: 11); clock.advance(now: 200)
        #expect(clock.time == 1)
        clock.setRunning(true, now: 300); clock.advance(now: 301)
        #expect(clock.time == 2)
    }
    @Test func geometryAndCacheStayBoundedAcrossZoomOrbitAndExpansion() async {
        let meadow = OfficeMeadow(); meadow.configure(project: "p", office: office)
        for size in [10.0, 40, 100, 200, 500] {
            for x in [-size, 0, size] {
                meadow.updateVisibility(bounds: .init(minX: x-size, maxX: x+size, minZ: -size, maxZ: size), centre: SIMD2(x, 0))
                await meadow.settle()
                #expect(meadow.cachedBytes <= OfficeMeadow.byteLimit)
                #expect(meadow.bladeCount > 0 && meadow.bladeCount <= 48_000)
                #expect(meadow.cachedPatchCount <= OfficeMeadow.cacheLimit)
                #expect(meadow.root.childNodes.allSatisfy { $0.categoryBitMask == 2 && !$0.castsShadow })
            }
        }
    }
    @Test func lifecycleAndSnapshots() async throws {
        let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let world = SpatialWorld(projects: [.init(id: "p", name: "Meadow", teams: [])])
        view.apply(world: world, focus: .project("p"), active: true, reducedMotion: true, reset: 0)
        let defaultPose = view.pose
        await view.meadow.settle()
        view.frameStep(at: CACurrentMediaTime())
        #expect(!view.rendersContinuously)
        view.apply(world: world, focus: .project("p"), active: true, reducedMotion: false, reset: 0)
        #expect(view.rendersContinuously) // Empty office still has wind.
        view.apply(world: world, focus: .portfolio, active: false, reducedMotion: false, reset: 0)
        #expect(!view.rendersContinuously)
        view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
        #expect(view.pose == defaultPose)
        func save(_ name: String) throws {
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-meadow-\(name).png"))
        }
        await view.meadow.settle()
        try save("default")
        for (index, yaw) in [-Double.pi / 4, Double.pi / 4, Double.pi * 3 / 4, -Double.pi * 3 / 4].enumerated() {
            for (name, scale, elevation) in [("wide", defaultPose.scale * 3, 0.25), ("near", defaultPose.scale * 0.45, 1.2)] {
                var pose = defaultPose; pose.yaw = yaw; pose.scale = scale; pose.elevation = elevation
                view.move(to: pose, animated: false)
                await view.meadow.settle()
                try save("\(name)-\(index)")
            }
        }
        // Twelve-second deterministic shader capture includes a full traveling gust.
        view.move(to: .init(x: -7.4, y: 0, z: 7.4, scale: 2.4, yaw: -.pi/4, elevation: .pi/6), animated: false)
        await view.meadow.settle()
        view.frame.size = NSSize(width: 720, height: 480)
        let destination = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: "/tmp/diorama-meadow-wind.gif") as CFURL, UTType.gif.identifier as CFString, 120, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        view.meadow.setRunning(false, now: 0); view.meadow.setRunning(true, now: 0)
        var first: Data?
        var distinct = false
        for frame in 0..<120 {
            view.meadow.advance(now: Double(frame) / 10)
            let image = view.snapshot()
            let tiff = try #require(image.tiffRepresentation)
            if first == nil { first = tiff } else if first != tiff { distinct = true }
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        #expect(distinct, "Wind uniform must change the rendered geometry")
        #expect(CGImageDestinationFinalize(destination))
        try save("close")
        view.suspend(); #expect(!view.rendersContinuously)
    }
}

extension OfficeMeadowTests {
    @Test func profileSixteenDesksAndSixtyFourAgents() async throws {
        for count in [0, 64] {
            let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
            let agents = (0..<count).map { index in
                SpatialAgent(projectID: "p", conversationID: "c", value: WorkspaceAgent(id: "a\(index)", name: "Agent", provider: "Codex", task: "Fixture", action: "Editing", status: .working, reportedStatus: "working", freshness: .live, observedAt: Date()))
            }
            let session = Session(id: "c", provider: .codex, url: nil, sessionID: "c", title: "Fixture", project: "/tmp/meadow", modified: Date(), bytes: 0, archived: false, parentID: nil, classification: .conversation)
            let world = SpatialWorld(projects: [.init(id: "p", name: "Fixture", teams: [.init(projectID: "p", session: session, agents: agents)])])
            view.apply(world: world, focus: .project("p"), active: false, reducedMotion: true, reset: 0)
            await view.meadow.settle()
            _ = view.snapshot() // Warm pipelines and assets before timing.
            view.meadow.setRunning(true, now: 0)
            var samples: [Double] = []
            for frame in 0..<60 {
                let start = ProcessInfo.processInfo.systemUptime
                view.meadow.advance(now: Double(frame) / 30)
                _ = view.snapshot()
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            samples.sort()
            print("MEADOW PROFILE \(count == 0 ? 16 : count) desks: median \(samples[30])ms, p95 \(samples[57])ms, \(view.meadow.bladeCount) blades; 1200x800 synchronous snapshot includes GPU readback")
            view.suspend()
        }
    }
}
