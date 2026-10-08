import SwiftUI
import DioramaCore

/// Device-code sign-ins waiting on the browser. Development auto-reload holds off while any are
/// pending, since relaunching would drop the poll that completes the sign-in.
enum GitHubSignIn {
    static var pending = 0
}

/// Connects Diorama's GitHub account in place: device-code sign-in, the code to enter, and the
/// Keychain permission a separately signed build may need. Shared by setup and Add GitHub project.
struct GitHubConnectPanel: View {
    var changed: ((GitHubIdentity?) -> Void)? = nil
    @State private var identity: GitHubIdentity?
    @State private var status = "Checking connection…"
    @State private var code: GitHubDeviceCode?
    @State private var loginTask: Task<Void, Never>?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authPanel
            if needsKeychain && code == nil { keychainRow }
            else if identity == nil, loginTask == nil, !checking, status != "Checking connection…", status != "Not connected" {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .task { await check() }
        .onChange(of: identity?.login) { changed?(identity) }
        .onDisappear { loginTask?.cancel() }
    }

    /// Diorama found a saved login, but macOS needs permission before this build can read it.
    private var needsKeychain: Bool { identity == nil && status.contains("Keychain") && !status.contains("Could not") }

    private var authPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                GitHubMarkTile(size: 44, mark: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(identity.map { "Connected as @" + $0.login } ?? "Connect your GitHub account").font(.system(size: 14, weight: .semibold))
                    Text(identity == nil ? "Diorama opens GitHub in your browser. Your password is never shared." : "Diorama can now import, publish, and open pull requests.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if identity != nil {
                    Label("Connected", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                } else if checking && loginTask == nil {
                    ProgressView().controlSize(.small).accessibilityLabel("Checking GitHub connection")
                } else if code == nil {
                    Button(action: connect) {
                        HStack(spacing: 9) { Text("Continue with GitHub"); Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)) }
                    }.buttonStyle(GitHubContinueButtonStyle()).pointingHand().disabled(loginTask != nil)
                }
            }
            if let code {
                Divider().padding(.top, 14).padding(.bottom, 12)
                HStack(spacing: 11) {
                    Text("ENTER THIS CODE ON GITHUB").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.5).foregroundStyle(.secondary)
                    Text(code.user_code).font(.system(size: 14, weight: .semibold, design: .monospaced)).tracking(1.5).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.15)))
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code.user_code, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy code").accessibilityLabel("Copy code").pointingHand()
                    Spacer(minLength: 8)
                    ProgressView().controlSize(.mini)
                    Text("Waiting for browser confirmation…").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
    }
    private var keychainRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill").foregroundStyle(.secondary)
            Text("Diorama found a saved GitHub login. macOS needs your permission to use it.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Allow Keychain access…") {
                checking = true
                Task.detached {
                    _ = try? GitHubCredentials.loadRecord(allowInteraction: true)
                    await check()
                }
            }.controlSize(.small).pointingHand().disabled(checking || loginTask != nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
    }
    private func check() async {
        checking = true; defer { checking = false }
        do { identity = try await GitHubAccount.shared.identity(); status = "Connected" }
        catch { identity = nil; status = error.localizedDescription }
    }
    private func connect() {
        GitHubSignIn.pending += 1
        loginTask = Task {
            defer { loginTask = nil; code = nil; GitHubSignIn.pending -= 1 }
            do {
                let device = try await GitHubAccount.shared.startLogin(); code = device
                NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!)
                identity = try await GitHubAccount.shared.finishLogin(device); status = "Connected"
            } catch is CancellationError { status = "Sign-in cancelled" }
            catch { status = error.localizedDescription }
        }
    }
}

/// The GitHub mark on a small bordered tile.
struct GitHubMarkTile: View {
    let size: CGFloat, mark: CGFloat
    private static let image: NSImage? = {
        guard let url = Bundle.dioramaResources?.url(forResource: "GitHub", withExtension: "svg", subdirectory: "ConnectorBrand"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()
    var body: some View {
        Group {
            if let image = Self.image { Image(nsImage: image).resizable().scaledToFit() } else { Image(systemName: "link") }
        }
        .frame(width: mark, height: mark)
        .frame(width: size, height: size)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: size * 0.25))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(.primary.opacity(0.14)))
        .accessibilityHidden(true)
    }
}

/// A light, high-contrast pill that stands out on the dark setup sheet.
struct GitHubContinueButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(white: 0.12))
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Color(white: configuration.isPressed ? 0.88 : 0.96), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.15)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.12), value: configuration.isPressed)
    }
}
