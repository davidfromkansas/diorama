import Foundation
import Testing
@testable import DioramaCore

@MainActor struct ComposerQueueLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_COMPOSER_PROBE"] == "1"))
    func queuedMessageCanSteer() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diorama-composer-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let transport = CodexExecutionTransport()
        let c = ExecutionController(transport: transport)
        await c.connect()
        let id = try await c.prepare(folder: folder.path, title: "Diorama composer queue verification", model: "")
        do {
            try await c.send(id: id, prompt: "Do not use tools. Write 100 short numbered sentences about clouds.")
            try await c.enqueue(id: id, prompt: "Stop listing sentences and reply COMPOSER-STEER-OK only. Do not use tools.")
            let row = try #require(c.tasks[id]?.workflow.queue.first)
            try await c.steerQueued(id: id, submissionID: try #require(row["id"].string))
            #expect(c.tasks[id]?.workflow.queue.isEmpty == true)
            #expect(c.tasks[id]?.workflow.queueUncertain == false)
            print("COMPOSER_PROBE: queue -> steer acknowledged, queued copy removed; thread \(id)")
            if c.tasks[id]?.phase.active == true { try await c.interrupt(id: id) }
            let end = Date().addingTimeInterval(20)
            while c.tasks[id]?.phase.active == true && Date() < end { try await Task.sleep(for: .milliseconds(100)) }
            #expect(c.tasks[id]?.phase.active == false)
            await transport.shutdown()
        } catch {
            if c.tasks[id]?.phase.active == true { try? await c.interrupt(id: id) }
            await transport.shutdown()
            throw error
        }
    }
}
