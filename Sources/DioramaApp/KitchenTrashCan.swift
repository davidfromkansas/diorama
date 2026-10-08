import SwiftUI

/// The trash can that appears while a chef is held: dropping the chef in archives its thread.
/// Its lid tips open and it grows while the chef is over it; a chef that can't be archived
/// turns it red with the reason.
struct KitchenTrashCan: View {
    let hold: KitchenHold
    @Environment(\.accessibilityReduceMotion) private var reduced

    private var hot: Bool { hold.overTrash && hold.blocker == nil }
    private var refused: Bool { hold.overTrash && hold.blocker != nil }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(refused ? Color.red : hot ? Color.accentColor : Color.secondary)
                    .rotationEffect(.degrees(hot && !reduced ? -8 : 0), anchor: .bottomTrailing)
            }
            .frame(width: 92, height: 92)
            .background(Circle().fill(.regularMaterial))
            .overlay(Circle().stroke(refused ? Color.red.opacity(0.6) : hot ? Color.accentColor.opacity(0.7) : Color.black.opacity(0.08), lineWidth: hot || refused ? 3 : 1))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .scaleEffect(hot && !reduced ? 1.15 : 1)
            Text(hold.blocker ?? (hot ? "Release to archive" : "Archive \(hold.name)"))
                .font(.callout.weight(.medium))
                .foregroundStyle(refused ? Color.red : Color.primary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.regularMaterial))
        }
        .animation(reduced ? nil : .spring(duration: 0.22), value: hold)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hold.blocker ?? "Trash: drop \(hold.name) here to archive the conversation")
    }
}

/// "Archived Lena · Undo" after a chef went in the trash, or why archiving failed.
struct KitchenUndoBanner: View {
    let text: String
    var undo: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(.callout).lineLimit(2)
            if let undo { Button("Undo", action: undo).buttonStyle(.borderless).fontWeight(.semibold).pointingHand() }
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).pointingHand().accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().stroke(Color.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}
