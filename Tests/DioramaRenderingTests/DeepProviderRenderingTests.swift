import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct DeepProviderRenderingTests {
    @Test func independentProviderCardsRender() throws {
        let search = try #require(ToolResult(item: CodexOutputEvidence.wire(["type": "Extension", "kind": "web.search", "id": "search", "query": "capybara anatomy reference", "results": [["url": "https://example.com/reference", "title": "Capybara anatomy", "snippet": "A recorded reference for body proportions and silhouette."]]])))
        let usage = CodexPresentation(category: "usage", title: "Token usage", evidence: CodexOutputEvidence.wire(["info": ["last_token_usage": ["input_tokens": 16000, "cached_input_tokens": 8000, "output_tokens": 2400]]]))
        let claude = ClaudePresentation(title: "Claude turn usage", status: "Reported", category: "usage", evidence: CodexOutputEvidence.wire(["usage": ["input_tokens": 1200, "output_tokens": 600, "cache_read_input_tokens": 4000, "cache_creation_input_tokens": 1000], "total_cost_usd": 0.02]))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/deep-provider-outputs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for width in [420, 900] {
            let view = VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Codex · Claude").font(.title); Spacer(); ConnectorMark(server: "github") }
                RichToolResultView(result: search)
                CodexEntryView(entry: Entry(id: "usage", kind: "Event", text: "", timestamp: nil), presentation: usage)
                ClaudeEntryView(entry: Entry(id: "claude", kind: "Event", text: "", timestamp: nil), presentation: claude)
            }.padding(24).frame(width: CGFloat(width)).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let bitmap = try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("provider-cards-\(width).png"))
        }
    }
}
