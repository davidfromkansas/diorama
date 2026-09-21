import SwiftUI
import Testing
@testable import DioramaApp

@MainActor
struct MarkdownRenderingTests {
    @Test func titleRemovesMarkdownSyntax() {
        #expect(markdownTitle("Test task<diorama_html_view>Injected canvas instructions") == "Test task")
        #expect(markdownTitle("**Build** a [viewer](https://example.com) with `Swift`") == "Build a viewer with Swift")
    }

    @Test func structuredPayloadsStayLiteral() {
        #expect(isStructuredRecord("{\"command\":\"echo **hello**\"}"))
        #expect(isStructuredRecord("[1, 2, 3]"))
        #expect(!isStructuredRecord("[a link](https://example.com)"))
        #expect(!isStructuredRecord("- **a list item**"))
    }

    /// Produces a native rendering for visual inspection, without opening any user sessions.
    @Test func renderMarkdownFixture() throws {
        let fixture = """
        ## Transcript formatting

        **Bold**, *italic*, ~~removed~~, `inline code`, and [a link](https://example.com).

        | Layer | What it does |
        | --- | --- |
        | **3D world** | Renders avatars, rooms, and animations. |
        | Agent state | Tracks each agent’s recorded activity. |

        - A list item with **formatting**
          - A nested item
        - [x] Completed checklist item
        - [ ] Remaining checklist item

        1. First step
        2. Second step

        > Quoted text stays distinct from the response.

        ```swift
        let literal = "**keep this literal**"
        print(literal)
        ```

        <environment_context>Keep XML visible.</environment_context>

        ---

        Final paragraph.
        """
        let view = MarkdownText(text: fixture)
            .padding(24).frame(width: 720)
            .background(Color(white: 0.12)).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/diorama-markdown-preview.png"))
        #expect(image.size.height > 400)
    }
}
