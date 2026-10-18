import Testing
import simd
@testable import DioramaApp

@MainActor struct FloorNavigationTests {
    @Test func routingAvoidsFurnitureAndRejectsBlockedTargets() {
        var nav = FloorNavigation()
        nav.obstacles = [.init(min:SIMD2(-1,-1),max:SIMD2(1,1))]
        let start=SIMD2<Float>(-3,0),goal=SIMD2<Float>(3,0)
        let route=nav.route(from:start,to:goal)
        #expect(route != nil)
        var previous=start
        for p in route ?? [] { #expect(nav.clear(previous,p));previous=p }
        #expect(previous==goal)
        #expect(nav.route(from:start,to:.zero)==nil)
        #expect(nav.route(from:start,to:SIMD2(50,50))==nil)
    }
}
