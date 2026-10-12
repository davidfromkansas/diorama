import SwiftUI
import DioramaCore

struct GitHubSettingsView: View {
    var onboarding = false
    var connectionChanged: ((Bool) -> Void)? = nil
    @State private var connection = GitHubConnection.shared
    @State private var managing = false
    var body: some View {
        if onboarding { onboardingBody } else { settingsBody }
    }
    /// Settings: who's connected (or what's wrong) and the GitHub modal, which does the rest.
    private var settingsBody: some View {
        HStack(spacing: 12) {
            GitHubMarkTile(size: 36, mark: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text("GitHub").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(connection.login == nil ? "Connect…" : "Manage…") { managing = true }.pointingHand()
        }
        .sheet(isPresented: $managing) { GitHubConnectionModal() }
        .task { await connection.refresh() }
        .onChange(of: connection.login) { connectionChanged?(connection.login != nil) }
    }
    private var summary: String {
        switch connection.state {
        case .checking: "Checking connection…"
        case .notConnected: "Not connected. Connecting does not publish local projects."
        case .signingIn: "Finishing sign-in in your browser…"
        case .connected(let login, _): "Connected as @" + login
        case .needsAttention(let problem): problem.message
        case .needsKeychain: "macOS needs your permission to use the saved login."
        }
    }
    /// Setup step: a branded header and the shared connect panel, after the agentsim GitHub dialog.
    private var onboardingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                GitHubMarkTile(size: 36, mark: 19)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GITHUB · OPTIONAL").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
                    Text("Bring your projects to GitHub").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                }
            }
            Text("Import repositories, publish projects, and open pull requests.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            GitHubConnectPanel { connectionChanged?($0 != nil) }.padding(.top, 16)
            HStack(spacing: 6) {
                Text("Connecting does not publish local projects.")
                Link("Manage authorization on GitHub", destination: URL(string: "https://github.com/settings/applications")!).pointingHand()
            }.font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 14)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
