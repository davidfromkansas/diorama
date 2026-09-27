import Foundation
import CryptoKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

/// Opt-in observer only. Start prompts in the source client; this probe never executes them.
@MainActor struct LiveExternalViewerProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_APPROVAL_PROBE_SESSION"] != nil))
    func observesRealApprovalWithoutResolvingIt() async throws {
        let env = ProcessInfo.processInfo.environment
        let id = try #require(env["DIORAMA_APPROVAL_PROBE_SESSION"])
        let sessions = await SessionLibrary().scan().sessions
        let session = try #require(sessions.first { $0.sessionID == id })
        let observer = ExternalSessionObserver()
        let snapshot = await observer.read(session)
        #expect(snapshot.error == nil)
        if env["DIORAMA_APPROVAL_PROBE_RESOLVED"] == "1" {
            #expect(snapshot.activity.state == .finished)
            #expect(snapshot.activity.attention.isEmpty)
            #expect(snapshot.transcript.entries.contains { $0.text.contains("VIEWER_V3_APPROVAL_DONE") && $0.kind == "Assistant" })
        } else {
            #expect(snapshot.activity.state == .approval)
            #expect(!snapshot.activity.attention.isEmpty)
            let transcriptOnly = await observer.read(session, hookDirectory: nil)
            #expect(transcriptOnly.activity.state == .working, "This client exposes pending Bash permission through hooks, not its transcript")
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_CANCELLATION_PROBE_SESSION"] != nil))
    func observesRealCancellationOrRecoveryWithoutHooks() async throws {
        let env = ProcessInfo.processInfo.environment
        let id = try #require(env["DIORAMA_CANCELLATION_PROBE_SESSION"])
        let sessions = await SessionLibrary().scan().sessions
        let session = try #require(sessions.first { $0.sessionID == id })
        let observer = ExternalSessionObserver()
        let snapshot = await observer.read(session, hookDirectory: nil)
        #expect(snapshot.error == nil)
        #expect(snapshot.activity.events.contains { $0.kind == "interrupted" })
        if env["DIORAMA_CANCELLATION_PROBE_RECOVERED"] == "1" {
            #expect(snapshot.activity.state == .finished)
            #expect(snapshot.transcript.entries.contains { $0.text.contains("VIEWER_V3_RECOVERED") && $0.kind == "Assistant" })
        } else {
            #expect(snapshot.activity.state == .interrupted)
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_WORKTREE_PROBE_SESSION"] != nil))
    func observesDesignatedWorktreeWithoutHooks() async throws {
        let env = ProcessInfo.processInfo.environment
        let id = try #require(env["DIORAMA_WORKTREE_PROBE_SESSION"])
        let project = try await ProjectGit.discover(try #require(env["DIORAMA_WORKTREE_PROBE_PROJECT"]))
        let sessions = await SessionLibrary().scan().sessions
        let session = try #require(sessions.first { $0.sessionID == id })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(execution: ExecutionController(transport: ProbeReadOnlyTransport()),
            projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")),
            conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")),
            observationHookDirectory: nil)
        model.sessions = [session]; model.selectedID = session.id
        model.projects.projects = [project]
        await model.projects.associate([session])
        #expect(model.projects.sessions(project, library: model).contains { $0.id == session.id })
        let changed = await SessionLibrary.changedSessions(paths: [try #require(session.url).path])
        #expect(changed.contains { $0.id == session.id })
        await model.readSelected()
        #expect(model.transcript.entries.contains { $0.text.contains("VIEWER_V2_WORKTREE_DONE") })
        #expect(model.observations[session.id]?.activity.events.contains { $0.kind == "toolFailed" } == true)
        #expect(model.observations[session.id]?.activity.state == .finished)
        #expect(model.execution.tasks.isEmpty)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_VIEWER_PROBE_SESSION"] != nil))
    func measuresDesignatedExternalSession() async throws {
        let env = ProcessInfo.processInfo.environment
        let id = try #require(env["DIORAMA_VIEWER_PROBE_SESSION"])
        let sessions = await SessionLibrary().scan().sessions
        let session = try #require(sessions.first { $0.sessionID == id && $0.classification != .subagent })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(execution: ExecutionController(transport: ProbeReadOnlyTransport()),
            projects: ProjectModel(storageURL: root.appendingPathComponent("projects.json")),
            conversations: DioramaConversationModel(file: root.appendingPathComponent("conversations.json")),
            observationHookDirectory: env["DIORAMA_VIEWER_PROBE_IGNORE_HOOKS"] == "1" ? nil : HookStore.directory)
        model.sessions = sessions; model.selectedID = session.id
        await model.readSelected()
        var seen = Set(model.transcript.entries.map(probeIdentity))
        var evidenceToModel: [Double] = [], sourceToModel: [Double] = []
        var notifications = 0
        var samples: [[String: Any]] = []
        let evidence = ReadableEvidenceSampler(session: session)
        await evidence.sample()
        let sampling = Task {
            while !Task.isCancelled {
                await evidence.sample()
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
        defer { sampling.cancel() }
        var reading = false
        var pendingReceipt: Date?
        let watcher = DirectoryWatcher(paths: [try #require(session.url).deletingLastPathComponent().path]) {
            notifications += 1
            pendingReceipt = pendingReceipt ?? Date()
            guard !reading else { return }
            reading = true
            Task {
                defer { reading = false }
                while let receipt = pendingReceipt {
                    pendingReceipt = nil
                    await model.readSelected()
                    let now = Date()
                    let new = model.transcript.entries.filter { seen.insert(probeIdentity($0)).inserted }
                    for entry in new {
                        if let source = ActivityParser.date(entry.timestamp) { sourceToModel.append(now.timeIntervalSince(source) * 1000) }
                        if let modified = model.observations[session.id]?.sourceModifiedAt { evidenceToModel.append(now.timeIntervalSince(modified) * 1000) }
                        guard samples.count < 2000 else { continue }
                        var sample: [String: Any] = ["event_id": probeIdentity(entry), "kind": entry.kind,
                            "observer_received_at": receipt.timeIntervalSince1970,
                            "model_updated_at": now.timeIntervalSince1970,
                            "visible_at": NSNull(), "source_visible_at": NSNull()]
                        if let source = ActivityParser.date(entry.timestamp) { sample["source_timestamp"] = source.timeIntervalSince1970 }
                        // Only test markers are retained, never conversation text.
                        if let range = entry.text.range(of: #"VIEWER_V2_[A-Z0-9_]+"#, options: .regularExpression) {
                            sample["test_marker"] = String(entry.text[range])
                        }
                        samples.append(sample)
                    }
                }
            }
        }
        if let path = env["DIORAMA_VIEWER_PROBE_OUTPUT"] {
            try Data("ready".utf8).write(to: URL(fileURLWithPath: path + ".ready"), options: .atomic)
        }
        try FileHandle.standardOutput.write(contentsOf: Data("VIEWER_LIVE_PROBE_READY provider=\(session.provider.rawValue) origin=\(session.origin.rawValue)\n".utf8))
        let duration = min(900, max(5, Double(env["DIORAMA_VIEWER_PROBE_SECONDS"] ?? "60") ?? 60))
        try await Task.sleep(for: .seconds(duration))
        withExtendedLifetime(watcher) {}
        sampling.cancel()
        await sampling.value
        let intervals = await evidence.intervals
        for index in samples.indices {
            if let id = samples[index]["event_id"] as? String, let interval = intervals[id] {
                samples[index]["first_readable_after"] = interval.lower.timeIntervalSince1970
                samples[index]["first_readable_by"] = interval.upper.timeIntervalSince1970
            }
        }
        func summary(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return [:] }
            return ["count": Double(sorted.count), "p95_ms": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], "maximum_ms": sorted.last!]
        }
        let report: [String: Any] = ["provider": session.provider.rawValue, "origin": session.origin.rawValue,
            "notifications": notifications, "duration_seconds": duration,
            "evidence_to_model": summary(evidenceToModel), "source_timestamp_to_model": summary(sourceToModel),
            "pixel_latency_measured": false, "source_client_visible_time_measured": false,
            "execution_requests": 0, "samples": samples, "observer_reads_hooks": env["DIORAMA_VIEWER_PROBE_IGNORE_HOOKS"] != "1",
            "readability_measurement": "Independent 20ms sampling; intervals bound complete-entry readability. File mtime aggregate is a proxy, not first-evidence timing.",
            "screen_measurement": "visible_at/source_visible_at require separately correlated screenshot or recording evidence; null is unmeasured."]
        if let path = env["DIORAMA_VIEWER_PROBE_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
        print("VIEWER_LIVE_PROBE_RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: report, options: .sortedKeys), as: UTF8.self))
        #expect(!evidenceToModel.isEmpty, "Send a bounded prompt in the designated source client while the probe is running")
    }
}
private actor ProbeReadOnlyTransport: ExecutionTransport {
    nonisolated let events = AsyncStream<WireValue> { $0.finish() }
    func connect() { Issue.record("Observation connected execution") }
    func request(_ method: String, _ params: WireValue) -> WireValue { Issue.record("Unexpected execution request: \(method)"); return .null }
    func respond(id: WireValue, result: WireValue) { Issue.record("Unexpected approval response") }
    func reject(id: WireValue, message: String) { Issue.record("Unexpected approval rejection") }
    func shutdown() {}
}

// Test-only bounded sampler, independent of the notification consumer. Hashes permit
// joining records without writing private message bodies to the timing report.
private func probeIdentity(_ entry: Entry) -> String {
    // Reader scopes differ (path vs. session/inode), so join on provider identity
    // and reported content, not presentation IDs. Include result-only updates.
    let outputs = entry.claude?.outputs.map { ($0.location ?? "") + ($0.encoded ?? "") + $0.kind }.joined(separator: "\n") ?? ""
    let fields = [entry.providerItemID ?? entry.id, entry.kind, entry.timestamp ?? "", entry.text,
                  entry.claude?.callID ?? "", entry.claude?.status ?? "", outputs, entry.tool?.rawPreview ?? ""]
    return SHA256.hash(data: Data(fields.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()

}
private actor ReadableEvidenceSampler {
    struct Interval: Sendable { let lower: Date; let upper: Date }
    let session: Session
    var intervals: [String: Interval] = [:]
    private var previous = Date()
    private var signature: String?
    init(session: Session) { self.session = session }
    func sample() {
        let checkedAt = Date()
        guard let url = session.url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return }
        let current = "\(attributes[.size] ?? 0):\(attributes[.modificationDate] ?? 0):\(attributes[.systemFileNumber] ?? 0)"
        if signature == current { previous = checkedAt; return }
        let transcript = SessionLibrary.readTranscript(url: url, provider: session.provider, limit: 300)
        guard transcript.error == nil else { return }
        let readBy = Date()
        for entry in transcript.entries {
            let id = probeIdentity(entry)
            if intervals[id] == nil && intervals.count < 4000 { intervals[id] = Interval(lower: previous, upper: readBy) }
        }
        signature = current; previous = checkedAt
    }
}
