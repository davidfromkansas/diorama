import SwiftUI
import DioramaCore

/// Displays Diorama's own GitHub account, independently of any ambient gh login.
struct SidebarGitHubStatus: View {
    var visible: Bool
    @Environment(\.openSettings) private var openSettings
    @State private var status = "Checking…"
    @State private var connected = false
    @State private var detail = "Checking GitHub connection"
    @State private var refreshID = UUID()
    private static let mark: NSImage? = {
        guard let url = Bundle.module.url(forResource: "GitHub", withExtension: "svg", subdirectory: "ConnectorBrand"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Button { openSettings() } label: {
            HStack(spacing: 8) {
                Group {
                    if let mark = Self.mark {
                        Image(nsImage: mark).resizable().scaledToFit()
                    } else {
                        Image(systemName: "link")
                    }
                }.frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GitHub")
                    HStack(spacing: 5) {
                        Circle().fill(connected ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(detail + ". Manage GitHub in Settings.")
        .accessibilityLabel("GitHub, " + status)
        .accessibilityHint("Opens account settings")
        .task(id: refreshID) {
            guard visible else { return }
            await refresh()
        }
        .onChange(of: visible) { _, shown in if shown { refreshID = UUID() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if visible { refreshID = UUID() }
        }
    }

    private func refresh() async {
        do {
            // Missing credentials are distinct from a temporary verification failure.
            let hasCredentials = try await Task.detached {
                try GitHubCredentials.loadRecord() != nil
            }.value
            guard !Task.isCancelled else { return }
            guard hasCredentials else {
                connected = false; status = "Not connected"; detail = "GitHub is not connected"
                return
            }
            let identity = try await GitHubAccount.shared.identity()
            guard !Task.isCancelled else { return }
            connected = true; status = "Connected"; detail = "Connected as @" + identity.login
        } catch {
            guard !Task.isCancelled else { return }
            connected = false; status = "Check connection"; detail = error.localizedDescription
        }
    }
}
