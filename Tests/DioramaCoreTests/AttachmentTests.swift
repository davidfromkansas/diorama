import Foundation
import Testing
@testable import DioramaCore

struct AttachmentTests {
    private func fixture(_ name: String, data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    @Test func imageOnlyUsesOfficialLocalImage() throws {
        let data = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        let url = try fixture("pixel.png", data: data)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let attachment = try ConversationAttachment(url: url)
        let input = try ConversationAttachment.input(prompt: "", attachments: [attachment])
        #expect(input.count == 1)
        #expect(input[0]["type"].string == "localImage")
        #expect(input[0]["path"].string == attachment.url.path)
        let mixed = try ConversationAttachment.input(prompt: "Describe this", attachments: [attachment])
        #expect(mixed.count == 2)
        #expect(mixed[0]["text"].string == "Describe this")
    }
    @Test func filesAreQuotedReferencesAndRevalidated() throws {
        let url = try fixture("notes \"quoted\".txt", data: Data("private file contents".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let attachment = try ConversationAttachment(url: url)
        let input = try ConversationAttachment.input(prompt: "", attachments: [attachment])
        #expect(input[0]["type"].string == "text")
        #expect(input[0]["text"].string?.contains("private file contents") == false)
        #expect(input[0]["text"].string?.contains("\\\"quoted\\\"") == true)
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try ConversationAttachment.input(prompt: "retry", attachments: [attachment]) }
    }
    @Test func rejectsInvalidAttachmentsAndEmptyInput() throws {
        #expect(throws: (any Error).self) { try ConversationAttachment(url: URL(string: "https://example.com/a.png")!) }
        #expect(throws: (any Error).self) { try ConversationAttachment(url: FileManager.default.temporaryDirectory) }
        #expect(throws: (any Error).self) { try ConversationAttachment.input(prompt: "  ", attachments: []) }
        let url = try fixture("broken.png", data: Data("not an image".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: (any Error).self) { try ConversationAttachment(url: url) }
    }
}
