import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct UsageStatsTests {
    private final class Sent: @unchecked Sendable { var requests: [URLRequest] = []; var status = 200 }
    private func stats(_ defaults: UserDefaults, endpoint: URL? = URL(string: "https://example.test/api/events"), sent: Sent) -> UsageStats {
        UsageStats(defaults: defaults, endpoint: endpoint) { request in sent.requests.append(request); return sent.status }
    }
    private func fresh() -> UserDefaults {
        let name = "usage-stats-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
    private func settle() async { for _ in 0..<20 { await Task.yield() } }
    private func body(_ request: URLRequest) -> [String: String] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: String] ?? [:]
    }

    @Test func eachMilestoneIsSentOnceWithAnAnonymousInstallID() async {
        let defaults = fresh(), sent = Sent(), usage = stats(defaults, sent: sent)
        usage.record(.firstLaunch); await settle()
        usage.record(.firstLaunch); usage.record(.firstProject); await settle()
        usage.record(.firstProject); usage.flush(); await settle()
        #expect(sent.requests.map { body($0)["event"] } == ["first_launch", "first_project"])
        let first = body(sent.requests[0])
        #expect(UUID(uuidString: first["install"] ?? "") != nil)
        #expect(first["install"] == body(sent.requests[1])["install"], "One install ID for both milestones")
        #expect(Set(first.keys) == ["install", "event", "version", "build", "macOS"], "Nothing else leaves the Mac")
        #expect(sent.requests[0].httpMethod == "POST" && sent.requests[0].url?.absoluteString == "https://example.test/api/events")
    }

    @Test func aFailedReportIsSentAgainLater() async {
        let defaults = fresh(), sent = Sent()
        sent.status = 503
        stats(defaults, sent: sent).record(.firstProject); await settle()
        #expect(sent.requests.count == 1)
        sent.status = 200
        let relaunched = stats(defaults, sent: sent)
        relaunched.flush(); await settle()
        #expect(sent.requests.count == 2)
        relaunched.flush(); await settle()
        #expect(sent.requests.count == 2, "Sent; never again")
    }

    @Test func turningSharingOffSendsNothingNowOrLater() async {
        let defaults = fresh(), sent = Sent(), usage = stats(defaults, sent: sent)
        defaults.set(false, forKey: UsageStats.enabledKey)
        usage.record(.firstLaunch); usage.record(.firstProject); await settle()
        defaults.set(true, forKey: UsageStats.enabledKey)
        usage.flush(); await settle()
        #expect(sent.requests.isEmpty, "Milestones reached while off are never reported")
    }

    @Test func testsDemosAndDevelopmentBuildsHaveNowhereToSend() async {
        #expect(UsageStats.configuredEndpoint == nil || ProcessInfo.processInfo.environment["DIORAMA_USAGE_ENDPOINT"] != nil)
        let defaults = fresh(), sent = Sent()
        stats(defaults, endpoint: nil, sent: sent).record(.firstProject); await settle()
        #expect(sent.requests.isEmpty)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("usage") }.isEmpty, "Nothing is even noted")
    }

    @Test func onlyANewProjectCountsAsAdded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ProjectModel(storageURL: root.appendingPathComponent("projects.json"))
        let project = DioramaProject(name: "A", folder: root.appendingPathComponent("a").path, commonDirectory: "", base: "main", remote: nil)
        model.add(project); model.add(project)
        #expect(model.projects.count == 1, "Adding the same folder again selects it; the usage hook runs only on the first")
    }
}
