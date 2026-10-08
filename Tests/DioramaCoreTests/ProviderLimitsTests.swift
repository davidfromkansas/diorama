import Foundation
import Testing
@testable import DioramaCore

struct ProviderLimitsTests {
    private func wire(_ value: String) throws -> WireValue { try JSONDecoder().decode(WireValue.self, from: Data(value.utf8)) }
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func codexTranscriptWeeklyWindowIsFoundInEitherSlot() throws {
        let primary = try wire(#"{"limit_id":"codex","primary":{"used_percent":23.0,"window_minutes":10080,"resets_at":1791747415},"secondary":null,"plan_type":"pro","rate_limit_reached_type":null}"#)
        let window = try #require(ProviderLimits.codexWeekly(primary, at: now))
        #expect(window.usedPercent == 23 && window.leftPercent == 77 && window.status == .ok)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_791_747_415))
        #expect(ProviderLimits.codexPlan(primary) == "pro")
        let secondary = try wire(#"{"limit_id":"codex","primary":{"used_percent":90,"window_minutes":300,"resets_at":1},"secondary":{"used_percent":85,"window_minutes":10080,"resets_at":1791747415}}"#)
        #expect(ProviderLimits.codexWeekly(secondary, at: now)?.usedPercent == 85)
        #expect(ProviderLimits.codexWeekly(secondary, at: now)?.status == .warning)
        let model = try wire(#"{"limit_id":"codex_bengalfox","primary":{"used_percent":5,"window_minutes":10080,"resets_at":1}}"#)
        #expect(ProviderLimits.codexWeekly(model, at: now) == nil)
    }
    @Test func codexAppServerShapeIsCamelCase() throws {
        let value = try wire(#"{"rateLimits":{"primary":{"usedPercent":15,"windowDurationMins":10080,"resetsAt":1791747415},"planType":"plus"}}"#)
        #expect(ProviderLimits.codexWeekly(value, at: now)?.usedPercent == 15)
        #expect(ProviderLimits.codexPlan(value) == "plus")
    }
    @Test func claudeEventsMayOmitUtilization() throws {
        let fraction = try wire(#"{"status":"allowed","rateLimitType":"seven_day","utilization":0.42,"resetsAt":1791747415}"#)
        #expect(ProviderLimits.claudeWeekly(fraction, at: now)?.usedPercent == 42)
        let statusOnly = try wire(#"{"status":"allowed_warning","rateLimitType":"seven_day","resetsAt":1791747415}"#)
        let window = try #require(ProviderLimits.claudeWeekly(statusOnly, at: now.addingTimeInterval(60)))
        #expect(window.usedPercent == nil && window.status == .warning)
        #expect(ProviderLimits.claudeWeekly(try wire(#"{"status":"allowed","rateLimitType":"five_hour"}"#), at: now) == nil)
        let merged = ProviderLimits.merge(ProviderLimits.claudeWeekly(fraction, at: now), window)
        #expect(merged.usedPercent == 42 && merged.status == .warning)
        #expect(ProviderLimits.merge(window, try #require(ProviderLimits.claudeWeekly(fraction, at: now))) == window)
    }
    @Test func plansAndExpiry() {
        #expect(ProviderLimits.claudePlan(authStatus: Data(#"{"loggedIn":true,"subscriptionType":"max"}"#.utf8)) == "max")
        #expect(ProviderLimits.planName(.claude, "max") == "Claude Max")
        #expect(ProviderLimits.planName(.codex, "pro") == "ChatGPT Pro")
        #expect(ProviderLimits.planName(.codex, nil) == "ChatGPT")
        let window = LimitWindow(provider: .codex, usedPercent: 50, resetsAt: now, status: .ok, observedAt: now)
        #expect(window.expired(now: now.addingTimeInterval(1)) && !window.expired(now: now.addingTimeInterval(-1)))
    }
    @Test func transcriptTailFindsTheNewestLimitsAndSkipsAHalfWrittenLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        func row(_ used: Int) -> String {
            #"{"timestamp":"2026-10-06T20:54:17.964Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":"# + "\(used)" + #","window_minutes":10080,"resets_at":1791747415}}}}"#
        }
        try Data((row(10) + "\n" + row(23) + "\n" + #"{"type":"event_msg","payload":{"type":"agent_message"}}"# + "\n" + #"{"payload":{"type":"tok"#).utf8).write(to: url)
        let latest = try #require(ProviderLimits.latestCodexRateLimits(url))
        #expect(ProviderLimits.codexWeekly(latest.value, at: latest.at)?.usedPercent == 23)
    }
    @Test func cacheRoundTrips() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var cache = ProviderLimitsCache()
        cache.weekly["codex"] = LimitWindow(provider: .codex, usedPercent: 23, resetsAt: now, status: .ok, observedAt: now)
        cache.plans["claude"] = "max"
        cache.save(url)
        #expect(ProviderLimitsCache.load(url) == cache)
    }
    @Test func claudeUsageReportGivesTheWeeklyAllModelsLine() throws {
        let text = "You are currently using your subscription\\n\\nCurrent session: 16% used · resets Oct 6 at 7pm (America/Los_Angeles)\\nCurrent week (all models): 18% used · resets Oct 11 at 2pm (America/Los_Angeles)\\nCurrent week (Fable): 0% used · resets Oct 11 at 2pm (America/Los_Angeles)"
        let report = Data(("{\"result\":\"" + text + "\",\"num_turns\":0}").utf8)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-06T22:00:00Z"))
        let window = try #require(ProviderLimits.claudeWeekly(usageReport: report, now: now))
        #expect(window.usedPercent == 18 && window.status == .ok)
        #expect(window.resetsAt == ISO8601DateFormatter().date(from: "2026-10-11T21:00:00Z"))
        let halfHour = ProviderLimits.resetDate("Jan 2 at 2:30pm", zone: "UTC", now: now)
        #expect(halfHour == ISO8601DateFormatter().date(from: "2027-01-02T14:30:00Z"))
        #expect(ProviderLimits.claudeWeekly(usageReport: Data(#"{"result":"Usage unavailable"}"#.utf8), now: now) == nil)
    }
}
