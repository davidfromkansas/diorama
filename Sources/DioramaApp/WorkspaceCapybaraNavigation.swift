import Foundation
import simd

/// A small visibility-smoothed A* grid on the workspace floor. Obstacles already include body clearance.
struct WorkspaceCapybaraNavigation {
    struct Obstacle {
        let min: SIMD2<Float>
        let max: SIMD2<Float>
        func contains(_ p: SIMD2<Float>) -> Bool { p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y }
        func intersects(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
            let d = b-a
            var low: Float = 0, high: Float = 1
            for axis in 0..<2 {
                if abs(d[axis]) < 0.00001 { if a[axis] < min[axis] || a[axis] > max[axis] { return false } }
                else {
                    let x = (min[axis]-a[axis])/d[axis], y = (max[axis]-a[axis])/d[axis]
                    low = Swift.max(low,Swift.min(x,y)); high = Swift.min(high,Swift.max(x,y))
                    if low > high { return false }
                }
            }
            return true
        }
    }
    var obstacles: [Obstacle] = []
    var min = SIMD2<Float>(-9, -9)
    var max = SIMD2<Float>(9, 9)
    let spacing: Float = 0.5
    func isFree(_ p: SIMD2<Float>) -> Bool {
        p.x >= min.x && p.y >= min.y && p.x <= max.x && p.y <= max.y && !obstacles.contains { $0.contains(p) }
    }
    func clear(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool { isFree(a) && isFree(b) && !obstacles.contains { $0.intersects(a,b) } }
    func route(from start: SIMD2<Float>, to goal: SIMD2<Float>) -> [SIMD2<Float>]? {
        guard isFree(start), isFree(goal) else { return nil }
        if clear(start,goal) { return [goal] }
        let width = Int((max.x-min.x)/spacing)+1, height = Int((max.y-min.y)/spacing)+1
        func point(_ id: Int) -> SIMD2<Float> { min+SIMD2(Float(id%width),Float(id/width))*spacing }
        func nearest(_ p: SIMD2<Float>) -> Int? {
            (0..<width*height).filter { clear(p,point($0)) }.min { simd_distance_squared(point($0),p)<simd_distance_squared(point($1),p) }
        }
        guard let first = nearest(start), let last = nearest(goal) else { return nil }
        var open: Set<Int> = [first], closed = Set<Int>(), costs: [Int:Float] = [first:0], parents: [Int:Int] = [:]
        while let current = open.min(by: { costs[$0,default:.infinity]+simd_distance(point($0),goal) < costs[$1,default:.infinity]+simd_distance(point($1),goal) }) {
            if current == last {
                var path = [goal,point(last)], id = last
                while let parent = parents[id] { path.append(point(parent)); id = parent }
                path.append(start); path.reverse()
                var result: [SIMD2<Float>] = [], cursor = 0
                while cursor < path.count-1 {
                    var next = path.count-1
                    while next>cursor+1 && !clear(path[cursor],path[next]) { next-=1 }
                    result.append(path[next]);cursor=next
                }
                return result
            }
            open.remove(current);closed.insert(current)
            for dx in -1...1 { for dy in -1...1 where dx != 0 || dy != 0 {
                let x = current%width+dx, y = current/width+dy
                guard x>=0,y>=0,x<width,y<height else { continue }
                let next = y*width+x
                guard !closed.contains(next),clear(point(current),point(next)) else { continue }
                let cost = costs[current,default:0]+simd_distance(point(current),point(next))
                if cost < costs[next,default:.infinity] { costs[next]=cost;parents[next]=current;open.insert(next) }
            }}
        }
        return nil
    }
}
