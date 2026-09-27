import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ClaudeOutputRenderingTests {
    @Test func cardsRenderAtNarrowAndWideSizes() async throws {
        let text = #"""
        {"uuid":"a","cwd":"/tmp/fixture","type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Artifact","input":{"action":"quickstart"}},{"type":"tool_use","id":"b","name":"Write","input":{"file_path":"counter.html"}}]}}
        {"uuid":"b","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"Build a self-contained page with readable typography."},{"type":"tool_result","tool_use_id":"b","content":"Saved counter.html"}]}}
        """#
        let transcript = ClaudeNormalizer.parse(Data((text + "\n").utf8), scope: "render")
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/claude-outputs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for width in [420, 900] {
            let content = VStack(alignment: .leading, spacing: 18) {
                Text("Claude outputs").font(.title)
                Text("Fixture · passive conversation viewer").foregroundStyle(.secondary)
                ForEach(transcript.entries) { entry in
                    if let presentation = entry.claude { ClaudeEntryView(entry: entry, presentation: presentation) }
                }
                Spacer()
            }.padding(24).frame(width: CGFloat(width), height: 600)
            let renderer = ImageRenderer(content: content.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            renderer.scale = 2
            let image = try #require(renderer.nsImage)
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("cards-\(width).png"))

        }
    }
}
