import Foundation
import Testing
@testable import DioramaCore

@Suite struct ProjectServersTests {
    let roots = [LocalServerRoot(project: "p", folder: "/work/app"), LocalServerRoot(project: "nested", folder: "/work/app/inner"), LocalServerRoot(project: "p", folder: "/work/trees/feature")]
    func process(_ pid: Int32, _ folder: String, parent: Int32 = 0, endpoints: [String] = ["*:3000"]) -> LocalServerProcess {
        .init(pid: pid, parent: parent, started: UInt64(pid), name: "node", folder: folder, endpoints: endpoints)
    }
    @Test func projectAndWorktreeOwnership() {
        let rows = ProjectServerDiscovery.match([process(10, "/work/app/src"), process(11, "/work/app/inner"), process(12, "/work/trees/feature"), process(13, "/work/apple")], roots: roots, links: [])
        #expect(rows.map(\.project) == ["p", "nested", "p"])
    }
    @Test func ancestryAndAmbiguousOwnership() {
        let rows = ProjectServerDiscovery.match([process(10, "/work/app", endpoints: []), process(11, "", parent: 10)], roots: roots, links: [])
        #expect(rows.count == 1 && rows.first?.confirmed == true)
        #expect(ProjectServerDiscovery.match([process(10, "/work/app")], roots: roots + [.init(project: "other", folder: "/work/app")], links: []).isEmpty)
    }
    @Test func possibleMatchesNeverCountAsConfirmed() throws {
        let links = ProjectServerDiscovery.links(in: "Local: http://localhost:3000/writing?token=secret", project: "p", conversation: "c", title: "Website")
        let rows = ProjectServerDiscovery.match([process(10, "/unknown")], roots: roots, links: links)
        #expect(rows.count == 1 && rows.first?.confirmed == false)
        #expect(links.first?.label.contains("secret") == false)
        #expect(links.first?.url.query == "token=secret")
        #expect(ProjectServerDiscovery.match([process(10, "/work/app/inner")], roots: roots, links: links).first?.links.isEmpty == true)
    }
    @Test func listenersDeduplicateAndGroupWorkers() {
        let parsed = ProjectServerDiscovery.parseListeners("p12\ncnode\nf1\nn*:3000\nf2\nn*:3000\nf3\nn[::1]:4000\n")
        #expect(parsed[12]?.1 == ["*:3000", "[::1]:4000"])
        let rows = ProjectServerDiscovery.match([process(10, "/work/app"), process(11, "/work/app", parent: 10)], roots: roots, links: [])
        #expect(rows.count == 1)
    }
    @Test func processIdentityChangesOnRestartAndEmptyScanRemovesRows() {
        var original = process(10, "/work/app"), restarted = original
        restarted.started += 1
        #expect(original.id != restarted.id)
        original.endpoints = []
        #expect(ProjectServerDiscovery.match([original], roots: roots, links: []).isEmpty)
    }
    @Test func URLExtractionDoesNotGuessProtocols() {
        let links = ProjectServerDiscovery.links(in: "npm run dev localhost:3000 https://localhost:444/a http://127.0.0.1:123/b http://[::1]:8080/x https://example.com", project: "p", conversation: "c", title: "t")
        #expect(links.count == 3)
        #expect(links.map(\.port) == [444, 123, 8080])
    }
    @Test func actualLocalListenerLifecycle() async throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_SERVER_FIXTURE"] == "1" else { return }
        let inventory = try await ProjectServerDiscovery.scan()
        let port = Int(ProcessInfo.processInfo.environment["DIORAMA_SERVER_PORT"] ?? "") ?? 0
        #expect(inventory.processes.contains { $0.endpoints.contains { ProjectServerDiscovery.port($0) == port } })
        print("Local server scan duration: \(inventory.duration)s")
    }
}
