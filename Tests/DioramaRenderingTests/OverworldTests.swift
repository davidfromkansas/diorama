import Foundation
import SwiftUI
import simd
import Testing
@testable import DioramaApp

@MainActor struct OverworldTests {
    @Test func districtsComeFromTheGitHubOwner() {
        #expect(OverworldDistrictKey.of(remote: "git@github.com:Acme/x.git") == .github(owner: "acme"))
        #expect(OverworldDistrictKey.of(remote: "https://github.com/acme/y") == .github(owner: "acme"))
        #expect(OverworldDistrictKey.of(remote: "https://gitlab.com/acme/z.git") == .local)
        #expect(OverworldDistrictKey.of(remote: nil) == .local)
        #expect(OverworldDistrictKey.of(remote: "not a remote") == .local)
    }

    @Test func lotsAreStableAppendOnlyAndReused() throws {
        let a = OverworldDistrictKey.github(owner: "a"), b = OverworldDistrictKey.github(owner: "b")
        let first = OverworldLotLedger().assigning([("p1", .local), ("p2", a), ("p3", a), ("p4", b)])
        #expect(first == OverworldLotLedger().assigning([("p1", .local), ("p2", a), ("p3", a), ("p4", b)]))
        #expect(first.districts == [a, b, .local])
        #expect(first.lots["p3"] == .init(district: a, index: 1))

        // A new project appends without moving anyone.
        let grown = first.assigning([("p1", .local), ("p2", a), ("p3", a), ("p4", b), ("p5", a)])
        for id in ["p1", "p2", "p3", "p4"] { #expect(grown.lots[id] == first.lots[id]) }
        #expect(grown.lots["p5"] == .init(district: a, index: 2))

        // A removed project frees its lot for the next newcomer.
        let shrunk = grown.assigning([("p1", .local), ("p3", a), ("p4", b), ("p5", a)])
        #expect(shrunk.lots["p2"] == nil)
        let refilled = shrunk.assigning([("p1", .local), ("p3", a), ("p4", b), ("p5", a), ("p6", a)])
        #expect(refilled.lots["p6"] == .init(district: a, index: 0))

        let decoded = try JSONDecoder().decode(OverworldLotLedger.self, from: JSONEncoder().encode(refilled))
        #expect(decoded == refilled)
    }

    @Test func growingOneDistrictLeavesOthersInPlace() {
        let a = OverworldDistrictKey.github(owner: "a"), b = OverworldDistrictKey.github(owner: "b")
        let small = OverworldLotLedger().assigning([("a1", a), ("b1", b)])
        let big = small.assigning([("a1", a), ("b1", b), ("a2", a), ("a3", a), ("a4", a)])
        let before = OverworldLayout(ledger: small), after = OverworldLayout(ledger: big)
        // Districts grow in rows, never sideways, so the next district keeps its place.
        #expect(before.lot(for: "b1")?.origin == after.lot(for: "b1")?.origin)
        #expect(after.districts[0].rows == 2)
        let (low, high) = after.bounds
        for lot in after.lots {
            #expect(lot.origin.x >= low.x && lot.origin.x + PortfolioMassing.block <= high.x)
            #expect(lot.origin.y >= low.y && lot.origin.y + PortfolioMassing.block <= high.y)
        }
    }

    @Test func busRoutesFollowStreetsToTheDoor() throws {
        let a = OverworldDistrictKey.github(owner: "a"), b = OverworldDistrictKey.github(owner: "b")
        let ledger = OverworldLotLedger().assigning([("a1", a), ("a2", a), ("a3", a), ("a4", a), ("b1", b), ("b2", b)])
        let layout = OverworldLayout(ledger: ledger)
        let from = try #require(layout.lot(for: "a4")), to = try #require(layout.lot(for: "b2"))
        let path = layout.route(from: from.door, to: to)
        #expect(path.first == from.door)
        #expect(path.last == to.door)
        for (p, q) in zip(path, path.dropFirst()) {
            #expect(abs(p.x - q.x) < 1e-9 || abs(p.y - q.y) < 1e-9, "segment \(p) → \(q) leaves the street grid")
        }
        // Crossing to another district goes over the avenue.
        #expect(path.contains { abs($0.y - OverworldLayout.street / 2) < 1e-9 })
    }

    @Test func projectionRoundTripsAndCameraZoomsAroundTheCursor() {
        let projection = OverworldProjection(unit: 7.5, origin: CGPoint(x: 120, y: -40))
        let ground = projection.ground(projection.screen(12.25, 3.5))
        #expect(abs(ground.x - 12.25) < 1e-9 && abs(ground.y - 3.5) < 1e-9)

        let layout = OverworldLayout(ledger: OverworldLotLedger().assigning([("a", .local), ("b", .local), ("c", .local), ("d", .local)]))
        let size = CGSize(width: 800, height: 500)
        let fitted = OverworldCamera.fit(layout, height: 20, size: size)
        let view = fitted.projection(size: size)
        let (low, high) = layout.bounds
        for corner in [low, high, SIMD2(low.x, high.y), SIMD2(high.x, low.y)] {
            let p = view.screen(corner)
            #expect(p.x >= 0 && p.x <= size.width && p.y >= 0 && p.y <= size.height)
        }
        let anchor = CGPoint(x: 300, y: 200)
        let zoomed = fitted.zoomed(by: 2, anchor: anchor, size: size, minUnit: 1)
        let held = fitted.projection(size: size).ground(anchor), after = zoomed.projection(size: size).ground(anchor)
        #expect(simd_distance(held, after) < 1e-6)
        #expect(fitted.zoomed(by: 1000, anchor: anchor, size: size, minUnit: 1).unit == OverworldCamera.maxUnit)
    }

    @Test func clicksHitTheTallestBuildingFirst() throws {
        let ledger = OverworldLotLedger().assigning([("back", .local), ("front", .local), ("c", .local), ("d", .local)])
        let layout = OverworldLayout(ledger: ledger)
        let tower = PortfolioMassing(.empire, metrics: .init(width: 4, depth: 4, floors: 9))
        let low = PortfolioMassing(.walkup, metrics: .init(width: 2, depth: 2, floors: 2))
        let massings = ["back": tower, "front": low, "c": low, "d": low]
        let projection = OverworldProjection(unit: 6, origin: CGPoint(x: 400, y: 120))
        let backLot = try #require(layout.lot(for: "back"))
        let spire = tower.peak
        let tip = projection.screen(backLot.origin.x + spire.x, backLot.origin.y + spire.y, spire.z - 0.3)
        #expect(OverworldHit.project(at: tip, layout: layout, massings: massings, projection) == "back")
        // The street in front of the front row is nobody's building.
        let street = projection.screen(try #require(layout.lot(for: "d")).door)
        #expect(OverworldHit.project(at: street, layout: layout, massings: massings, projection) == nil)
    }

    @Test func busTripsAreBrief() {
        let short = OverworldBus(path: [.zero, SIMD2(1, 0)], start: .now, target: "x")
        let long = OverworldBus(path: [.zero, SIMD2(400, 0)], start: .now, target: "x")
        #expect(short.duration == 0.45)
        #expect(long.duration == 1.2)
        #expect(long.position(after: 0).point == .zero)
        #expect(long.position(after: 5).point == SIMD2(400, 0))
    }
}
