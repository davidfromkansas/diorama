import Foundation
import Testing
@testable import DioramaCore

struct DesignatedActivityProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_PROBE_TRANSCRIPT"] != nil))
    func readsDesignatedIndependentSession() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["DIORAMA_PROBE_TRANSCRIPT"])
        let url = URL(fileURLWithPath: path)
        let session = Session(id: "designated", provider: .codex, url: url, sessionID: "designated", title: "Designated probe",
                              project: "", modified: Date(), bytes: 0, archived: false, parentID: nil)
        let observer = ActivityLibrary()
        let first = try #require(await observer.scan([session], hookDirectory: nil)[session.id])
        #expect(first.error == nil); #expect(!first.events.isEmpty)
        let reconnected = try #require(await ActivityLibrary().scan([session], hookDirectory: nil)[session.id])
        #expect(first.events.map(\.id) == reconnected.events.map(\.id))
        let evidence: [String: Any] = ["tested_at": ISO8601DateFormatter().string(from: Date()), "event_count": first.events.count,
            "event_kinds": Array(Set(first.events.map(\.kind))).sorted(), "last_recorded_state": first.state.rawValue,
            "observer_reconnect_stable": first.events.map(\.id) == reconnected.events.map(\.id),
            "source_modified": false, "method": "read-only designated existing Codex transcript; no agent execution"]
        if let output = ProcessInfo.processInfo.environment["DIORAMA_PROBE_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
        }
    }
}
