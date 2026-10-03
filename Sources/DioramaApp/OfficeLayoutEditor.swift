import AppKit
import SceneKit

struct OfficeEditTransform: Codable, Equatable, Sendable {
    var x: Double
    var z: Double
    /// Rotation of the placement node, added to the asset's authored orientation.
    var rotationRadians: Double
}

@MainActor final class OfficeLayoutEditor {
    struct Item {
        let id: String
        let label: String
        let node: SCNNode
        let ignored: SCNNode?
        let width: Double
        let depth: Double
        let apply: (OfficeEditTransform) -> Void
    }
    private(set) var enabled = false
    private(set) var selection: Set<String> = []
    var selected: String? { selection.sorted().first }
    private(set) var project: String?
    private(set) var drafts: [String: [String: OfficeEditTransform]] = [:]
    private(set) var items: [Item] = []
    private var floor = LeisureBounds(minX: -10, maxX: 10, minZ: -5, maxZ: 20)
    private var dragStart: SCNVector3?
    private var dragTransforms: [String: OfficeEditTransform] = [:]
    private var loaded = false
    private var outlines: [SCNNode] = []
    private let writer = DispatchQueue(label: "Diorama.office-layout-draft")
    var defaults: UserDefaults?
    var exportURL: URL?
    var changed: (() -> Void)?
    private var exportError: String?
    private static let key = "officeLayoutDraft.v1"

    func prepareReconciliation() { outlines.forEach { $0.removeFromParentNode() }; outlines = [] }

    func configure(project: String, items: [Item], floor: LeisureBounds) {
        if self.project != project { finish(); self.project = project; selection = [] }
        if !loaded {
            loaded = true
            if let data = defaults?.data(forKey: Self.key), let saved = try? JSONDecoder().decode([String: [String: OfficeEditTransform]].self, from: data) {
                drafts = saved.filter { !$0.value.values.contains { !$0.x.isFinite || !$0.z.isFinite || !$0.rotationRadians.isFinite } }
            }
        }
        if project == OfficeBakedLayout.sourceProject {
            var migrated = false
            for item in items {
                guard let saved = drafts[project]?[item.id], let baked = OfficeBakedLayout.transforms[item.id],
                      abs(saved.x-baked.x) < 0.00001, abs(saved.z-baked.z) < 0.00001,
                      abs(saved.rotationRadians-baked.rotationRadians) < 0.00001 else { continue }
                let actual = transform(item)
                if abs(actual.x-baked.x) < 0.00001 && abs(actual.z-baked.z) < 0.00001 && abs(actual.rotationRadians-baked.rotationRadians) < 0.00001 {
                    drafts[project]?.removeValue(forKey: item.id); migrated = true
                }
            }
            if migrated { save() }
        }
        self.items = items; self.floor = floor
        var migrated = false
        var recovery = defaults?.data(forKey: "officeLayoutDraft.fixedBoundsBackup.v1")
            .flatMap { try? JSONDecoder().decode([String: [String: OfficeEditTransform]].self, from: $0) } ?? [:]
        for item in items {
            guard let value = drafts[project]?[item.id] else { continue }
            let bounded = constrained(value, for: item)
            item.apply(bounded)
            if abs(bounded.x-value.x) > 0.0001 || abs(bounded.z-value.z) > 0.0001 {
                if recovery[project]?[item.id] == nil { recovery[project, default: [:]][item.id] = value }
                drafts[project]?[item.id] = bounded; migrated = true
            }
        }
        if migrated {
            if let data = try? JSONEncoder().encode(recovery) { defaults?.set(data, forKey: "officeLayoutDraft.fixedBoundsBackup.v1") }
            save()
        }
        selection.formIntersection(Set(items.map(\.id)))
        updateOutline()
    }

    var status: String? {
        guard enabled else { return nil }
        let name = selection.count > 1 ? "\(selection.count) items selected" : items.first { $0.id == selected }?.label ?? "Drag empty floor to select furniture"
        return "EDIT MODE · \(name) · Shift to add · Drag selection to move · 1 ↶ / 2 ↷ 15° · E to finish" + (exportError.map { " · \($0)" } ?? "")
    }
    func toggle() { guard project != nil else { return }; enabled ? finish() : start() }
    private func start() { enabled = true; updateOutline(); changed?() }
    func finish() {
        guard enabled else { return }
        save(); enabled = false; dragStart = nil; dragTransforms = [:]; prepareReconciliation(); changed?()
    }
    func choose(_ id: String?) {
        chooseMany(id.map { [$0] } ?? [])
    }
    func chooseMany(_ ids: Set<String>) {
        selection = ids.intersection(Set(items.map(\.id)))
        dragStart = nil; dragTransforms = [:]; updateOutline(); changed?()
    }
    func items(in rectangle: CGRect, view: SCNView) -> Set<String> {
        Set(items.filter { item in
            let box = item.id.hasPrefix("desk:") || item.node.childNodes.isEmpty && item.node.geometry == nil
                ? (min: SCNVector3(-item.width/2, 0, -item.depth/2), max: SCNVector3(item.width/2, 1.4, item.depth/2))
                : item.node.boundingBox
            let corners = [box.min.x, box.max.x].flatMap { x in
                [box.min.y, box.max.y].flatMap { y in
                    [box.min.z, box.max.z].map { z in view.projectPoint(item.node.convertPosition(SCNVector3(x,y,z), to: nil)) }
                }
            }
            guard corners.allSatisfy({ $0.z >= 0 && $0.z <= 1 }) else { return false }
            let xs = corners.map { CGFloat($0.x) }, ys = corners.map { CGFloat($0.y) }
            let projected = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()!-xs.min()!, height: ys.max()!-ys.min()!)
            return rectangle.intersects(projected)
        }.map(\.id))
    }
    func item(for node: SCNNode) -> Item? {
        var cursor: SCNNode? = node
        while let current = cursor {
            if items.contains(where: { $0.ignored === current }) { return nil }
            if let item = items.first(where: { $0.node === current }) { return item }
            cursor = current.parent
        }
        return nil
    }
    func beginDrag(at point: SCNVector3?) {
        prepareReconciliation()
        dragStart = point
        dragTransforms = Dictionary(uniqueKeysWithValues: items.filter { selection.contains($0.id) }.map { ($0.id, transform($0)) })
        updateOutline()
    }
    func drag(to point: SCNVector3?) {
        guard enabled, let project, let point, let start = dragStart, !dragTransforms.isEmpty else { return }
        prepareReconciliation()
        var dx = Double(point.x - start.x), dz = Double(point.z - start.z)
        // Intersect the translation limits of every selected item; never clamp items independently.
        for item in items {
            guard let original = dragTransforms[item.id] else { continue }
            var proposed = original; proposed.x += dx; proposed.z += dz
            let bounded = constrained(proposed, for: item)
            dx += bounded.x - proposed.x; dz += bounded.z - proposed.z
            item.apply(original)
        }
        for item in items {
            guard var value = dragTransforms[item.id] else { continue }
            value.x += dx; value.z += dz
            drafts[project, default: [:]][item.id] = value; item.apply(value)
        }
        updateOutline(); changed?()
    }
    func endDrag() { dragStart = nil; dragTransforms = [:]; save() }
    func rotate(clockwise: Bool) {
        guard enabled else { return }
        prepareReconciliation()
        for item in items where selection.contains(item.id) {
            var value = transform(item)
            value.rotationRadians += (clockwise ? -1 : 1) * .pi / 12
            value.rotationRadians = value.rotationRadians.remainder(dividingBy: .pi * 2)
            set(value, for: item)
        }
        updateOutline(); changed?(); save()
    }
    private func transform(_ item: Item) -> OfficeEditTransform {
        .init(x: Double(item.node.worldPosition.x), z: Double(item.node.worldPosition.z), rotationRadians: Double(item.node.eulerAngles.y))
    }
    private func set(_ proposed: OfficeEditTransform, for item: Item) {
        guard let project else { return }
        let value = constrained(proposed, for: item)
        drafts[project, default: [:]][item.id] = value
        item.apply(value)
    }
    /// Clamp transformed occupied bounds, including asymmetric authored asset origins.
    private func constrained(_ proposed: OfficeEditTransform, for item: Item) -> OfficeEditTransform {
        item.apply(proposed)
        var value = proposed
        let bounds: (min: SCNVector3, max: SCNVector3)
        if item.id.hasPrefix("desk:") || item.node.childNodes.isEmpty && item.node.geometry == nil {
            bounds = (SCNVector3(-item.width/2,0,-item.depth/2), SCNVector3(item.width/2,0,item.depth/2))
        } else { bounds = item.node.boundingBox }
        let a = item.node.convertPosition(SCNVector3(bounds.min.x,0,bounds.min.z), to: nil)
        let b = item.node.convertPosition(SCNVector3(bounds.min.x,0,bounds.max.z), to: nil)
        let c = item.node.convertPosition(SCNVector3(bounds.max.x,0,bounds.min.z), to: nil)
        let d = item.node.convertPosition(SCNVector3(bounds.max.x,0,bounds.max.z), to: nil)
        let minX = Double(min(a.x,b.x,c.x,d.x)), maxX = Double(max(a.x,b.x,c.x,d.x))
        let minZ = Double(min(a.z,b.z,c.z,d.z)), maxZ = Double(max(a.z,b.z,c.z,d.z))
        value.x += max(0, floor.minX+0.1-minX) - max(0, maxX-(floor.maxX-0.65))
        value.z += max(0, floor.minZ+0.65-minZ) - max(0, maxZ-(floor.maxZ-0.1))
        return value
    }

    private func updateOutline() {
        prepareReconciliation()
        guard enabled else { return }
        for item in items where selection.contains(item.id) {
            let outline = SCNNode()
            let box = SCNBox(width: item.width + 0.12, height: 0.025, length: item.depth + 0.12, chamferRadius: 0)
            let material = SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents = NSColor.systemBlue
            material.fillMode = .lines; material.readsFromDepthBuffer = false
            box.materials = [material]; outline.geometry = box; outline.categoryBitMask = 0
            outline.castsShadow = false; outline.position = SCNVector3(0,0.025,0); outline.renderingOrder = 100
            item.node.addChildNode(outline); outlines.append(outline)
        }
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        defaults?.set(data, forKey: Self.key)
        guard let exportURL else { return }
        writer.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: exportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: exportURL, options: .atomic)
            } catch {
                Task { @MainActor in self?.exportError = "Draft export failed; local settings retained"; self?.changed?() }
            }
        }
    }

    static func floorPoint(_ point: CGPoint, in view: SCNView) -> SCNVector3? {
        let near = view.unprojectPoint(SCNVector3(point.x,point.y,0))
        let far = view.unprojectPoint(SCNVector3(point.x,point.y,1))
        let delta = SCNVector3(far.x-near.x,far.y-near.y,far.z-near.z)
        guard abs(delta.y) > 0.00001 else { return nil }
        let t = -near.y/delta.y
        guard t >= 0, t <= 1 else { return nil }
        return SCNVector3(near.x + delta.x*t,0,near.z + delta.z*t)
    }
}
