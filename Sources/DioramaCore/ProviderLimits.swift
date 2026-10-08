import Foundation

extension Provider: Codable {}

/// The weekly allowance of one provider subscription, as last reported by the provider.
public struct LimitWindow: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case ok, warning, exhausted, unknown }
    public var provider: Provider
    /// Nil when the provider reported only a status, never zero by assumption.
    public var usedPercent: Double?
    public var resetsAt: Date?
    public var status: Status
    public var observedAt: Date
    public init(provider: Provider, usedPercent: Double?, resetsAt: Date?, status: Status, observedAt: Date) {
        self.provider = provider; self.usedPercent = usedPercent; self.resetsAt = resetsAt; self.status = status; self.observedAt = observedAt
    }
    public var leftPercent: Double? { usedPercent.map { max(0, min(100, 100 - $0)) } }
    /// A window whose reset time has passed no longer describes the current allowance.
    public func expired(now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }
}

/// Reads weekly limits from what Claude Code and Codex already report; nothing here starts a session.
public enum ProviderLimits {
    static let week = 7 * 24 * 60

    /// Codex reports `rate_limits` on every `token_count` transcript row (snake_case) and from the
    /// app server (`rateLimits`, camelCase). The weekly window may be `primary` or `secondary`.
    public static func codexWeekly(_ value: WireValue, at time: Date) -> LimitWindow? {
        let limits = value["rateLimits"] != .null ? value["rateLimits"] : value
        let id = (limits["limit_id"].string ?? limits["limitId"].string)
        guard id == nil || id == "codex" else { return nil }
        for key in ["primary", "secondary"] {
            let window = limits[key]
            let minutes = window["window_minutes"].number ?? window["windowDurationMins"].number
            guard let minutes, Int(minutes) == week, let used = window["used_percent"].number ?? window["usedPercent"].number else { continue }
            let reset = (window["resets_at"].number ?? window["resetsAt"].number).map { Date(timeIntervalSince1970: $0) }
                ?? window["resets_in_seconds"].number.map { time.addingTimeInterval($0) }
            let reached = limits["rate_limit_reached_type"].string != nil
            return LimitWindow(provider: .codex, usedPercent: used, resetsAt: reset,
                               status: reached || used >= 100 ? .exhausted : used >= 80 ? .warning : .ok, observedAt: time)
        }
        return nil
    }
    public static func codexPlan(_ value: WireValue) -> String? {
        let limits = value["rateLimits"] != .null ? value["rateLimits"] : value
        return limits["plan_type"].string ?? limits["planType"].string
    }
    /// Claude Code's `rate_limit_event` info. `utilization` is optional and may be a fraction.
    public static func claudeWeekly(_ info: WireValue, at time: Date) -> LimitWindow? {
        guard info["rateLimitType"].string == "seven_day" else { return nil }
        let used = info["utilization"].number.map { $0 <= 1 ? $0 * 100 : $0 }
        let status: LimitWindow.Status = switch info["status"].string {
        case "rejected": .exhausted
        case "allowed_warning": .warning
        case "allowed": (used ?? 0) >= 80 ? .warning : .ok
        default: .unknown
        }
        return LimitWindow(provider: .claude, usedPercent: used, resetsAt: info["resetsAt"].number.map { Date(timeIntervalSince1970: $0) },
                           status: status, observedAt: time)
    }
    /// Claude Code's own `/usage` report, run without a model call, transcript or hooks.
    public static let claudeUsageArguments = ["-p", "/usage", "--no-session-persistence", "--settings", #"{"disableAllHooks":true}"#, "--output-format", "json"]
    /// Reads "Current week (all models): 18% used · resets Oct 11 at 2pm (America/Los_Angeles)" from that report.
    public static func claudeWeekly(usageReport data: Data, now: Date = Date()) -> LimitWindow? {
        guard let reply = try? JSONDecoder().decode(WireValue.self, from: data), let text = reply["result"].string else { return nil }
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("Current week (all models):") }),
              let match = line.firstMatch(of: /(\d+(?:\.\d+)?)% used(?: · resets (.+?) \((.+)\))?/), let used = Double(match.1) else { return nil }
        let reset = match.2.flatMap { day in match.3.flatMap { zone in resetDate(String(day), zone: String(zone), now: now) } }
        return LimitWindow(provider: .claude, usedPercent: used, resetsAt: reset, status: used >= 100 ? .exhausted : used >= 80 ? .warning : .ok, observedAt: now)
    }
    /// "Oct 11 at 2pm" or "Oct 11 at 2:30pm" in the given zone; the report omits the year.
    static func resetDate(_ text: String, zone: String, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: zone)
        formatter.amSymbol = "am"; formatter.pmSymbol = "pm"
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = formatter.timeZone
        let year = calendar.component(.year, from: now)
        for format in ["MMM d 'at' ha yyyy", "MMM d 'at' h:mma yyyy"] {
            formatter.dateFormat = format
            guard let date = formatter.date(from: text + " \(year)") else { continue }
            // A reset is in the future; a date well in the past belongs to next year.
            return date < now.addingTimeInterval(-86_400) ? calendar.date(byAdding: .year, value: 1, to: date) : date
        }
        return nil
    }
    /// `claude auth status` prints JSON that includes `subscriptionType`.
    public static func claudePlan(authStatus data: Data) -> String? {
        (try? JSONDecoder().decode(WireValue.self, from: data))?["subscriptionType"].string
    }
    public static func planName(_ provider: Provider, _ raw: String?) -> String {
        let brand = provider == .claude ? "Claude" : "ChatGPT"
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return brand }
        let tier = ["business": "Business", "edu": "Edu"][raw] ?? raw.prefix(1).uppercased() + raw.dropFirst()
        return brand + " " + tier
    }
    /// Newer reports replace older ones, except that a status-only report never erases a known
    /// percentage for the same reset.
    public static func merge(_ old: LimitWindow?, _ new: LimitWindow) -> LimitWindow {
        guard let old else { return new }
        guard new.observedAt >= old.observedAt else { return old }
        var merged = new
        if merged.usedPercent == nil, merged.resetsAt == nil || merged.resetsAt == old.resetsAt {
            merged.usedPercent = old.usedPercent; merged.resetsAt = merged.resetsAt ?? old.resetsAt
        }
        return merged
    }

    /// The newest `rate_limits` in a Codex transcript, read from its tail only.
    public static func latestCodexRateLimits(_ url: URL, tail: Int = 256 * 1024) -> (value: WireValue, at: Date)? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return nil }
        try? file.seek(toOffset: size > UInt64(tail) ? size - UInt64(tail) : 0)
        guard let data = try? file.readToEnd() else { return nil }
        // The first line may be cut by the tail boundary and the last may be half written; both fail to decode.
        for line in data.split(separator: 10).reversed() {
            guard let row = try? JSONDecoder().decode(WireValue.self, from: Data(line)) else { continue }
            let payload = row["payload"]
            guard payload["type"].string == "token_count", payload["rate_limits"] != .null else { continue }
            return (payload["rate_limits"], ActivityParser.date(row["timestamp"].string) ?? Date())
        }
        return nil
    }
}

/// Last known limits and plans, kept so Home shows them immediately after a relaunch.
public struct ProviderLimitsCache: Codable, Equatable, Sendable {
    public var weekly: [String: LimitWindow] = [:]
    public var plans: [String: String] = [:]
    public var claudePlanCheckedAt: Date?
    public var claudeUsageCheckedAt: Date?
    public init() {}
    public static func load(_ url: URL?) -> Self {
        guard let url, let data = try? Data(contentsOf: url) else { return Self() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(Self.self, from: data)) ?? Self()
    }
    public func save(_ url: URL?) {
        guard let url else { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
