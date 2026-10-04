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
        // Worktops now follow the chef's reach (KitchenLayout.heightScale), so stations project
        // shorter than the original 1.36 m counters. Allow one pixel for projection rounding.
        #expect(occupiedHeight >= 650 * 0.7 - 1)
        for connector in KitchenLayout.connectors {
            #expect(KitchenLayout.floor.contains(connector))
            #expect(!connector.intersects(CGRect(x: -4.5, y: -3.25, width: 9, height: 6.5)))
        }
        #expect(!view.allowsCameraControl)
        #expect(!view.isPlaying && !view.rendersContinuously)
        #expect(KitchenLayout.areas.count == 6)
        for area in KitchenLayout.areas { #expect(KitchenLayout.floor.contains(area.footprint)) }
        let island = KitchenLayout.areas.first { $0.id == "prep" }!.footprint
        #expect(island.size == CGSize(width: 5, height: 2.5))
        for area in KitchenLayout.areas where area.id != "prep" {
            #expect(!island.insetBy(dx: -2, dy: -2).intersects(area.footprint))
        }
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
