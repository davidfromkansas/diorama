import SwiftUI
import DioramaCore

/// Device-code sign-ins waiting on the browser. Development auto-reload holds off while any are
/// pending, since relaunching would drop the poll that completes the sign-in.
enum GitHubSignIn {
    static var pending = 0
}

/// Connects Diorama's GitHub account in place, inside setup and Add GitHub project: device-code
/// sign-in, the code to enter, and the Keychain permission a separately signed build may need. It
/// shows the shared `GitHubConnection`, so it always agrees with the home button and the GitHub modal.
struct GitHubConnectPanel: View {
    var changed: ((GitHubIdentity?) -> Void)? = nil
    @State private var connection = GitHubConnection.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authPanel
            if connection.state == .needsKeychain { keychainRow }
            else if case .needsAttention(let problem) = connection.state {
                Text(problem.message).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            } else if let error = connection.signInError, connection.login == nil, !connection.signingIn {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .task { await connection.refresh() }
        .onChange(of: connection.login) { changed?(connection.identity) }
    }

    private var authPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                GitHubMarkTile(size: 44, mark: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.login.map { "Connected as @" + $0 } ?? "Connect your GitHub account").font(.system(size: 14, weight: .semibold))
                    Text(connection.login == nil ? "Diorama opens GitHub in your browser. Your password is never shared." : "Diorama can now import, publish, and open pull requests.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                switch connection.state {
                case .connected:
                    Label("Connected", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(GitHubStyle.green)
                case .checking:
                    ProgressView().controlSize(.small).accessibilityLabel("Checking GitHub connection")
                case .signingIn:
                    Button("Cancel") { connection.cancelSignIn() }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).pointingHand()
                default:
                    Button { connection.connect() } label: {
                        HStack(spacing: 9) { Text("Continue with GitHub"); Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)) }
                    }.buttonStyle(GitHubContinueButtonStyle()).pointingHand().disabled(connection.signingIn)
                }
            }
            if case .signingIn(let code, _, _) = connection.state {
                Divider().padding(.top, 14).padding(.bottom, 12)
                HStack(spacing: 11) {
                    Text("ENTER THIS CODE ON GITHUB").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.5).foregroundStyle(.secondary)
                    Text(code).font(.system(size: 14, weight: .semibold, design: .monospaced)).tracking(1.5).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.15)))
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy code").accessibilityLabel("Copy code").pointingHand()
                    Button { connection.openVerification() } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.borderless).help("Open GitHub again").accessibilityLabel("Open GitHub again").pointingHand()
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
            Button("Allow Keychain access…") { Task { await connection.allowKeychainAccess() } }
                .controlSize(.small).pointingHand().disabled(connection.checking || connection.signingIn)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
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
