import AppKit
import SceneKit
import Testing
@testable import DioramaApp

@MainActor struct KitchenSceneTests {
    @Test func kitchenFitsWithoutCameraInteraction() {
        let view = KitchenSceneView()
        for size in [CGSize(width: 1000, height: 700), CGSize(width: 300, height: 700), CGSize(width: 1000, height: 250)] {
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded(); view.fitFloor()
            for (index, frame) in view.labelFrames.enumerated() {
                #expect(view.bounds.contains(frame))
                for other in view.labelFrames.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
            }
            for point in view.framingPoints.map(view.projectPoint) {
                #expect(point.x >= 0 && Double(point.x) <= size.width)
                #expect(point.y >= 0 && Double(point.y) <= size.height)
            }
        }
        #expect(view.pointOfView?.camera?.usesOrthographicProjection == false)
        view.frame.size = CGSize(width: 650, height: 650); view.fitFloor()
        // Measure the visible kitchen, including the floor between and around stations.
        let projected = (view.floorCorners + view.framingPoints).map(view.projectPoint)
        let occupiedHeight = min(650, projected.map(\.y).max()!) - max(0, projected.map(\.y).min()!)
        // The 24×16 lifecycle room is wider than tall, so a square view is width-limited; low,
        // chef-height worktops add little projected height. Allow one pixel for rounding.
        #expect(occupiedHeight >= 650 * 0.6 - 1)
        for fixture in KitchenLayout.connectors + KitchenLayout.breakRoomWalls + KitchenLayout.elevatorWalls {
            #expect(KitchenLayout.floor.contains(fixture))
        }
        // Stations never overlap one another or the connecting cabinets.
        let footprints = KitchenLayout.areas.map(\.footprint) + KitchenLayout.connectors
        for (i, a) in footprints.enumerated() { for b in footprints.dropFirst(i + 1) { #expect(!a.insetBy(dx: 0.01, dy: 0.01).intersects(b)) } }
        #expect(!view.allowsCameraControl)
        #expect(!view.isPlaying && !view.rendersContinuously)
        #expect(KitchenLayout.areas.map(\.id) == ["elevator", "order", "prep", "cooking", "stove", "tasting", "bell", "serving", "break", "pantry"])
        #expect(KitchenLayout.areas.map(\.spots) == [1, 3, 6, 6, 6, 3, 6, 5, 10, 4])
    }
    @Test func captureKitchenViewportSizes() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_KITCHEN_CAPTURE"] == "1" else { return }
        let view = KitchenSceneView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        for size in [CGSize(width: 1000, height: 700), CGSize(width: 650, height: 650), CGSize(width: 420, height: 700)] {
            view.frame.size = size; view.fitFloor()
            let tiff = try #require(view.snapshot().tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-kitchen-filled-\(Int(size.width)).png"))
        }
    }
    @Test func sceneChoiceDefaultsToKitchenAndIsWindowLocal() {
        let first = SpatialWorkspaceState(), second = SpatialWorkspaceState()
        #expect(first.sceneKind == .kitchen)
        first.sceneKind = .office
        #expect(second.sceneKind == .kitchen)
        #expect(first.focus == .portfolio)
    }
}
