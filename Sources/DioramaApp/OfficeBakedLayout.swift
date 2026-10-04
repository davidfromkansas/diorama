import Foundation
import SceneKit

/// Captured user-approved placement-node transforms; authored asset rotations remain intact.
enum OfficeBakedLayout {
    private static let saved: [String: [String: OfficeEditTransform]] = {
        let bundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Diorama_DioramaApp.bundle")) } ?? Bundle.module
        guard let url = bundle.url(forResource: "BakedOfficeLayout", withExtension: "json", subdirectory: "OfficeFurniture"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: OfficeEditTransform]].self, from: data)) ?? [:]
    }()
    static var sourceProject: String? { saved.keys.sorted().first }
    static var transforms: [String: OfficeEditTransform] { sourceProject.flatMap { saved[$0] } ?? [:] }
    static func apply(to node: SCNNode) {
        guard let id = node.name, let value = transforms[id] else { return }
        node.position.x = value.x; node.position.z = value.z
        node.eulerAngles.y = value.rotationRadians
    }
}
