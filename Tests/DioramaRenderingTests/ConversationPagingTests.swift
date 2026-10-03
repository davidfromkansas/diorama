import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor @Observable private final class PagingFixture { var start = 100 }

@MainActor private struct PagingFixtureView: View {
    @Bindable var fixture: PagingFixture
    let viewport: ConversationHistoryViewport
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(fixture.start..<200, id: \.self) { index in
                    Text("Message \(index)").frame(height: 40)
                        .background(ConversationHistoryRowAnchor(id: "row-\(index)", viewport: viewport))
                        .id("row-\(index)")
                }
            }
        }.onChange(of: fixture.start) {
            Task { @MainActor in
                await Task.yield()
                if let id = viewport.anchorID { proxy.scrollTo(id, anchor: .top) }
                viewport.restore()
            }
        }
        }
    }
}

@MainActor struct ConversationPagingTests {
    @Test func preparedRowsReuseUnchangedHistoryAndPreserveGrouping() {
        let cache = ConversationRowCache()
        let entries = (0..<1000).map { Entry(id: "row-\($0)", kind: "Assistant", text: "Message", timestamp: $0 == 20 ? nil : "2026-10-02T05:49:22.902Z") }
        let first = cache.prepare(entries, mode: .conversation)
        #expect(first.count == 1000)
        #expect(first.filter { $0.separator != nil }.count == 1)
        #expect(first.filter(\.tail).count == 1)
        for _ in 0..<20 { _ = cache.prepare(entries, mode: .conversation) }
        #expect(cache.revision == 1)
        var changed = entries
        changed[999].text = "Streaming update"
        #expect(cache.prepare(changed, mode: .conversation).last?.row.entries.first?.text == "Streaming update")
        #expect(cache.revision == 2)
    }
    @Test func nativePrependKeepsVisibleRowOffset() async throws {
        let fixture = PagingFixture()
        let viewport = ConversationHistoryViewport()
        let host = NSHostingView(rootView: PagingFixtureView(fixture: fixture, viewport: viewport))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        func settle() async throws {
            for _ in 0..<5 { try await Task.sleep(for: .milliseconds(60)); host.layoutSubtreeIfNeeded() }
        }
        func find(_ view: NSView) -> NSScrollView? { (view as? NSScrollView) ?? view.subviews.compactMap(find).first }
        try await settle()
        let scroll = try #require(find(host))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        let captured = viewport.capture()
        #expect(captured != nil, "Must capture a visible row")
        fixture.start = 0
        try await settle()
        #expect(abs(scroll.contentView.bounds.minY - 4120) < 3, "Document: \(scroll.documentView!.bounds), anchor: \(captured ?? "none")")
    }
}
