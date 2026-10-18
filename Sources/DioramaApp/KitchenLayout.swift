import AppKit
import DioramaCore
import Foundation
import simd

/// The kitchen follows an agent's journey: elevator → order rail → prep → cooking (cutting
/// boards for editing, burners for commands) → tasting → serving window, with the service bell in the middle
/// and the break room for finished chefs. Sized for 10 agents in parallel.
enum KitchenLayout {
    static let floor = CGRect(x: -12, y: -8, width: 24, height: 16)
    /// Cabinets that close the gaps between wall stations.
    static let connectors: [CGRect] = [
        .init(x: -9.2, y: -7.8, width: 0.8, height: 1.2),
        .init(x: -3.6, y: -7.8, width: 2.4, height: 1.2),
        .init(x: 8.0, y: -7.8, width: 3.8, height: 1.2),
        .init(x: 10.6, y: -6.6, width: 1.2, height: 2.2),
        .init(x: 10.6, y: 0.4, width: 1.2, height: 7.2)
    ]
    static let areas: [KitchenArea] = [
        .init(id: "elevator", label: "Elevator: new agents arrive", short: "Elevator", footprint: .init(x: -11.6, y: -7.8, width: 2.4, height: 2.0), wall: .freestanding, spots: 1, accent: .init(red: 0.55, green: 0.52, blue: 0.68, alpha: 1)),
        .init(id: "order", label: "Order rail: read the request", short: "Orders", footprint: .init(x: -8.4, y: -7.8, width: 4.8, height: 1.2), wall: .back, spots: 3, accent: .init(red: 0.56, green: 0.67, blue: 0.61, alpha: 1)),
        .init(id: "prep", label: "Prep: planning and research", short: "Prep", footprint: .init(x: -1.2, y: -7.8, width: 9.2, height: 1.2), wall: .back, spots: 6, accent: .init(red: 0.56, green: 0.67, blue: 0.61, alpha: 1)),
        // Two long islands, each worked from the far side so chefs face the camera: one
        // cutting board or burner per chef.
        .init(id: "cooking", label: "Cooking island: editing code", short: "Cooking", footprint: .init(x: -4.5, y: -2.8, width: 9.0, height: 1.2), wall: .front, spots: 6, accent: .init(red: 0.57, green: 0.64, blue: 0.72, alpha: 1)),
        .init(id: "stove", label: "Stove island: running commands", short: "Stove", footprint: .init(x: -4.5, y: 0.6, width: 9.0, height: 1.2), wall: .front, spots: 6, accent: .init(red: 0.69, green: 0.59, blue: 0.47, alpha: 1)),
        .init(id: "tasting", label: "Tasting: tests and QA", short: "Tasting", footprint: .init(x: 10.6, y: -4.4, width: 1.2, height: 4.8), wall: .right, spots: 3, accent: .init(red: 0.64, green: 0.59, blue: 0.72, alpha: 1)),
        // The service gong: a chef that needs you strikes it, then waits in front of it.
        .init(id: "bell", label: "Service gong: needs you", short: "Needs you", footprint: .init(x: -0.9, y: 4.9, width: 1.8, height: 0.6), wall: .freestanding, spots: 6, accent: .init(red: 0.75, green: 0.58, blue: 0.47, alpha: 1)),
        .init(id: "serving", label: "Serving window: ready for review", short: "Serving", footprint: .init(x: 3.2, y: 6.4, width: 7.4, height: 1.2), wall: .front, spots: 5, accent: .init(red: 0.51, green: 0.67, blue: 0.66, alpha: 1)),
        // The break room's side table (its machines, chairs and circles: `BreakRoomLayout`).
        .init(id: "break", label: "Break room: finished agents", short: "Break room", footprint: BreakRoomLayout.sideTable, wall: .island, spots: 10, accent: .init(red: 0.55, green: 0.52, blue: 0.68, alpha: 1)),
        // Where agents fetch what they use: skills (jars), plugins (crates) and MCP servers (appliances).
        .init(id: "pantry", label: "Pantry: skills, plugins and MCP", short: "Pantry", footprint: .init(x: -11.8, y: -3.6, width: 1.2, height: 6.7), wall: .left, spots: 3, accent: .init(red: 0.62, green: 0.43, blue: 0.24, alpha: 1))
    ]
    /// Low partial walls enclosing the break room, with a doorway toward the kitchen.
    static let breakRoomWalls: [CGRect] = [
        .init(x: -12, y: 3.125, width: 6.6, height: 0.15),
        .init(x: -3.475, y: 3.125, width: 0.15, height: 4.875)
    ]
    /// The elevator car's side and back walls; its interior and doorway stay walkable.
    static let elevatorWalls: [CGRect] = [
        .init(x: -11.6, y: -7.8, width: 0.12, height: 2.0),
        .init(x: -9.32, y: -7.8, width: 0.12, height: 2.0)
    ]
}

/// The kitchen's layout and station table under their kitchen names: everything forwards to
/// `SceneLayout.kitchen`, the shared routing (`SceneRouting`) and the chef's proportions
/// (`ChefMetrics`). Change stations in `SceneLayout`.
extension KitchenLayout {
    static var chefScale: Float { ChefMetrics.chefScale }
    static var chefCounterTop: Float { ChefMetrics.chefCounterTop }
    static var chefCounterFront: Float { ChefMetrics.chefCounterFront }
    static var chefHeight: Float { ChefMetrics.chefHeight }
    static var floorTop: CGFloat { ChefMetrics.floorTop }
    static var worktopHeight: Float { ChefMetrics.worktopHeight }
    static var heightScale: Float { ChefMetrics.heightScale }
    static var minimumDwell: Double { ChefMetrics.minimumDwell }
    static var orderReading: Double { ChefMetrics.orderReading }
    static var arrivalWave: Double { ChefMetrics.arrivalWave }

    static var gongCenter: SIMD2<Float> { SceneLayout.kitchen.gongCenter }
    static var gongStrike: ChefStation { SceneLayout.kitchen.gongStrike }
    /// Where the manager comes in from the dining room and leaves again: the open front of the
    /// kitchen between the break room and the serving window.
    static var diningDoor: ChefStation { SceneLayout.kitchen.managerDoor }
    static func managerSpot(talkingTo stand: SIMD2<Float>, others: [SIMD2<Float>]) -> ChefStation {
        SceneLayout.kitchen.managerSpot(talkingTo: stand, others: others)
    }
    static var elevatorLanding: ChefStation { SceneLayout.kitchen.elevatorLanding }

    static func work(for agent: WorkspaceAgent, review: KitchenReviews.State? = nil) -> ChefWork {
        SceneLayout.kitchen.work(for: agent, review: review)
    }
    static func breakRoom(_ agent: WorkspaceAgent, urgent: Bool) -> ChefWork { SceneRouting.rest(agent, urgent: urgent) }
    static func intent(for agent: WorkspaceAgent, at slot: ChefStation?, pickup: ChefStation?, restored: Bool, review: KitchenReviews.State? = nil) -> ChefIntent {
        SceneLayout.kitchen.intent(for: agent, at: slot, pickup: pickup, restored: restored, review: review)
    }
    static func exitIntent(for agent: String) -> ChefIntent { SceneLayout.kitchen.exitIntent(for: agent) }
    static func arrivalIntent(at slot: ChefStation) -> ChefIntent { SceneLayout.kitchen.arrivalIntent(at: slot) }

    static var chefSlots: [String: [ChefStation]] { SceneLayout.kitchen.chefSlots }
    static var chefNavigation: FloorNavigation { SceneLayout.kitchen.chefNavigation }
    static func assignSlots(_ wants: [(id: String, area: String?)], previous: [String: ChefStation]) -> [String: ChefStation] {
        SceneLayout.kitchen.assignSlots(wants, previous: previous)
    }
}
