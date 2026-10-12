import SwiftUI

/// Exact connector IDs only. Unknown names never borrow another company's branding.
/// The GitHub mark as a small template image (it takes the text colour), sized like an SF Symbol
/// beside a label, so it sits in buttons and menus the way the other icons do.
enum GitHubSymbol {
    static let image: NSImage? = {
        guard let url = Bundle.dioramaResources?.url(forResource: "GitHub", withExtension: "svg", subdirectory: "ConnectorBrand"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 15, height: 15)
        image.isTemplate = true
        return image
    }()
    /// The mark, or a link symbol if the resource is missing.
    static var icon: Image { image.map { Image(nsImage: $0) } ?? Image(systemName: "link") }
}

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
