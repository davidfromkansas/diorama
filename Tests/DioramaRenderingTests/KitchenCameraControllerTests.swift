import Foundation
import Testing
import simd
@testable import DioramaApp

@MainActor struct KitchenCameraControllerTests {
    private func camera() -> KitchenCameraController {
        var camera = KitchenCameraController()
        camera.setHome(center: SIMD2(0, 0), distance: 30)
        return camera
    }

    @Test func zoomStaysBetweenHomeAndThreeTimesCloser() {
        var c = camera()
        c.scroll(-500)
        #expect(c.pose.zoom == 1)
        for _ in 0..<200 { c.scroll(1000) }
        #expect(c.pose.zoom == KitchenCameraController.maxZoom)
        #expect(abs(simd_distance(c.eye, c.look) - 10) < 0.001)
        // One fast flick can't jump far.
        var flick = camera(); flick.scroll(100_000)
        #expect(flick.pose.zoom <= exp(KitchenCameraController.maxZoomStep) + 0.0001)
    }

    @Test func zoomingBackToHomeSnapsToTheHomeCenter() {
        var c = camera()
        for _ in 0..<10 { c.scroll(100) }
        c.press(.right)
        for _ in 0..<30 { c.step(1 / 30) }
        #expect(c.pose.center.x > 0)
        c.press(.up)
        for _ in 0..<40 { c.scroll(-100) }
        #expect(c.pose.zoom == 1 && c.pose.center == SIMD2(0, 0) && c.held.isEmpty)
    }

    @Test func arrowsDoNothingAtHomeAndStayOverTheFloor() {
        var c = camera()
        c.press(.left)
        for _ in 0..<30 { c.step(1 / 30) }
        #expect(c.pose.center == SIMD2(0, 0))
        for _ in 0..<10 { c.scroll(100) }
        for _ in 0..<600 { c.step(1 / 30) }
        #expect(c.pose.center.x == c.floor.minX)
        c.release(.left); c.press(.up)
        for _ in 0..<600 { c.step(1 / 30) }
        #expect(c.pose.center.y == c.floor.minZ)
    }

    @Test func diagonalMovesAreAsFastAsStraightOnes() {
        var straight = camera(), diagonal = camera()
        for _ in 0..<10 { straight.scroll(100); diagonal.scroll(100) }
        straight.press(.up); diagonal.press(.up); diagonal.press(.right)
        straight.step(0.05); diagonal.step(0.05)
        #expect(abs(simd_length(straight.pose.center) - simd_length(diagonal.pose.center)) < 0.0001)
        // Each frame's step is capped.
        var long = camera(); for _ in 0..<10 { long.scroll(100) }
        long.press(.up); long.step(1)
        #expect(abs(simd_length(long.pose.center) - KitchenCameraController.moveSpeed * KitchenCameraController.maxStep) < 0.0001)
    }

    @Test func qAndWTurnOppositeWaysAndUpFollowsTheTurn() {
        var left = camera(), right = camera()
        left.press(.turnLeft); right.press(.turnRight)
        for _ in 0..<20 { left.step(0.05); right.step(0.05) }
        #expect(abs(left.pose.yaw + .pi / 4) < 0.0001 && abs(right.pose.yaw - .pi / 4) < 0.0001)
        // Up is forward on screen: away from the camera, whatever the turn.
        for _ in 0..<10 { right.scroll(100) }
        right.release(.turnRight)
        let eye = right.eye, look = right.look
        right.press(.up); right.step(0.05)
        let moved = right.look - look, away = SIMD3(look.x - eye.x, 0, look.z - eye.z)
        #expect(simd_dot(simd_normalize(moved), simd_normalize(away)) > 0.999)
    }

    @Test func resetRestoresHomeAndInvalidValuesResetToo() {
        var c = camera()
        for _ in 0..<10 { c.scroll(100) }
        c.press(.turnLeft); c.step(0.05)
        c.reset()
        #expect(c.isHome && c.held.isEmpty)
        var broken = camera()
        broken.force(.init(center: SIMD2(.nan, 0), zoom: 2, yaw: 0))
        #expect(broken.isHome)
        broken.force(.init(center: SIMD2(0, 0), zoom: .infinity, yaw: 0))
        #expect(broken.isHome)
    }
}
