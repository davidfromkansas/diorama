import SwiftUI

struct ConversationViewportAnchor: Codable, Equatable { var id: String; var offset: Double }

/// Native row coordinates preserve the same text under the reader when rows prepend.
@MainActor final class ConversationHistoryViewport {
    private final class WeakRow { weak var view: NSView?; init(_ view: NSView) { self.view = view } }
    private var rows: [String: WeakRow] = [:]
    private var anchor: (id: String, offset: CGFloat)?
    private var generation = 0
    var anchorID: String? { anchor?.id }
    var checkpoint: ConversationViewportAnchor? {
        get { anchor.map { ConversationViewportAnchor(id: $0.id, offset: $0.offset) } }
        set { anchor = newValue.map { ($0.id, $0.offset) } }
    }
    func register(_ view: NSView, id: String) { rows[id] = WeakRow(view) }
    @discardableResult func capture() -> String? {
        rows = rows.filter { $0.value.view?.window != nil }
        let candidates = rows.compactMap { id, weakRow -> (String, CGFloat)? in
            guard let row = weakRow.view, let scroll = row.enclosingScrollView, let document = scroll.documentView else { return nil }
            let rect = row.convert(row.bounds, to: document)
            guard rect.maxY > scroll.contentView.bounds.minY, rect.minY < scroll.contentView.bounds.maxY else { return nil }
            return (id, rect.minY - scroll.contentView.bounds.minY)
        }
        if let candidate = candidates.min(by: { $0.1 < $1.1 }) { anchor = (candidate.0, candidate.1) }
        return anchor?.id
    }
    func cancel() { generation += 1; anchor = nil }
    func restore() {
        let token = generation
        for delay in [0.0, 0.06, 0.14] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == token, let anchor = self.anchor,
                      let row = self.rows[anchor.id]?.view, let scroll = row.enclosingScrollView,
                      let document = scroll.documentView else { return }
                document.layoutSubtreeIfNeeded()
                let y = row.convert(row.bounds, to: document).minY - anchor.offset
                let limit = max(0, document.bounds.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: max(0, min(y, limit))))
                scroll.reflectScrolledClipView(scroll.contentView)
                if delay == 0.14 { self.anchor = nil }
            }
        }
    }
}

struct ConversationHistoryRowAnchor: NSViewRepresentable {
    let id: String
    let viewport: ConversationHistoryViewport
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); viewport.register(view, id: id); return view
    }
    func updateNSView(_ view: NSView, context: Context) { viewport.register(view, id: id) }
}
