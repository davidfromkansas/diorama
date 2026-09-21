import Foundation
import Testing
@testable import DioramaCore

struct ExecutionPresentationTests {
    func field(_ schema: String) throws -> ElicitationField {
        ElicitationField(id: "value", schema: try JSONDecoder().decode(WireValue.self, from: Data(schema.utf8)), required: true)
    }
    @Test func scalarFormsValidateTypesAndLimits() throws {
        let integer = try field(#"{"type":"integer","minimum":1,"maximum":4}"#)
        try integer.validate(.number(2))
        #expect(throws: (any Error).self) { try integer.validate(.number(2.5)) }
        #expect(throws: (any Error).self) { try integer.validate(.number(5)) }
        #expect(throws: (any Error).self) { try integer.validate(.string("2")) }
        let boolean = try field(#"{"type":"boolean"}"#)
        try boolean.validate(.bool(false))
        #expect(throws: (any Error).self) { try boolean.validate(.string("false")) }
        let string = try field(#"{"type":"string","minLength":2,"maxLength":4}"#)
        try string.validate(.string("hi"))
        #expect(throws: (any Error).self) { try string.validate(.string("longer")) }
    }
    @Test func titledAndLegacyEnumsKeepWireValues() throws {
        let legacy = try field(#"{"type":"string","enum":["a","b"],"enumNames":["Alpha","Beta"]}"#)
        #expect(legacy.choices.first?.title == "Alpha")
        try legacy.validate(.string("a"))
        #expect(throws: (any Error).self) { try legacy.validate(.string("Alpha")) }
        let titled = try field(#"{"type":"string","oneOf":[{"const":"a","title":"Alpha"}]}"#)
        try titled.validate(.string("a"))
        let multiple = try field(#"{"type":"array","minItems":1,"maxItems":2,"items":{"anyOf":[{"const":"a","title":"Alpha"},{"const":"b","title":"Beta"}]}}"#)
        try multiple.validate(.array([.string("a"), .string("b")]))
        #expect(throws: (any Error).self) { try multiple.validate(.array([.string("a"), .string("a")])) }
        #expect(throws: (any Error).self) { try multiple.validate(.array([])) }
    }
    @Test func invalidFormatsAndUnknownConstraintsFailClosed() throws {
        let date = try field(#"{"type":"string","format":"date"}"#)
        try date.validate(.string("2026-09-20"))
        #expect(throws: (any Error).self) { try date.validate(.string("2026-02-30")) }
        let email = try field(#"{"type":"string","format":"email"}"#)
        try email.validate(.string("test@example.com"))
        #expect(throws: (any Error).self) { try email.validate(.string("not an email")) }
        let unsupported = try field(#"{"type":"string","pattern":"^a$"}"#)
        #expect(!unsupported.supported)
        #expect(throws: (any Error).self) { try unsupported.validate(.string("a")) }
    }
    @Test func unsupportedFormCanStillBeDeclinedOrCancelled() throws {
        let request = ExecutionRequest(wireID: .string("form"), method: "mcpServer/elicitation/request", params: .object(["mode": .string("openai/form"), "requestedSchema": .object(["type": .string("object"), "oneOf": .array([])])]))
        #expect(!request.supportsElicitationForm)
        #expect(throws: (any Error).self) { try request.validateElicitation(.object(["action": .string("accept"), "content": .object([:])])) }
        try request.validateElicitation(.object(["action": .string("decline"), "content": .null]))
        try request.validateElicitation(.object(["action": .string("cancel")]))
    }
    @Test func diffIncludesDeletionBinaryAndMultipleFiles() {
        let diff = "diff --git a/gone b/gone\n--- a/gone\n+++ /dev/null\n-old\ndiff --git a/picture b/picture\nBinary files differ"
        let files = ExecutionDiffFile.parse(diff)
        #expect(files.count == 2)
        #expect(files.first?.path == "gone")
        #expect(files.first?.deletions == 1)
        #expect(files.last?.diff.contains("Binary files differ") == true)
    }
}
