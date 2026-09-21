import SwiftUI
import Testing
@testable import DioramaApp
@MainActor struct PermissionsMenuTests {
    @Test func renderMenu() throws {
        let host = NSHostingView(rootView: PermissionsMenu(selected: .user, pending: false, choose: { _ in }).background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/diorama-permissions-menu.png"))
    }
}
