import SwiftUI
import DioramaCore

struct GitHubSettingsView: View {
    var onboarding = false
    var connectionChanged: ((Bool) -> Void)? = nil
    @State private var identity: GitHubIdentity?
    @State private var status = "Checking connection…"
    @State private var code: GitHubDeviceCode?
    @State private var loginTask: Task<Void, Never>?
    @State private var checking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("GitHub").font(.headline)
                    Text(identity.map { "Connected as @" + $0.login } ?? status).font(.caption).textSelection(.enabled)
                }
                Spacer()
                if !onboarding || identity == nil { Button(identity == nil ? "Connect GitHub" : "Reconnect") { connect() }.pointingHand().disabled(loginTask != nil || checking) }
                if !onboarding { Button("Check connection") { Task { await check() } }.pointingHand().disabled(checking || loginTask != nil)
                Button("Disconnect") {
                    loginTask?.cancel(); loginTask = nil; code = nil
                    Task { do { try await GitHubAccount.shared.disconnect(); identity = nil; status = "Not connected" } catch { status = error.localizedDescription } }
                }.pointingHand() }
            }
            if let code {
                Text("Enter this code on GitHub: \(code.user_code)").font(.headline).textSelection(.enabled)
                Text("Waiting for authorization in your browser…").font(.caption)
                Link("Open GitHub", destination: URL(string: "https://github.com/login/device")!).pointingHand()
            }
            if loginTask != nil { ProgressView("Waiting for GitHub…").controlSize(.small) }
            Text("Connecting does not publish local projects. Disconnecting affects only Diorama on this Mac.").font(.caption).foregroundStyle(.secondary)
            if identity == nil {
                Button("Allow Keychain access…") {
                    checking = true
                    Task.detached {
                        _ = try? GitHubCredentials.loadRecord(allowInteraction: true)
                        await check()
                    }
                }.pointingHand().disabled(checking || loginTask != nil)
            }
            Link("Manage Diorama authorization on GitHub", destination: URL(string: "https://github.com/settings/applications")!).pointingHand().font(.caption)
        }.task { await check() }
        .onChange(of: identity?.login) { _, value in connectionChanged?(value != nil) }.onDisappear { loginTask?.cancel() }
    }
    private func check() async {
        checking = true; defer { checking = false }
        do { identity = try await GitHubAccount.shared.identity(); status = "Connected" }
        catch { identity = nil; status = error.localizedDescription }
    }
    private func connect() {
        loginTask = Task {
            defer { loginTask = nil; code = nil }
            do {
                let device = try await GitHubAccount.shared.startLogin(); code = device
                NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!)
                identity = try await GitHubAccount.shared.finishLogin(device); status = "Connected"
            } catch is CancellationError { status = "Sign-in cancelled" }
            catch { status = error.localizedDescription }
        }
    }
}
