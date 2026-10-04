import SwiftUI
import AppKit

struct UpdateComposerAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

struct AppUpdateOverlay: View {
    let updates: AppUpdateCoordinator
    var composer: Anchor<CGRect>?
    @State private var windowAvailable = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        GeometryReader { geometry in
            let composerTop = composer.map { geometry[$0].minY }
            let bottom = composerTop.map { max(20, geometry.size.height - $0 + 12) } ?? 20
            VStack {
                Spacer(minLength: 8)
                if updates.visible {
                    AppUpdateCard(updates: updates, announcementsEnabled: windowAvailable)
                        .opacity(windowAvailable ? 1 : 0).allowsHitTesting(windowAvailable)
                        .frame(width: min(320, max(180, geometry.size.width - 40)))
                        .frame(maxHeight: max(100, geometry.size.height - bottom - 16), alignment: .bottom)
                        .transition(reducedMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20).padding(.bottom, bottom)
            .animation(reducedMotion ? .easeOut(duration: 0.12) : .spring(response: 0.25, dampingFraction: 1), value: updates.visible)
            .background(UpdateWindowAvailability { windowAvailable = $0 })
        }
    }
}

struct AppUpdateCard: View {
    @Bindable var updates: AppUpdateCoordinator
    var announcementsEnabled = true
    @Environment(\.colorSchemeContrast) private var contrast
    private var title: String {
        switch updates.phase {
        case .available: "Diorama \(updates.version) is available"
        case .downloading: "Downloading update"
        case .preparing: "Preparing update…"
        case .ready: "Update ready"
        case .restarting: "Restarting Diorama…"
        case .failed: "Couldn’t update Diorama"
        case .checking: "Checking for updates…"
        case .current: "You’re up to date"
        case .idle: "Diorama updates"
        }
    }
    private var subtitle: String {
        if !updates.detail.isEmpty { return updates.detail }
        return switch updates.phase {
        case .available: "Get the latest improvements."
        case .downloading: "You can keep working while this downloads."
        case .preparing: "Verifying the download before installation."
        case .ready: "Restart to finish installing version \(updates.version)."
        case .restarting: "Saving your workspace and stopping agents."
        default: ""
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: updates.phase == .failed ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.down.app")
                        .font(.system(size: 20)).foregroundStyle(.blue).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { updates.dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
                    }.buttonStyle(UpdateActionStyle()).pointingHand().accessibilityLabel("Dismiss update notification")
                }
                Group {
                    if updates.phase == .downloading {
                        HStack(spacing: 10) {
                            if let progress = updates.progress {
                                ProgressView(value: progress, total: 1.0).tint(Color.blue)
                            } else { ProgressView().controlSize(.small) }
                            if let progress = updates.progress {
                                Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit().font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }.accessibilityLabel("Download progress")
                    } else if [.checking, .preparing, .restarting].contains(updates.phase) {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
                    } else { Color.clear }
                }.frame(height: 16)
                HStack {
                    Button("Release notes") { updates.releaseNotes() }.buttonStyle(UpdateActionStyle()).pointingHand()
                    Spacer()
                    if updates.phase == .available {
                        Button("Download update") { updates.download() }.buttonStyle(UpdateActionStyle(primary: true)).pointingHand()
                    } else if updates.phase == .ready {
                        Button("Restart") { updates.requestRestart() }.buttonStyle(UpdateActionStyle(primary: true)).pointingHand()
                    } else if updates.phase == .failed {
                        Button("Retry") { updates.check() }.buttonStyle(UpdateActionStyle(primary: true)).pointingHand()
                    }
                }.font(.system(size: 12, weight: .medium)).frame(minHeight: 30)
                if updates.preview { Text("Preview · simulated update").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black.opacity(contrast == .increased ? 0.55 : 0.1), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .environment(\.colorScheme, .light).tint(.blue)
        .onChange(of: updates.phase) { _, phase in
            guard announcementsEnabled, !updates.hidden, [.available, .ready, .failed, .current].contains(phase), let window = NSApp.keyWindow else { return }
            NSAccessibility.post(element: window, notification: .announcementRequested,
                userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .alert("Restart and update?", isPresented: $updates.confirmingRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Stop agents and restart", role: .destructive) { updates.confirmRestart() }
        } message: {
            Text("This will stop active agents and terminal commands. Your files and saved chat history will remain, but interrupted work won’t resume automatically.")
        }
    }
}

private struct UpdateActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, primary ? 10 : 4).padding(.vertical, primary ? 7 : 3)
            .foregroundStyle(primary ? Color.white : Color.blue)
            .background(primary ? Color.blue.opacity(configuration.isPressed ? 0.75 : hovered ? 0.88 : 1) : Color.blue.opacity(hovered || configuration.isPressed ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.97 : 1)
            .onHover { hovered = $0 }
    }
}

private struct UpdateWindowAvailability: NSViewRepresentable {
    var changed: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.publish() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }
    final class Probe: NSView {
        var changed: (Bool) -> Void = { _ in }
        private var last: Bool?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didEndSheetNotification, NSWindow.willBeginSheetNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(publish), name: name, object: window)
            }
            publish()
        }
        @objc func publish() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let value = self.window?.isKeyWindow == true && self.window?.attachedSheet == nil
                guard self.last != value else { return }
                self.last = value; self.changed(value)
            }
        }
        func stop() { NotificationCenter.default.removeObserver(self); last = nil }
    }
}
