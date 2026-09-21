import SwiftUI

/// Rounded outgoing bubble with a curved tail at the lower trailing edge.
struct UserMessageBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 7
        let body = CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - tail), height: rect.height)
        var path = Path(roundedRect: body, cornerRadius: min(20, rect.height / 2))
        let x = rect.maxX, y = rect.maxY
        path.move(to: CGPoint(x: x - 10, y: y - 23))
        path.addCurve(to: CGPoint(x: x, y: y - 1), control1: CGPoint(x: x - 12, y: y - 10), control2: CGPoint(x: x - 9, y: y - 4))
        path.addCurve(to: CGPoint(x: x - 27, y: y - 8), control1: CGPoint(x: x - 10, y: y + 1), control2: CGPoint(x: x - 20, y: y - 2))
        path.closeSubpath()
        return path
    }
}
