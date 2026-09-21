import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct PermissionReviewTests {
    @Test func cardFitsNarrowWindowWithoutClippingDecisions() throws {
        let request = ExecutionRequest(wireID: .string("example"), method: "item/commandExecution/requestApproval", params: .object(["toolName": .string("Read"), "toolInput": .object(["file_path": .string("/Users/example/Projects/Diorama/Package.swift")]), "availableDecisions": .array([.string("accept"), .string("decline")])]))
        for width in [460.0, 800.0] {
            let view = PermissionReviewCard(request: request, connected: true, respond: { _ in }).padding(16).frame(width: width).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame.size = host.fittingSize; host.layoutSubtreeIfNeeded()
            #expect(host.bounds.height < 360)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-permission-\(Int(width)).png"))
        }
    }
}
