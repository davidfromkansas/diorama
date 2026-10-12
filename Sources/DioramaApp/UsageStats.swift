import Foundation

/// Anonymous usage stats: Diorama tells trydiorama.com, once each, when an install first opens the
/// app and when it first adds a project. Each report carries a random install ID, the app version
/// and build, and the macOS version; never code, prompts, project names, paths or account details.
/// On unless turned off in onboarding or Settings. Tests, demos and development builds never send
/// (`DIORAMA_USAGE_ENDPOINT` points a development build at a test endpoint).
@MainActor final class UsageStats {
    enum Event: String, CaseIterable { case firstLaunch = "first_launch", firstProject = "first_project" }

    static let shared = UsageStats()
    static let enabledKey = "shareUsageStats"
    static let installKey = "usageInstallID"
    static let disclosure = "A random install ID, the app and macOS version, and when you first open Diorama and add a project. Never your code, prompts, project names or files."
    static let defaultEndpoint = URL(string: "https://trydiorama.com/api/events")!
    /// Where reports go, or nil where nothing may be sent (tests, demos, development builds).
    static var configuredEndpoint: URL? {
        if let override = ProcessInfo.processInfo.environment["DIORAMA_USAGE_ENDPOINT"], let url = URL(string: override) { return url }
        let development = Bundle.main.url(forResource: "DevelopmentRoot", withExtension: "txt") != nil
        guard KitchenLog.enabled, !DemoMode.active, !development else { return nil }
        return defaultEndpoint
    }

    private let defaults: UserDefaults
    private let endpoint: URL?
    private let post: (URLRequest) async throws -> Int
    private var sending: Set<Event> = []

    init(defaults: UserDefaults = .standard, endpoint: URL? = UsageStats.configuredEndpoint,
         post: @escaping (URLRequest) async throws -> Int = UsageStats.post) {
        self.defaults = defaults; self.endpoint = endpoint; self.post = post
    }

    var enabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
    private static func sentKey(_ event: Event) -> String { "usageSent." + event.rawValue }
    private static func pendingKey(_ event: Event) -> String { "usagePending." + event.rawValue }

    /// Notes a milestone and sends it; one that doesn't go through is sent again on a later launch.
    /// Nothing is noted while sharing is off, so turning it on later never reports the past.
    func record(_ event: Event) {
        guard endpoint != nil, enabled, !defaults.bool(forKey: Self.sentKey(event)) else { return }
        defaults.set(true, forKey: Self.pendingKey(event))
        flush()
    }
    /// Sends milestones still waiting from an earlier launch.
    func flush() {
        guard let endpoint, enabled else { return }
        for event in Event.allCases where defaults.bool(forKey: Self.pendingKey(event)) && !defaults.bool(forKey: Self.sentKey(event)) && !sending.contains(event) {
            sending.insert(event)
            let request = Self.request(endpoint, event: event, install: install)
            Task { @MainActor in
                let status = (try? await post(request)) ?? 0
                sending.remove(event)
                guard (200..<300).contains(status) else { return }
                defaults.set(true, forKey: Self.sentKey(event))
                defaults.removeObject(forKey: Self.pendingKey(event))
            }
        }
    }

    /// The random install ID, made the first time a report is sent.
    private var install: String {
        if let id = defaults.string(forKey: Self.installKey), UUID(uuidString: id) != nil { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Self.installKey)
        return id
    }
    static func request(_ endpoint: URL, event: Event, install: String) -> URLRequest {
        let info = Bundle.main.infoDictionary
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = [system.majorVersion, system.minorVersion] + (system.patchVersion > 0 ? [system.patchVersion] : [])
        let body: [String: String] = [
            "install": install, "event": event.rawValue,
            "version": info?["CFBundleShortVersionString"] as? String ?? "",
            "build": info?["CFBundleVersion"] as? String ?? "",
            "macOS": macOS.map(String.init).joined(separator: "."),
        ]
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
    nonisolated static func post(_ request: URLRequest) async throws -> Int {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
