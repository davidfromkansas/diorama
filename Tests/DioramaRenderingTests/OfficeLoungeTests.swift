import AppKit
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct OfficeLoungeTests {
    private func world(_ count: Int) -> SpatialWorld {
        let agents = (0..<count).map { index in
            SpatialAgent(projectID: "lounge-fixture", conversationID: "c", value: WorkspaceAgent(id: "a\(index)", name: "Agent \(index)", provider: "Codex", task: "Lounge fixture", action: "Finished", status: .done, reportedStatus: "done", freshness: .live, observedAt: Date()))
        }
        let session = Session(id: "c", provider: .codex, url: nil, sessionID: "c", title: "Lounge fixture", project: "/tmp/lounge-fixture", modified: Date(), bytes: 0, archived: false, parentID: nil, classification: .conversation)
        return SpatialWorld(projects: [.init(id: "lounge-fixture", name: "TV lounge", teams: [.init(projectID: "lounge-fixture", session: session, agents: agents)])])
    }

    @Test func measuredLayoutHasClearAislesAndStableStandingSlots() {
        let layout = OfficeLeisureLayout.standard
        #expect(layout.placements.count == 8)
        #expect(layout.placements.filter { $0.asset == "LuvaCorner" }.count == 2)
        #expect(layout.placements.filter { $0.asset == "EamesLounge" }.count == 4)
        let sofas = layout.placements.filter { $0.asset == "LuvaCorner" }.sorted { $0.z < $1.z }
        let chairs = layout.placements.filter { $0.asset == "EamesLounge" }.sorted { $0.z < $1.z }
        #expect(sofas[1].bounds.minZ - sofas[0].bounds.maxZ >= 1.199)
        #expect(chairs[2].bounds.minZ - chairs[1].bounds.maxZ >= 1.199)
        #expect(chairs.map(\.bounds.minX).min()! - sofas.map(\.bounds.maxX).max()! >= 1.199)
        for (index, placement) in layout.placements.enumerated() {
            #expect(placement.bounds.maxX < 9.36)
            #expect(placement.bounds.maxZ < layout.floorMaxZ)
            for other in layout.placements.dropFirst(index+1) { #expect(!placement.bounds.overlaps(other.bounds)) }
        }
        for slot in 0..<128 {
            let p = layout.standingPosition(slot: slot)
            #expect(!layout.seatingZone.contains(x: p.x, z: p.z, clearance: 0.4))
        }
    }

    @Test func furnitureRendersAndSurvivesExpansion() throws {
        let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        view.apply(world: world(0), focus: .project("lounge-fixture"), active: false, reducedMotion: true, reset: 0)
        let group = try #require(view.scene?.rootNode.childNode(withName: "officeTVLounge", recursively: true))
        #expect(group.childNodes.count == 8)
        for child in group.childNodes {
            #expect(abs(child.worldPosition.y) < 0.02)
            if child.name?.hasPrefix("loungeChair") == true {
                #expect(child.boundingBox.max.y < 0.91)
                #expect(child.boundingBox.max.x-child.boundingBox.min.x < 1.1) // no ottoman
            }
        }
        let tv = try #require(group.childNode(withName: "loungeTV", recursively: false))
        #expect(abs(tv.boundingBox.max.z - tv.boundingBox.min.z - 3.8) < 0.02)
        #expect(abs(tv.boundingBox.max.y - tv.boundingBox.min.y - 2.4687672) < 0.02)
        #expect(abs(Double(tv.worldPosition.x) - OfficeBakedLayout.transforms["loungeTV"]!.x) < 0.02)
        let table = try #require(group.childNode(withName: "loungeFoosball", recursively: false))
        #expect(abs(table.boundingBox.max.y - table.boundingBox.min.y - 0.9) < 0.02)
        let oldPositions = group.childNodes.map(\.worldPosition)
        view.apply(world: world(64), focus: .project("lounge-fixture"), active: false, reducedMotion: true, reset: 0)
        #expect(view.scene?.rootNode.childNode(withName: "officeTVLounge", recursively: true) === group)
        for (node, old) in zip(group.childNodes, oldPositions) {
            #expect(abs(node.worldPosition.x-old.x) < 0.001 && abs(node.worldPosition.z-old.z) < 0.001)
        }
        view.suspend()
    }

    @Test func loungeSnapshotsAndIncrementalRenderCost() throws {
        var report: [String] = ["Synchronous offscreen snapshot timing, 1200x800 points, static avatars. Not native display FPS."]
        for count in [0,16,64] {
            let view = SpatialSceneView(); view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
            view.apply(world: world(count), focus: .project("lounge-fixture"), active: false, reducedMotion: true, reset: 0)
            let pose = view.pose
            for angle in 0..<4 {
                var fitted = pose; fitted.yaw += Double(angle) * .pi/2; fitted.scale *= 1.5
                view.move(to: fitted, animated: false)
                try save(view.snapshot(), path: "/tmp/diorama-lounge-\(count)-\(angle).png")
            }
            let center = OfficeLeisureLayout.standard.centerZ
            view.move(to: .init(x: 4.5, y: 0.7, z: center, scale: 6.5, yaw: -.pi/4, elevation: .pi/6), animated: false)
            try save(view.snapshot(), path: "/tmp/diorama-lounge-close-\(count).png")
            if count > 0 {
                view.move(to: pose, animated: false)
                let group = try #require(view.scene?.rootNode.childNode(withName: "officeTVLounge", recursively: true))
                var samples: [Bool: [Double]] = [false: [], true: []]
                for index in 0..<36 {
                    for visible in [false,true] {
                        group.isHidden = !visible
                        let start = ProcessInfo.processInfo.systemUptime
                        autoreleasepool { _ = view.snapshot() }
                        let elapsed = (ProcessInfo.processInfo.systemUptime-start)*1000
                        if index >= 6 { samples[visible, default: []].append(elapsed) }
                    }
                }
                for visible in [false,true] {
                    let values = samples[visible]!.sorted()
                    report.append("\(count) agents, lounge \(visible ? "visible" : "hidden"): median \(values[values.count/2]) ms; p95 \(values[Int(Double(values.count)*0.95)]) ms")
                }
            }
            view.suspend()
        }
        try report.joined(separator: "\n").write(toFile: "/tmp/diorama-lounge-render-cost.txt", atomically: true, encoding: .utf8)
    }

    private func save(_ image: NSImage, path: String) throws {
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
