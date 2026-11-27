import SwiftUI
import DioramaCore

/// Each agent's accent color, for model menus, meters and marks.
extension Provider {
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.79, green: 0.39, blue: 0.26)
        case .codex: Color(white: 0.13)
        case .devin: Color(red: 0.05, green: 0.55, blue: 0.52)
        }
    }
}
