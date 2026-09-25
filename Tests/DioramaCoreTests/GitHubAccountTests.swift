import Foundation
import Testing
@testable import DioramaCore

private final class TestGitHubTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var token: GitHubToken?
    init(_ token: GitHubToken? = nil) { self.token = token }
    func load() -> GitHubToken? { lock.withLock { token } }
    func save(_ value: GitHubToken) { lock.withLock { token = value } }
    func remove() { lock.withLock { token = nil } }
}
private actor GitHubRequestCount { var count = 0; func increment() { count += 1 } }
struct GitHubAccountTests {
    @Test func loginSavesOnlyDioramaTokenAndDisconnectRemovesIt() async throws {
        let tokens = TestGitHubTokens()
        let account = GitHubAccount(clientID: "test-client", loadToken: { tokens.load() }, saveToken: { tokens.save($0) }, removeToken: { tokens.remove() }, transport: { request in
            let response: String
            if request.url?.path == "/login/device/code" { response = #"{"device_code":"device","user_code":"CODE","verification_uri":"https://github.com/login/device","expires_in":60,"interval":1}"# }
            else if request.url?.path == "/login/oauth/access_token" { response = #"{"access_token":"fake-test-token"}"# }
            else {
                #expect(request.url?.host == "api.github.com")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-token")
                response = #"{"login":"fixture","id":42}"#
            }
            return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let code = try await account.startLogin()
        let identity = try await account.finishLogin(code)
        #expect(identity.login == "fixture")
        #expect(tokens.load() != nil)
        try await account.disconnect()
        #expect(tokens.load() == nil)
        await #expect(throws: (any Error).self) { try await account.identity() }
    }
    @Test(arguments: [401, 403, 404, 429, 422, 503]) func apiFailuresAreRecoverable(_ status: Int) async throws {
        let account = GitHubAccount(loadToken: { GitHubToken(accessToken: "fake") }, transport: { request in
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        await #expect(throws: (any Error).self) { try await account.identity() }
    }
    @Test func denialExpirationAndCancellationDoNotSaveTokens() async throws {
        let tokens = TestGitHubTokens()
        let account = GitHubAccount(clientID: "test-client", loadToken: { tokens.load() }, saveToken: { tokens.save($0) }, transport: { request in
            (Data(#"{"error":"access_denied"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let code = GitHubDeviceCode(device_code: "device", user_code: "CODE", verification_uri: "https://github.com/login/device", expires_in: 30, interval: 1)
        await #expect(throws: (any Error).self) { try await account.finishLogin(code) }
        let expired = GitHubDeviceCode(device_code: "device", user_code: "CODE", verification_uri: "https://github.com/login/device", expires_in: 0, interval: 1)
        await #expect(throws: (any Error).self) { try await account.finishLogin(expired) }
        let task = Task { try await account.finishLogin(code) }; task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(tokens.load() == nil)
    }
    @Test func refreshIsSharedAcrossConcurrentRequests() async throws {
        let tokens = TestGitHubTokens(GitHubToken(accessToken: "expired", refreshToken: "fake-refresh", expiresAt: .distantPast))
        let calls = GitHubRequestCount()
        let account = GitHubAccount(clientID: "test-client", loadToken: { tokens.load() }, saveToken: { tokens.save($0) }, transport: { request in
            await calls.increment()
            try await Task.sleep(for: .milliseconds(50))
            return (Data(#"{"access_token":"renewed","refresh_token":"replacement","expires_in":3600}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        async let first = account.accessToken()
        async let second = account.accessToken()
        let results = try await (first, second)
        #expect(results.0 == "renewed" && results.1 == "renewed")
        #expect(await calls.count == 1)
        #expect(tokens.load()?.refreshToken == "replacement")
    }
    @Test func disconnectDuringResponseDoesNotReportSuccess() async throws {
        let tokens = TestGitHubTokens(GitHubToken(accessToken: "fake"))
        let calls = GitHubRequestCount()
        let account = GitHubAccount(loadToken: { tokens.load() }, removeToken: { tokens.remove() }, transport: { request in
            await calls.increment()
            try await Task.sleep(for: .milliseconds(100))
            return (Data(#"{"login":"fixture","id":42}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let task = Task { try await account.identity() }
        while await calls.count == 0 { await Task.yield() }
        try await account.disconnect()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(tokens.load() == nil)
    }
}
