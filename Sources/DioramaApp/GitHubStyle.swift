import SwiftUI
import DioramaCore

/// The GitHub screens' colours: GitHub's green for connected, amber for trouble, blue for actions.
enum GitHubStyle {
    static let green = Color(red: 0.25, green: 0.73, blue: 0.31)
    static let amber = Color(red: 0.94, green: 0.62, blue: 0.2)
    /// Amber text: readable on light and dark backgrounds.
    static let amberText = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.95, green: 0.71, blue: 0.3, alpha: 1) : NSColor(red: 0.62, green: 0.36, blue: 0.0, alpha: 1) })
    static let blue = Color(red: 0.18, green: 0.44, blue: 0.93)
    /// Blue text: readable on light and dark backgrounds.
    static let blueText = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.48, green: 0.66, blue: 1.0, alpha: 1) : NSColor(red: 0.13, green: 0.36, blue: 0.82, alpha: 1) })
}

/// A small pill on the GitHub button: the action it offers.
struct GitHubPill: View {
    enum Style { case filled, warning }
    let text: String
    let style: Style
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(style == .filled ? Color.white : GitHubStyle.amberText)
            .background(Capsule().fill(style == .filled ? GitHubStyle.blue : .clear))
            .overlay(Capsule().strokeBorder(style == .warning ? GitHubStyle.amber.opacity(0.7) : .clear, lineWidth: 1))
            .fixedSize()
    }
}
