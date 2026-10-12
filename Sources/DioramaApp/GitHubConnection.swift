import AppKit
import DioramaCore
import Observation

/// Diorama's GitHub connection, one for the app: what the home button, the GitHub modal, the
/// settings row and the setup and project sheets all show, and the one place that signs in,
/// checks and disconnects (through `GitHubAccount`).
@Observable @MainActor final class GitHubConnection {
    static let shared = GitHubConnection()

    enum Problem: Equatable {
        /// GitHub rejected the login: expired, revoked, or no longer refreshable.
        case expired(String)
        /// GitHub couldn't be reached; the login itself may be fine.
        case unreachable(String)
        case other(String)
        var message: String {
            switch self { case .expired(let m), .unreachable(let m), .other(let m): m }
        }
    }
    enum State: Equatable {
        case checking
        case notConnected
        /// Waiting for the code to be entered on GitHub.
        case signingIn(code: String, verification: URL, expires: Date)
        case connected(login: String, checkedAt: Date)
        case needsAttention(Problem)
        /// A saved login exists, but macOS must ask before this build can read it.
        case needsKeychain
    }

    private(set) var state: State = .checking
    /// The development demo shows a made-up account as signed in, without the keychain or GitHub.
    func showConnectedForDemo(login: String) { state = .connected(login: login, checkedAt: Date()) }
    /// Re-checking an established state (the button keeps showing it meanwhile).
    private(set) var checking = false
    /// Why the last sign-in didn't finish (cancelled on GitHub, the code expired), for the Connect screen.
    private(set) var signInError: String?
    var login: String? { if case .connected(let login, _) = state { login } else { nil } }
    /// Who's connected, while connected.
    private(set) var identity: GitHubIdentity?

    private let account: GitHubAccount
    private let hasSavedLogin: @Sendable () throws -> Bool
    private let askKeychain: @Sendable () -> Void
    private let openURL: (URL) -> Void
    private var signIn: Task<Void, Never>?

    init(account: GitHubAccount = .shared,
         hasSavedLogin: @escaping @Sendable () throws -> Bool = { try GitHubCredentials.loadRecord() != nil },
         askKeychain: @escaping @Sendable () -> Void = { _ = try? GitHubCredentials.loadRecord(allowInteraction: true) },
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.account = account; self.hasSavedLogin = hasSavedLogin; self.askKeychain = askKeychain; self.openURL = openURL
    }

    /// Checks the saved login with GitHub. A sign-in in progress is left alone.
    func refresh() async {
        if case .signingIn = state { return }
        guard !checking else { return }
        checking = true; defer { checking = false }
        let hasSavedLogin = self.hasSavedLogin
        do {
            guard try await Task.detached(operation: { try hasSavedLogin() }).value else { state = .notConnected; return }
            let identity = try await account.identity()
            if case .signingIn = state { return }
            self.identity = identity
            state = .connected(login: identity.login, checkedAt: Date())
        } catch is CancellationError {
        } catch {
            if case .signingIn = state { return }
            identity = nil
            state = Self.state(for: error)
        }
    }
    /// What a failed check means for the connection.
    static func state(for error: Error) -> State {
        switch error {
        case GitHubAuthError.notConnected: .notConnected
        case GitHubAuthError.keychainNeedsPermission: .needsKeychain
        case GitHubAuthError.expired(let message): .needsAttention(.expired(message))
        case let error as URLError: .needsAttention(.unreachable(error.localizedDescription))
        default: .needsAttention(.other(error.localizedDescription))
        }
    }

    /// Starts a device-code sign-in: shows the code, opens GitHub, and connects once it's approved.
    /// Also how Switch account and Reconnect work. It keeps going if the modal closes.
    func connect() {
        guard signIn == nil else { return }
        signInError = nil
        GitHubSignIn.pending += 1
        signIn = Task {
            defer { signIn = nil; GitHubSignIn.pending -= 1 }
            do {
                let code = try await account.startLogin()
                let url = URL(string: code.verification_uri) ?? URL(string: "https://github.com/login/device")!
                state = .signingIn(code: code.user_code, verification: url, expires: Date().addingTimeInterval(TimeInterval(code.expires_in)))
                openURL(url)
                let identity = try await account.finishLogin(code)
                self.identity = identity
                state = .connected(login: identity.login, checkedAt: Date())
            } catch is CancellationError {
                state = .checking
                signIn = nil
                await refresh()
            } catch {
                signInError = error.localizedDescription
                state = .checking
                signIn = nil
                await refresh()
            }
        }
    }
    /// Stops waiting for GitHub; the connection goes back to what it was.
    func cancelSignIn() { signIn?.cancel() }
    var signingIn: Bool { signIn != nil }

    /// Opens the GitHub page where the sign-in code goes.
    func openVerification() {
        if case .signingIn(_, let url, _) = state { openURL(url) }
    }

    /// Signs Diorama out of GitHub on this Mac.
    func disconnect() async {
        signIn?.cancel()
        do {
            try await account.disconnect()
            identity = nil; state = .notConnected; signInError = nil
        } catch {
            state = .needsAttention(.other(error.localizedDescription))
        }
    }

    /// Shows a state as it is, for previews and captures of the GitHub screens.
    func show(_ state: State, login identity: GitHubIdentity? = nil) { self.state = state; self.identity = identity }

    /// Lets macOS ask for the saved login, then checks it.
    func allowKeychainAccess() async {
        let ask = askKeychain
        await Task.detached { ask() }.value
        state = .checking
        await refresh()
    }
}
