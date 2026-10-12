import AppKit
import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

private final class Tokens: @unchecked Sendable {
    private let lock = NSLock()
    private var token: GitHubToken?
    init(_ token: GitHubToken? = nil) { self.token = token }
    func load() -> GitHubToken? { lock.withLock { token } }
    func save(_ value: GitHubToken) { lock.withLock { token = value } }
    func remove() { lock.withLock { token = nil } }
}

/// A fake GitHub reply.
private func reply(_ request: URLRequest, _ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}

/// The shared GitHub connection: what each kind of failure means for the button and the modal,
/// signing in through the device code, and disconnecting.
@MainActor struct GitHubConnectionTests {
    @Test func checksMapToStates() async {
        // No saved login.
        let none = GitHubConnection(account: GitHubAccount(loadToken: { nil }), hasSavedLogin: { false }, openURL: { _ in })
        await none.refresh()
        #expect(none.state == .notConnected)
        // A good login.
        let good = GitHubConnection(account: GitHubAccount(loadToken: { GitHubToken(accessToken: "t") }, transport: { reply($0, 200, #"{"login":"octo","id":1}"#) }),
                                    hasSavedLogin: { true }, openURL: { _ in })
        await good.refresh()
        #expect(good.login == "octo" && good.identity?.id == 1)
        // Revoked or expired: reconnect.
        let expired = GitHubConnection(account: GitHubAccount(loadToken: { GitHubToken(accessToken: "t") }, transport: { reply($0, 401, "{}") }),
                                       hasSavedLogin: { true }, openURL: { _ in })
        await expired.refresh()
        guard case .needsAttention(.expired) = expired.state else { Issue.record("\(expired.state)"); return }
        // No network: not a reconnect.
        let offline = GitHubConnection(account: GitHubAccount(loadToken: { GitHubToken(accessToken: "t") }, transport: { _ in throw URLError(.notConnectedToInternet) }),
                                       hasSavedLogin: { true }, openURL: { _ in })
        await offline.refresh()
        guard case .needsAttention(.unreachable) = offline.state else { Issue.record("\(offline.state)"); return }
        // A saved login macOS must ask for.
        let locked = GitHubConnection(account: GitHubAccount(loadToken: { nil }), hasSavedLogin: { throw GitHubAuthError.keychainNeedsPermission }, openURL: { _ in })
        await locked.refresh()
        #expect(locked.state == .needsKeychain)
    }

    @Test func signsInThroughTheDeviceCodeThenDisconnects() async throws {
        let tokens = Tokens()
        var opened: [URL] = []
        let account = GitHubAccount(clientID: "test", loadToken: { tokens.load() }, saveToken: { tokens.save($0) }, removeToken: { tokens.remove() }, transport: { request in
            switch request.url?.path {
            case "/login/device/code": return reply(request, 200, #"{"device_code":"d","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":1}"#)
            case "/login/oauth/access_token":
                try await Task.sleep(for: .milliseconds(200))
                return reply(request, 200, #"{"access_token":"fresh"}"#)
            default: return reply(request, 200, #"{"login":"octo","id":7}"#)
            }
        })
        let connection = GitHubConnection(account: account, hasSavedLogin: { tokens.load() != nil }, openURL: { opened.append($0) })
        await connection.refresh()
        #expect(connection.state == .notConnected)
        connection.connect()
        for _ in 0..<50 where { if case .signingIn = connection.state { false } else { true } }() { try await Task.sleep(for: .milliseconds(20)) }
        guard case .signingIn(let code, let url, _) = connection.state else { Issue.record("\(connection.state)"); return }
        #expect(code == "WDJB-MJHT" && url.absoluteString == "https://github.com/login/device" && opened == [url])
        #expect(GitHubSignIn.pending == 1)
        for _ in 0..<200 where connection.login == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(connection.login == "octo" && tokens.load() != nil)
        #expect(GitHubSignIn.pending == 0)
        await connection.disconnect()
        #expect(connection.state == .notConnected && tokens.load() == nil)
    }

    @Test func cancellingASignInGoesBack() async throws {
        let account = GitHubAccount(clientID: "test", loadToken: { nil }, transport: { request in
            if request.url?.path == "/login/device/code" {
                return reply(request, 200, #"{"device_code":"d","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":1}"#)
            }
            return reply(request, 200, #"{"error":"authorization_pending"}"#)
        })
        let connection = GitHubConnection(account: account, hasSavedLogin: { false }, openURL: { _ in })
        connection.connect()
        for _ in 0..<50 where { if case .signingIn = connection.state { false } else { true } }() { try await Task.sleep(for: .milliseconds(20)) }
        connection.cancelSignIn()
        for _ in 0..<100 where connection.state != .notConnected { try await Task.sleep(for: .milliseconds(20)) }
        #expect(connection.state == .notConnected && !connection.signingIn)
    }

    /// Opt-in renders of the home button in every state and each modal screen, light and dark
    /// (DIORAMA_UTILITY_CAPTURE=1; /tmp/diorama-github-*.png).
    @Test func captureGitHubScreens() throws {
        guard ProcessInfo.processInfo.environment["DIORAMA_UTILITY_CAPTURE"] == "1" else { return }
        let connection = GitHubConnection.shared
        let identity = try JSONDecoder().decode(GitHubIdentity.self, from: Data(#"{"login":"davidfromkansas","id":1}"#.utf8))
        let states: [(String, GitHubConnection.State)] = [
            ("not-connected", .notConnected),
            ("signing-in", .signingIn(code: "WDJB-MJHT", verification: URL(string: "https://github.com/login/device")!, expires: Date().addingTimeInterval(872))),
            ("connected", .connected(login: "davidfromkansas", checkedAt: Date())),
            ("attention", .needsAttention(.expired("Your GitHub authorization expired. Reconnect in Settings."))),
            ("offline", .needsAttention(.unreachable("The Internet connection appears to be offline."))),
            ("keychain", .needsKeychain),
        ]
        func render<V: View>(_ view: V, _ name: String, dark: Bool) throws {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
                .background(Color(nsColor: dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1))))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-github-\(name)-\(dark ? "dark" : "light").png"))
        }
        for dark in [true, false] {
            for (name, state) in states {
                connection.show(state, login: name == "connected" ? identity : nil)
                try render(HomeGitHubOrb(open: {}).padding(10), "button-" + name, dark: dark)
                try render(GitHubConnectionModal(), "modal-" + name, dark: dark)
            }
        }
        connection.show(.checking)
    }
}
