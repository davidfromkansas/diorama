import SwiftUI
import DioramaCore

/// The GitHub modal, opened from the home sidebar's GitHub button and from Manage… wherever
/// GitHub shows: it signs you in when Diorama isn't connected, and manages the connection when it
/// is. One screen per `GitHubConnection.State`, moving on by itself as the state changes.
struct GitHubConnectionModal: View {
    @State private var connection = GitHubConnection.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .padding(28)
        .frame(width: 480, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).pointingHand().padding(14)
            .keyboardShortcut(.cancelAction).help("Close").accessibilityLabel("Close")
        }
        .task { await connection.refresh() }
        .animation(.easeInOut(duration: 0.18), value: connection.state)
    }

    @ViewBuilder private var content: some View {
        switch connection.state {
        case .checking: checkingScreen
        case .notConnected: connectScreen
        case .signingIn(let code, _, let expires): signingInScreen(code: code, expires: expires)
        case .connected(let login, let checkedAt): manageScreen(login: login, checkedAt: checkedAt)
        case .needsAttention(let problem): attentionScreen(problem)
        case .needsKeychain: keychainScreen
        }
    }

    // MARK: Screens

    private var checkingScreen: some View {
        HStack(spacing: 12) {
            GitHubMarkTile(size: 44, mark: 24)
            ProgressView().controlSize(.small)
            Text("Checking your GitHub connection…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    private var connectScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            GitHubMarkTile(size: 52, mark: 30)
            heading("Connect GitHub", "Link your GitHub account so your agents can work with your repositories.")
            VStack(alignment: .leading, spacing: 0) {
                benefit("square.and.arrow.down", "Import repositories", "Start a project from any repo you can access")
                benefit("square.and.arrow.up", "Publish projects", "Only when you choose to; nothing goes up on its own")
                benefit("arrow.triangle.pull", "Open pull requests", "Send finished work for review from the serving window")
            }
            .padding(6).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
            if let error = connection.signInError {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(GitHubStyle.amberText)
            }
            VStack(spacing: 12) {
                primaryButton("Continue with GitHub", github: true) { connection.connect() }
                Label("You sign in on github.com. Diorama never sees your password.", systemImage: "lock")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func signingInScreen(code: String, expires: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text("Waiting for GitHub…").font(.system(size: 12, weight: .semibold)).foregroundStyle(GitHubStyle.blueText)
            }
            heading("Finish in your browser", "GitHub opened in your browser. Enter this code there, then approve Diorama.")
            VStack(spacing: 14) {
                Text("YOUR CODE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, character in
                        if character == "-" {
                            Text("–").font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.tertiary)
                        } else {
                            Text(String(character)).font(.system(size: 24, weight: .bold, design: .monospaced))
                                .frame(width: 34, height: 44)
                                .background(.background, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.14)))
                        }
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("Code " + code.map(String.init).joined(separator: " "))
                .textSelection(.enabled)
                HStack(spacing: 10) {
                    secondaryButton("Copy code", icon: "doc.on.doc") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    }
                    secondaryButton("Open GitHub again", icon: "arrow.up.right") { connection.openVerification() }
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 10) {
                step(.done, "Open github.com/login/device")
                step(.now, "Enter the code and approve Diorama")
                step(.todo, "Come back here — this closes on its own")
            }
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(expires.timeIntervalSince(context.date)))
                    Text(left > 0 ? "Code expires in \(left / 60):" + String(format: "%02d", left % 60) : "Code expired")
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel sign-in") { connection.cancelSignIn() }.buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).pointingHand()
            }
        }
    }

    private func manageScreen(login: String, checkedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("GitHub").font(.system(size: 20, weight: .bold))
            HStack(spacing: 14) {
                GitHubMarkTile(size: 48, mark: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("@" + login).font(.system(size: 16, weight: .semibold)).textSelection(.enabled)
                    HStack(spacing: 6) {
                        Circle().fill(GitHubStyle.green).frame(width: 7, height: 7)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("Connected · checked " + Self.ago(checkedAt, now: context.date))
                        }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(GitHubStyle.green)
                    }
                }
                Spacer()
                Button { Task { await connection.refresh() } } label: {
                    Group {
                        if connection.checking { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)) }
                    }
                    .frame(width: 34, height: 34).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain).pointingHand().disabled(connection.checking)
                .help("Check the connection again").accessibilityLabel("Check connection again")
            }
            .padding(16).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 9) {
                Text("DIORAMA CAN").font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                ForEach(["Import and clone your repositories", "Push branches and open pull requests", "Create a repository when you publish a project"], id: \.self) { line in
                    Label { Text(line).font(.system(size: 13)) } icon: { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(GitHubStyle.green) }
                }
            }
            VStack(spacing: 0) {
                Divider()
                actionRow("arrow.left.arrow.right", "Switch account", "Sign in to GitHub as someone else") { connection.connect() }
                Link(destination: URL(string: "https://github.com/settings/applications")!) {
                    rowLabel("gearshape", "Manage access on GitHub", "See or revoke Diorama in your GitHub settings", trailing: "arrow.up.right")
                }
                .buttonStyle(.plain).pointingHand()
            }
            HStack(spacing: 14) {
                Text("Disconnecting only signs Diorama out on this Mac. Your repositories and local projects stay as they are.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Disconnect") { confirmDisconnect = true }.buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.5)))
                    .pointingHand()
            }
            .padding(14).background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .confirmationDialog("Disconnect GitHub?", isPresented: $confirmDisconnect) {
                Button("Disconnect", role: .destructive) { Task { await connection.disconnect() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Agents won't be able to push branches or open pull requests until you connect again.")
            }
        }
    }

    private func attentionScreen(_ problem: GitHubConnection.Problem) -> some View {
        let unreachable: Bool = { if case .unreachable = problem { true } else { false } }()
        return VStack(alignment: .leading, spacing: 20) {
            Image(systemName: unreachable ? "wifi.exclamationmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 22)).foregroundStyle(unreachable ? Color.secondary : GitHubStyle.amber)
                .frame(width: 52, height: 52)
                .background((unreachable ? Color.primary.opacity(0.07) : GitHubStyle.amber.opacity(0.16)), in: RoundedRectangle(cornerRadius: 14))
            heading(unreachable ? "Can't reach GitHub" : "Reconnect GitHub",
                    unreachable ? "Diorama couldn't reach GitHub just now. Your login is probably fine; check your network and try again."
                                : "Diorama's access to GitHub stopped working, so agents can't push branches or open pull requests until you sign in again.")
            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT HAPPENED").font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(GitHubStyle.amberText)
                Text(Self.explanation(problem)).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Text(problem.message).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(GitHubStyle.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GitHubStyle.amber.opacity(0.3)))
            VStack(spacing: 10) {
                if unreachable {
                    primaryButton(connection.checking ? "Checking…" : "Try again", github: false) { Task { await connection.refresh() } }
                } else {
                    primaryButton("Reconnect with GitHub", github: true) { connection.connect() }
                }
                HStack(spacing: 8) {
                    if !unreachable {
                        Button("Try again") { Task { await connection.refresh() } }.buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold)).padding(8).pointingHand()
                    }
                    Button("Disconnect instead") { Task { await connection.disconnect() } }.buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.red).padding(8).pointingHand()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var keychainScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "key.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                .frame(width: 52, height: 52).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            heading("Allow access to your saved login", "Diorama found its saved GitHub login, but macOS needs your permission before this build can use it. macOS will ask once.")
            VStack(spacing: 10) {
                primaryButton("Allow access", github: false) { Task { await connection.allowKeychainAccess() } }
                Button("Sign in again instead") { connection.connect() }.buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(8).pointingHand()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Pieces

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 22, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(detail).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 24)
    }
    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 30, height: 30)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }
    /// The main action: inverse of the page (light on dark, dark on light), full width.
    private func primaryButton(_ title: String, github: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if github { GitHubMarkGlyph(size: 17) }
                Text(title).font(.system(size: 14.5, weight: .semibold))
                if github { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)) }
            }
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(.primary, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointingHand().keyboardShortcut(.defaultAction)
    }
    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 32)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).pointingHand()
    }
    private enum Step { case done, now, todo }
    private func step(_ state: Step, _ text: String) -> some View {
        HStack(spacing: 11) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(GitHubStyle.green)
                case .now: Image(systemName: "circle.circle").foregroundStyle(GitHubStyle.blue)
                case .todo: Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 16))
            Text(text).font(.system(size: 13, weight: state == .now ? .semibold : .regular))
                .foregroundStyle(state == .todo ? .secondary : .primary)
                .strikethrough(state == .done, color: .secondary)
        }
    }
    private func actionRow(_ icon: String, _ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, title, detail, trailing: "chevron.right") }.buttonStyle(.plain).pointingHand()
    }
    private func rowLabel(_ icon: String, _ title: String, _ detail: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: trailing).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11).contentShape(Rectangle())
    }

    /// "just now", "2 min ago".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        now.timeIntervalSince(date) < 45 ? "just now" : RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
    }
    /// The plain-words reason under "What happened".
    static func explanation(_ problem: GitHubConnection.Problem) -> String {
        switch problem {
        case .expired: "GitHub says the sign-in has expired or was revoked. This happens if Diorama was removed in your GitHub settings or the login aged out."
        case .unreachable: "The request to GitHub didn't get through. This is usually the network, a VPN or GitHub itself, not your login."
        case .other: "GitHub didn't accept Diorama's request."
        }
    }
}

/// The GitHub mark alone, in the current text colour.
struct GitHubMarkGlyph: View {
    var size: CGFloat
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
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}
