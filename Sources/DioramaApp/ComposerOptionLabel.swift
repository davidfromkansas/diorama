import SwiftUI

/// Full-width, consistently aligned labels for the compact creation menu.
struct ComposerOptionLabel: View {
    let title: String
    let icon: String
    var checked = false
    var disclosure = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).frame(width: 20)
            Text(title).font(.system(size: 14))
            Spacer(minLength: 10)
            if checked { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
            if disclosure { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).frame(height: 36)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
