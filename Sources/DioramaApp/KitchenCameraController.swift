import Foundation
import simd

/// The kitchen's free camera (after agentsim's office camera): scroll zooms in up to 3× from the
/// home view, arrow keys move over the floor while zoomed in, Q/W turn around the center point,
/// and R returns home. Pure state, no AppKit, so it can be tested directly.
struct KitchenCameraController: Equatable {
    enum Key: Hashable { case up, down, left, right, turnLeft, turnRight }
    struct Pose: Equatable {
        /// The point on the floor the camera looks at (world x, z).
        var center: SIMD2<Float>
        /// 1 at home, up to `maxZoom` closer.
        var zoom: Float
        /// Turn around the center, in radians (0 = the home view's direction).
        var yaw: Float
    }
    static let maxZoom: Float = 3
    /// Zoom per scroll unit, and the most one scroll event may change it (a fast flick can't jump).
    static let zoomSensitivity: Float = 0.012
    static let maxZoomStep: Float = 0.25
    /// World units per second (the kitchen floor is 24 wide) and radians per second.
    static let moveSpeed: Float = 8
    static let turnSpeed: Float = .pi / 4
    static let maxStep: Float = 0.05

    /// Home: the overview that frames the whole kitchen.
    var homeCenter = SIMD2<Float>(0, 0)
    var homeDistance: Float = 30
    var elevation: Float = 62 * .pi / 180
    var lookHeight: Float = 0.65
    /// The floor's edges; the center never leaves them.
    var floor = (minX: Float(-12), maxX: Float(12), minZ: Float(-8), maxZ: Float(8))
    private(set) var pose = Pose(center: .zero, zoom: 1, yaw: 0)
    private(set) var held: Set<Key> = []

    static func == (a: Self, b: Self) -> Bool {
        a.pose == b.pose && a.held == b.held && a.homeCenter == b.homeCenter && a.homeDistance == b.homeDistance
    }

    var isHome: Bool { pose.zoom <= 1.0001 && pose.yaw == 0 && pose.center == homeCenter }
    var isZoomedIn: Bool { pose.zoom > 1.0001 }

    /// Where the camera stands and what it looks at.
    var eye: SIMD3<Float> {
        let distance = homeDistance / pose.zoom
        let look = self.look
        return look + SIMD3(sin(pose.yaw) * cos(elevation) * distance, sin(elevation) * distance, cos(pose.yaw) * cos(elevation) * distance)
    }
    var look: SIMD3<Float> { SIMD3(pose.center.x, lookHeight, pose.center.y) }

    mutating func setHome(center: SIMD2<Float>, distance: Float) {
        let wasHome = !isZoomedIn && pose.center == homeCenter
        homeCenter = center; homeDistance = distance
        if wasHome { pose.center = center }
        validate()
    }

    /// Scroll to zoom in (positive delta) or back out, never past home.
    mutating func scroll(_ delta: Float) {
        let step = max(-Self.maxZoomStep, min(Self.maxZoomStep, delta * Self.zoomSensitivity))
        let zoom = min(Self.maxZoom, max(1, pose.zoom * exp(step)))
        pose.zoom = zoom
        // All the way back out: the home view, centered, with nothing held.
        if zoom <= 1.0001 { pose.zoom = 1; pose.center = homeCenter; held.removeAll() }
        validate()
    }

    mutating func press(_ key: Key) { held.insert(key) }
    mutating func release(_ key: Key) { held.remove(key) }
    mutating func releaseAll() { held.removeAll() }

    /// Advances held keys by one frame.
    mutating func step(_ delta: Float) {
        let dt = min(Self.maxStep, max(0, delta))
        guard dt > 0, !held.isEmpty else { return }
        if held.contains(.turnLeft) { pose.yaw -= Self.turnSpeed * dt }
        if held.contains(.turnRight) { pose.yaw += Self.turnSpeed * dt }
        // Moving only makes sense zoomed in; at home the whole kitchen is already in view.
        if isZoomedIn {
            var input = SIMD2<Float>(0, 0)
            if held.contains(.up) { input.y -= 1 }
            if held.contains(.down) { input.y += 1 }
            if held.contains(.left) { input.x -= 1 }
            if held.contains(.right) { input.x += 1 }
            if simd_length(input) > 0 {
                // Up is forward on screen: rotate the input by the camera's turn, at one speed in any direction.
                let direction = simd_normalize(input)
                let world = SIMD2(direction.x * cos(pose.yaw) + direction.y * sin(pose.yaw), -direction.x * sin(pose.yaw) + direction.y * cos(pose.yaw))
                pose.center += world * Self.moveSpeed * dt
                pose.center.x = min(floor.maxX, max(floor.minX, pose.center.x))
                pose.center.y = min(floor.maxZ, max(floor.minZ, pose.center.y))
            }
        }
        validate()
    }

    mutating func reset() { pose = Pose(center: homeCenter, zoom: 1, yaw: 0); held.removeAll() }

    /// Any invalid value sends the camera home.
    private mutating func validate() {
        let values = [pose.center.x, pose.center.y, pose.zoom, pose.yaw, homeDistance]
        if values.contains(where: { !$0.isFinite }) || homeDistance <= 0 { if !homeDistance.isFinite || homeDistance <= 0 { homeDistance = 30 }; reset() }
    }
    /// For tests: a pose to start from, validated like any other.
    mutating func force(_ pose: Pose) { self.pose = pose; validate() }
}
