import AppKit
import Foundation
import Testing
@testable import DioramaCore

private actor ImageProbeTransport: ExecutionTransport {
    nonisolated let events: AsyncStream<WireValue>
    let base: any ExecutionTransport
    var calls: [String] = []
    init(_ base: any ExecutionTransport) { self.base = base; events = base.events }
    func connect() async throws { try await base.connect() }
    func request(_ method: String, _ params: WireValue) async throws -> WireValue {
        calls.append(method)
        return try await base.request(method, params)
    }
    func respond(id: WireValue, result: WireValue) async throws { try await base.respond(id: id, result: result) }
    func reject(id: WireValue, message: String) async throws { try await base.reject(id: id, message: message) }
    func shutdown() async { await base.shutdown() }
    func resetCalls() { calls = [] }
}

@MainActor struct ImageSendLiveProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIORAMA_IMAGE_SEND_PROBE"] == "1"), arguments: [false, true])
    func describesImageUsingCurrentPermissions(claude: Bool) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".local/verification/image-send/\(claude ? "claude" : "codex")-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try #require(bitmap.bitmapData)
        for y in 0..<64 { for x in 0..<64 {
            let offset = y * bitmap.bytesPerRow + x * 4
            pixels[offset] = 255; pixels[offset + 1] = 0; pixels[offset + 2] = 0; pixels[offset + 3] = 255
        } }
        let image = root.appendingPathComponent("fixture.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: image)
        let base: any ExecutionTransport = claude ? ClaudeExecutionTransport(folder: root.path) : CodexExecutionTransport()
        let transport = ImageProbeTransport(base)
        let controller = ExecutionController(transport: transport, journal: root.appendingPathComponent("owned.json"))
        do {
            await controller.connect()
            try #require(controller.connected)
            let id = try await controller.prepare(folder: root.path, title: "Image send verification", model: claude ? "claude/haiku" : "", permission: .user)
            controller.tasks[id]?.permissionPreference = .autoReview // Reproduce the stale bookmark.
            await transport.resetCalls()
            try await controller.send(id: id, prompt: "Describe the dominant color in the attached image in one word. Do not use tools or change files.", attachments: [try ConversationAttachment(url: image)])
            let deadline = Date().addingTimeInterval(90)
            while controller.tasks[id]?.phase != .finished && controller.tasks[id]?.phase != .failed {
                guard Date() < deadline else { throw AppServerFailure("Image probe timed out") }
                try await Task.sleep(for: .milliseconds(100))
            }
            let task = try #require(controller.tasks[id])
            let answer = task.transcript.entries.filter { $0.kind == "Assistant" }.map(\.text).joined(separator: "\n")
            try #require(task.phase == .finished, Comment(rawValue: task.error ?? "Turn did not finish"))
            #expect(answer.lowercased().contains("red"))
            let calls = await transport.calls
            #expect(calls.filter { $0 == "turn/start" }.count == 1)
            #expect(!calls.contains("diorama/permissions/set") && !calls.contains("thread/resume"))
            let evidence: [String: Any] = ["session": id, "provider": claude ? "Claude" : "Codex", "answer": answer, "calls": calls, "policy": task.approvalPolicy.pretty]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("result.json"))
            print("IMAGE_SEND_EVIDENCE \(root.path)")
            await transport.shutdown()
        } catch {
            // This transport owns only the isolated probe session.
            await transport.shutdown()
            throw error
        }
    }
}
