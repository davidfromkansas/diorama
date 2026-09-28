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
    @Test func blenderAssetsLoadAndSceneHitTargetsStaySeparate() throws {
        _ = NSApplication.shared
        for name in ["ChibiLibrary", "ClosedBook", "OpenBook"] {
            let root = try #require(WorkspaceLibraryArtwork.asset(name))
            #expect(!root.childNodes.isEmpty)
            #expect(root.boundingBox.max.y > root.boundingBox.min.y)
        }
        let view = WorkspaceSceneNSView(); view.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        view.apply(agents: [.ready], selectedID: nil, reduceMotion: true, active: true)
        let root = try #require(view.scene?.rootNode.childNode(withName: "library", recursively: false))
        #expect(root.boundingBox.max.y < 5)
        #expect(root.boundingBox.max.x - root.boundingBox.min.x > 5)
        view.updateLibrary(item(0), open: true, reduceMotion: true, active: true)
        #expect(root.childNode(withName: "selectedLibraryBook", recursively: false) != nil)
        #expect(!view.rendersContinuously)
        // Commit model transforms before SceneKit hit testing a newly constructed view.
        _ = view.snapshot()
        let points = stride(from: 0, to: 1100, by: 10).flatMap { x in
            stride(from: 0, to: 700, by: 10).map { y in NSPoint(x: x, y: y) }
        }
        let hit = try #require(points.first { view.target(at: $0) == .library })
        #expect(view.agentID(at: hit) == nil)
        view.updateLibrary(item(1), open: true, reduceMotion: false, active: true)
        view.updateLibrary(item(2), open: true, reduceMotion: true, active: false)
        view.stopRendering(); #expect(!view.rendersContinuously)
        #expect(root.childNodes.filter { $0.name == "selectedLibraryBook" }.count == 1)
        let book = try #require(root.childNode(withName: "selectedLibraryBook", recursively: false))
        var coloredMeshes = 0
        book.enumerateChildNodes { node, _ in
            if let color = node.geometry?.firstMaterial?.diffuse.contents as? NSColor,
               color == WorkspaceLibraryArtwork.colors[item(2).coverIndex] { coloredMeshes += 1 }
        }
        #expect(coloredMeshes >= 3)
        try save(view.snapshot(), "workspace-library.png")
        let agents = [WorkspaceAgent.ready] + (0..<9).map { index in
            var agent = WorkspaceAgent.ready; agent = WorkspaceAgent(id: "child-\(index)", name: "Agent \(index + 1)", provider: "Codex", task: "Working", action: "Reading", status: .working, reportedStatus: "working", freshness: .live)
            return agent
        }
        view.apply(agents: agents, selectedID: nil, reduceMotion: true, active: false)
        view.resetCamera()
        try save(view.snapshot(), "workspace-many-agents.png")
        let closeup = SCNView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))
        closeup.scene = WorkspaceLibraryArtwork.previewScene(); closeup.antialiasingMode = .multisampling4X
        try save(closeup.snapshot(), "library-alcove.png")
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
