import Foundation
import Testing
@testable import DioramaCore

struct ConversationCanvasTests {
    func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-canvas-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func stableLocationIsolatesProvidersAndConversationsAndPreservesEdits() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let canvas = ConversationCanvas()
        let a = try canvas.prepare(folder: root.path, provider: .codex, sessionID: "../../one", title: "<script>unsafe</script>")
        let b = try canvas.location(folder: root.path, provider: .codex, sessionID: "two")
        let c = try canvas.location(folder: root.path, provider: .claude, sessionID: "../../one")
        #expect(a != b && a != c)
        #expect(a.path.hasPrefix(root.path + "/.diorama/canvases/"))
        #expect(try canvas.read(at: a).html.contains("&lt;script&gt;unsafe&lt;/script&gt;"))
        try Data("<html><body>Agent revision</body></html>".utf8).write(to: a, options: .atomic)
        _ = try canvas.prepare(folder: root.path, provider: .codex, sessionID: "../../one", title: "New title")
        #expect(try canvas.read(at: a).html.contains("Agent revision"))
    }
    @Test func incompleteOversizedAndEscapingFilesAreRejected() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let canvas = ConversationCanvas()
        let url = try canvas.prepare(folder: root.path, provider: .codex, sessionID: "one", title: "Test")
        try Data("<html>partial".utf8).write(to: url)
        #expect(throws: (any Error).self) { try canvas.read(at: url) }
        try Data(repeating: 65, count: ConversationCanvas.maximumBytes + 1).write(to: url)
        #expect(throws: (any Error).self) { try canvas.read(at: url) }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: URL(fileURLWithPath: "/tmp/outside-canvas.html"))
        #expect(throws: (any Error).self) { try canvas.location(folder: root.path, provider: .codex, sessionID: "one") }
    }
    @Test func canvasInstructionsAreSeparatedFromTheUserMessage() {
        let instructions = ConversationCanvas.instructions(for: URL(fileURLWithPath: "/tmp/my folder/a.html"))
        let parts = MessageContent.split("Do the task.\n" + instructions, provider: .codex)
        #expect(parts.count == 2)
        #expect(parts[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == "Do the task.")
        #expect(parts[1].context)
        #expect(instructions.contains("after each meaningful batch"))
        #expect(instructions.contains("http-equiv=\"refresh\""))
    }
}
