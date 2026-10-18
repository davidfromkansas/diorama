import AppKit
import simd

/// The startup office: a new teammate steps out of the elevator, reads its ticket at the board,
/// plans at the whiteboards, writes code at the desks and runs it at the server rack, tests at the
/// QA bench, rings the manager's desk bell when it needs you, presents finished work at the demo
/// table and unwinds in the lounge; skills, plugins and MCP servers come from the supply closet.
/// The same floor plan as the kitchen (24 × 16, same footprints), so slots, walkways and the
/// camera's framing carry over; only the fixtures, light and props differ.
extension SceneLayout {
    static let office = SceneLayout(kind: .office, floor: KitchenLayout.floor, areas: OfficeLayout.areas,
                                    connectors: KitchenLayout.connectors, partitionWalls: KitchenLayout.breakRoomWalls,
                                    arrivalWalls: KitchenLayout.elevatorWalls, lounge: .kitchen,
                                    managerDoor: ChefStation(id: "lobby door", area: "door", stand: SIMD2(1.9, Float(KitchenLayout.floor.maxY) - 0.6), facing: .pi),
                                    restSign: KitchenFloor.rug, dressing: .office)
}

enum OfficeLayout {
    /// Pastel accents, one per station.
    static let sage = NSColor(srgbRed: 0.62, green: 0.77, blue: 0.66, alpha: 1)
    static let peach = NSColor(srgbRed: 0.95, green: 0.72, blue: 0.60, alpha: 1)
    static let lilac = NSColor(srgbRed: 0.74, green: 0.68, blue: 0.87, alpha: 1)
    static let sky = NSColor(srgbRed: 0.62, green: 0.77, blue: 0.91, alpha: 1)
    static let butter = NSColor(srgbRed: 0.96, green: 0.85, blue: 0.55, alpha: 1)
    static let coral = NSColor(srgbRed: 0.93, green: 0.58, blue: 0.55, alpha: 1)
    static let mint = NSColor(srgbRed: 0.60, green: 0.84, blue: 0.80, alpha: 1)

    /// The kitchen's footprints under the office's names (`KitchenLayout.areas`).
    static let areas: [SceneArea] = KitchenLayout.areas.map { area in
        let (label, short, accent): (String, String, NSColor) = switch area.id {
        case "elevator": ("Elevator: new teammates arrive", "Elevator", lilac)
        case "order": ("Ticket board: read the request", "Tickets", butter)
        case "prep": ("Whiteboards: planning and research", "Whiteboards", sage)
        case "cooking": ("Desks: editing code", "Desks", sky)
        case "stove": ("Server rack: running commands", "Servers", peach)
        case "tasting": ("QA bench: tests and checks", "QA", lilac)
        case "bell": ("Manager's bell: needs you", "Needs you", coral)
        case "serving": ("Demo table: ready for review", "Demo", mint)
        case "break": ("Lounge: finished agents", "Lounge", lilac)
        case "pantry": ("Supply closet: skills, plugins and MCP", "Supplies", butter)
        default: (area.label, area.short, area.accent)
        }
        return SceneArea(id: area.id, label: label, short: short, footprint: area.footprint, wall: area.wall, spots: area.spots, accent: accent)
    }
}

extension SceneDressing {
    /// Office chefs type at their desks and watch the rack with empty hands (no knife, no tasting
    /// spoon), carry a deliverable box rather than a plate, and ring the desk bell as they arrive
    /// instead of striking a gong.
    static let office = SceneDressing(dress: { work in
        var work = work
        if work.hand == .knife || work.hand == .spoon { work.hand = nil }
        return work
    }, arrivalHand: .ticket, strikesNeedsYou: false, servingHand: .plate)
}
