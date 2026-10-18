import SwiftUI

/// A project's settings, from the gear in its scene's corner: where its agents work, and whether
/// the scene makes sounds.
struct ProjectSceneSettings: View {
    @Binding var scene: SceneKind
    @Binding var sounds: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project settings").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Scene").font(.subheadline).foregroundStyle(.secondary)
                Picker("Scene", selection: $scene) {
                    ForEach(SceneKind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(scene.summary).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Sounds", isOn: $sounds)
        }
        .padding(16)
        .frame(width: 280)
    }
}

extension SceneKind {
    var symbol: String {
        switch self {
        case .kitchen: "fork.knife"
        case .office: "building.2"
        }
    }
    /// What the agents do there, for the settings popover.
    var summary: String {
        switch self {
        case .kitchen: "Agents cook as chefs: orders, prep, the stove and the serving window."
        case .office: "Agents work a startup floor: the ticket board, whiteboards, desks and the demo table."
        }
    }
}
