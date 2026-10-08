import SwiftUI

/// Exact connector IDs only. Unknown names never borrow another company's branding.
struct ConnectorMark: View {
    let server: String?
    private var github: NSImage? {
        guard server?.lowercased() == "github", let url = Bundle.dioramaResources?.url(forResource: "GitHub", withExtension: "svg", subdirectory: "ConnectorBrand") else { return nil }
        return NSImage(contentsOf: url)
    }
    var body: some View {
        Group {
            if let github { Image(nsImage: github).resizable().scaledToFit().padding(5).background(.black, in: RoundedRectangle(cornerRadius: 6)) }
            else { Image(systemName: "puzzlepiece.extension").resizable().scaledToFit().padding(5) }
        }.frame(width: 28, height: 28).accessibilityLabel(server.map { $0 + " connector" } ?? "Connector")
    }
}
