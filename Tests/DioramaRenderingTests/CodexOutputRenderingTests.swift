import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct CodexOutputRenderingTests {
    @Test func richCardsRenderAtNarrowAndWideSizes() throws {
        let items: [[String: Any]] = [
            ["type": "fileChange", "id": "file", "status": "completed", "changes": [["path": "/tmp/example/counter.html", "kind": ["type": "add"], "diff": "+<html>Counter</html>"]]],
            ["type": "dynamicToolCall", "id": "dynamic", "tool": "Design preview", "status": "completed", "contentItems": [["type": "inputText", "text": "Created the preview."]]],
            ["type": "mcpToolCall", "id": "resource", "server": "design", "tool": "export", "status": "completed", "result": ["content": [["type": "resource_link", "uri": "https://example.com/design", "name": "Design document"]]]]
        ]
        let tools = items.compactMap { ToolResult(item: CodexOutputEvidence.wire($0)) }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/codex-outputs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for width in [420, 900] {
            let view = VStack(alignment: .leading, spacing: 16) {
                Text("Codex outputs").font(.title)
                Text("Fixture · passive conversation viewer").foregroundStyle(.secondary)
                ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in RichToolResultView(result: tool) }
                Spacer()
            }.padding(24).frame(width: CGFloat(width), height: 900).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let bitmap = try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("cards-\(width).png"))
        }
    }
}
