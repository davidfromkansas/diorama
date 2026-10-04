import AppKit
import SceneKit
import Testing
@testable import DioramaApp

@MainActor struct OfficeLayoutEditorTests {
    private func item(_ node: SCNNode, ignored: SCNNode? = nil) -> OfficeLayoutEditor.Item {
        .init(id: "desk:0", label: "Desk 1", node: node, ignored: ignored, width: 1.8, depth: 1.9) { value in
            node.position = SCNVector3(value.x,0,value.z); node.eulerAngles.y = value.rotationRadians
        }
    }
    private let floor = LeisureBounds(minX: -10, maxX: 10, minZ: -5, maxZ: 20)

    @Test func draggingRotationAndPersistenceKeepStableIdentity() throws {
        let suite = "office-edit-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let node = SCNNode(); node.position = SCNVector3(2,0,3)
        let editor = OfficeLayoutEditor(); editor.defaults = defaults
        editor.configure(project: "p", items: [item(node)], floor: floor)
        editor.toggle(); editor.choose("desk:0")
        editor.beginDrag(at: SCNVector3(2.5,0,3.5)); editor.drag(to: SCNVector3(5.5,0,7.5)); editor.endDrag()
        #expect(abs(node.position.x-5) < 0.001 && abs(node.position.z-7) < 0.001)
        editor.rotate(clockwise: false)
        #expect(abs(Double(node.eulerAngles.y) - .pi/12) < 0.001)
        editor.rotate(clockwise: true); #expect(abs(node.eulerAngles.y) < 0.001)
        editor.finish(); #expect(!editor.enabled)
        let replacement = SCNNode(), restored = OfficeLayoutEditor(); restored.defaults = defaults
        restored.configure(project: "p", items: [item(replacement)], floor: floor)
        #expect(abs(replacement.position.x-5) < 0.001 && abs(replacement.position.z-7) < 0.001)
        let other = SCNNode()
        restored.configure(project: "other", items: [item(other)], floor: floor)
        #expect(other.position.x == 0 && other.position.z == 0)
    }

    @Test func floorClampingAndAgentExclusion() {
        let node = SCNNode(), agent = SCNNode(), furniture = SCNNode(), hand = SCNNode()
        node.addChildNode(agent); agent.addChildNode(hand); node.addChildNode(furniture)
        let editor = OfficeLayoutEditor(); editor.configure(project: "p", items: [item(node, ignored: agent)], floor: floor)
        #expect(editor.item(for: hand) == nil)
        #expect(editor.item(for: furniture)?.id == "desk:0")
        editor.toggle(); editor.choose("desk:0"); editor.beginDrag(at: .init(0,0,0)); editor.drag(to: .init(100,0,-100))
        #expect(node.position.x < 9 && node.position.z > -4)
        editor.choose(nil); let before = node.position; editor.rotate(clockwise: true)
        #expect(node.position.x == before.x && node.position.z == before.z)
    }

    @Test func standingAgentDoesNotMoveWhenItsDeskRotates() {
        let station = OfficeWorkstation(id: "test")
        station.place(desk: .init(slot: 0,x: 4,z: 2,yaw: .pi/2), standingAt: .init(slot: 0,x: 7,z: 6,yaw: 0), animated: false)
        #expect(abs(station.person.worldPosition.x-7) < 0.001 && abs(station.person.worldPosition.z-6) < 0.001)
        #expect(abs(station.person.worldOrientation.y) < 0.001)
    }

    @Test func groupDragPreservesSpacingAtBoundaryAndPersistsAllMembers() throws {
        let suite = "office-group-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let a = SCNNode(), b = SCNNode(), c = SCNNode()
        a.position = .init(1,0,2); b.position = .init(4,0,2); c.position = .init(-4,0,2)
        func member(_ id: String, _ node: SCNNode) -> OfficeLayoutEditor.Item {
            .init(id: id, label: id, node: node, ignored: nil, width: 1.8, depth: 1.9) { value in
                node.position = .init(value.x,0,value.z); node.eulerAngles.y = value.rotationRadians
            }
        }
        let members = [member("desk:0",a), member("desk:1",b), member("desk:2",c)]
        let editor = OfficeLayoutEditor(); editor.defaults = defaults
        editor.configure(project: "p", items: members, floor: floor); editor.toggle()
        editor.chooseMany(["desk:0", "desk:1"])
        editor.beginDrag(at: .init(1,0,2)); editor.drag(to: .init(101,0,102)); editor.endDrag()
        #expect(abs((b.position.x-a.position.x)-3) < 0.001)
        #expect(abs(b.position.z-a.position.z) < 0.001)
        #expect(b.position.x <= 8.451 && b.position.z <= 18.951)
        #expect(c.position.x == -4 && c.position.z == 2)
        #expect(editor.drafts["p"]?.count == 2)
        editor.rotate(clockwise: true)
        #expect(abs(a.eulerAngles.y-b.eulerAngles.y) < 0.001)
        let restored = OfficeLayoutEditor(); restored.defaults = defaults
        restored.configure(project: "p", items: members, floor: floor)
        #expect(restored.drafts == editor.drafts)
        editor.configure(project: "other", items: members, floor: floor)
        #expect(editor.selection.isEmpty && !editor.enabled)
    }

    @Test func marqueeSelectsFurnitureWithinProjectedBounds() {
        let view = SCNView(frame: NSRect(x: 0,y: 0,width: 800,height: 600))
        view.scene = SCNScene(); let camera = SCNNode(); camera.camera = SCNCamera()
        camera.position = .init(0,10,15); camera.look(at: .init(0,0,0))
        view.scene?.rootNode.addChildNode(camera); view.pointOfView = camera
        let node = SCNNode(); view.scene?.rootNode.addChildNode(node)
        let editor = OfficeLayoutEditor(); editor.configure(project: "p", items: [item(node)], floor: floor)
        #expect(editor.items(in: view.bounds, view: view) == ["desk:0"])
        #expect(editor.items(in: CGRect(x: -1000,y: -1000,width: 10,height: 10), view: view).isEmpty)
    }

    @Test func screenRayIntersectsFloor() throws {
        let view = SCNView(frame: NSRect(x: 0,y: 0,width: 800,height: 600))
        view.scene = SCNScene(); let camera = SCNNode(); camera.camera = SCNCamera()
        camera.position = SCNVector3(4,8,10); camera.look(at: SCNVector3Zero); view.scene?.rootNode.addChildNode(camera); view.pointOfView = camera
        let source = SCNVector3(2,0,3); let screen = view.projectPoint(source)
        let result = try #require(OfficeLayoutEditor.floorPoint(CGPoint(x: screen.x,y: screen.y), in: view))
        #expect(abs(result.x-source.x) < 0.01 && abs(result.z-source.z) < 0.01)
    }
}
