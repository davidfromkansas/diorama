import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct CapabilityLibraryRenderingTests {
    private func item(_ n: Int) -> CapabilityLibraryItem {
        let names = ["Design studio", "Research", "Write Swift", "Figma", "Documents", "Animation", "Spreadsheets", "Image workshop"]
        return .init(id: "book-\(n)", name: names[n % names.count], description: "A little book of practical knowledge. Explore tools and techniques for thoughtful work.", kind: n % 4 == 0 ? .plugin : .skill, provider: .codex, source: "Workspace", availability: n % 3 == 0 ? .unverified : .available)
    }
    @Test func cacheAndLateContextResponses() async {
        let model = CapabilityLibraryModel()
        let a = CapabilityLibraryContext(provider: .codex, folder: "/a")
        let b = CapabilityLibraryContext(provider: .claude, folder: "/b")
        var continuation: CheckedContinuation<CapabilityLibrarySnapshot, Never>?
        let old = Task { await model.load(a) { context in await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        await model.load(b) { .init(context: $0) }
        continuation?.resume(returning: .init(context: a)); await old.value
        #expect(model.snapshot?.context == b)
        var called = false
        await model.load(b) { called = true; return .init(context: $0) }
        #expect(!called)
        await model.load(b, force: true) { called = true; return .init(context: $0) }
        #expect(called)
        #expect(!model.loading)
    }
    @Test func catalogueRendersAtNarrowAndWideSizes() throws {
        _ = NSApplication.shared
        let context = CapabilityLibraryContext(provider: .codex, folder: "/workspace")
        let snapshot = CapabilityLibrarySnapshot(context: context, items: (0..<300).map(item))
        let controller = ExecutionController()
        for width in [380, 440] {
            let view = CapabilityLibraryView(controller: controller, context: context, compact: width == 380, selected: .constant(nil), model: CapabilityLibraryModel(snapshot: snapshot), close: {})
            let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: width, height: 760); host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            try save(bitmap.representation(using: .png, properties: [:]), "catalogue-\(width).png")
        }
        let view = CapabilityLibraryView(controller: controller, context: context, selected: .constant(item(0)), model: CapabilityLibraryModel(snapshot: snapshot), close: {})
        let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: 440, height: 760); host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        try save(bitmap.representation(using: .png, properties: [:]), "book-detail.png")
    }
    private func save(_ image: NSImage, _ name: String) throws {
        let tiff = try #require(image.tiffRepresentation); let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try save(bitmap.representation(using: .png, properties: [:]), name)
    }
    private func save(_ data: Data?, _ name: String) throws {
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/library")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #require(data).write(to: folder.appendingPathComponent(name))
    }
}
