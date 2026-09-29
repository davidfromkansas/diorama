import Foundation
import os

/// Opt-in in release builds too; no user settings or normal-run event collection.
nonisolated enum ScenePerformance {
    static let enabled = ProcessInfo.processInfo.environment["DIORAMA_PROFILE_SCENE"] == "1"
    static let log = OSLog(subsystem: "local.diorama", category: "ScenePerformance")
    static func disabled(_ feature: String) -> Bool {
        enabled && ProcessInfo.processInfo.environment["DIORAMA_DISABLE_" + feature] == "1"
    }
    static func begin(_ name: StaticString) -> OSSignpostID {
        guard enabled else { return .invalid }
        let id = OSSignpostID(log: log); os_signpost(.begin, log: log, name: name, signpostID: id); return id
    }
    static func end(_ name: StaticString, _ id: OSSignpostID) {
        if enabled { os_signpost(.end, log: log, name: name, signpostID: id) }
    }
}

/// Frame intervals are telemetry, not assumed to be GPU execution time.
nonisolated struct SceneQualityPolicy {
    var level = 0
    private var slowSince: Double?
    private var fastSince: Double?
    mutating func observe(gpuSeconds: Double?, now: Double, targetFPS: Int) -> Bool {
        guard let gpuSeconds else { return false }
        let budget = 1 / Double(targetFPS)
        if gpuSeconds > budget {
            fastSince = nil
            if slowSince == nil { slowSince = now }
            if now - (slowSince ?? now) >= 2 && level < 4 { level += 1; slowSince = nil; return true }
        } else if gpuSeconds < budget * 0.75 {
            slowSince = nil
            if fastSince == nil { fastSince = now }
            if now - (fastSince ?? now) >= 10 && level > 0 { level -= 1; fastSince = nil; return true }
        } else { slowSince = nil; fastSince = nil }
        return false
    }
}
