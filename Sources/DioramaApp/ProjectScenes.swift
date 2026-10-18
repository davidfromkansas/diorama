import Foundation
import Observation

/// Which scene each project's agents work in (the gear in the scene's corner). One choice per
/// project, shared by every window and kept across launches; projects without one use the kitchen.
@Observable final class ProjectScenes {
    static let key = "projectScenes.v1"
    private(set) var kinds: [String: SceneKind]
    @ObservationIgnored private let defaults: UserDefaults?

    /// `defaults` nil keeps choices in memory only (demo recordings).
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        kinds = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: SceneKind].self, from: $0) } ?? [:]
    }
    func kind(for project: String?) -> SceneKind { project.flatMap { kinds[$0] } ?? .kitchen }
    func set(_ kind: SceneKind, for project: String) {
        guard kinds[project] != kind else { return }
        kinds[project] = kind == .kitchen ? nil : kind
        if let defaults, let data = try? JSONEncoder().encode(kinds) { defaults.set(data, forKey: Self.key) }
    }
}

extension LibraryModel {
    /// Switches a project to another scene; the scene on screen follows when it's that project's.
    func setScene(_ kind: SceneKind, project: String) {
        projectScenes.set(kind, for: project)
        if projects.selectedID == project || spatial.focus.projectID == project { spatial.sceneKind = kind }
    }
}
