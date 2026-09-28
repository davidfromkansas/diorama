import Foundation
import Security
import LocalAuthentication

private final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct GitHubAPIError: LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public var errorDescription: String? { message }
}

public struct GitHubToken: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
}
public enum GitHubCredentials {
    private static let service = "local.diorama.github.oauth"
    private static let interactionLock = NSLock()
    public static func loadRecord(allowInteraction: Bool = false) throws -> GitHubToken? {
        // This app currently uses the macOS file-based keychain. Its legacy
        // implementation does not consistently honor LAContext's UI setting.
        interactionLock.lock()
        defer { interactionLock.unlock() }
        var previous: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&previous)
        SecKeychainSetUserInteractionAllowed(allowInteraction)
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        var result: CFTypeRef?
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: "github.com", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed { throw AppServerFailure("macOS requires access to Diorama's saved GitHub login. Use Allow Keychain access in GitHub Settings, then retry.") }
        guard status == errSecSuccess, let data = result as? Data else { throw AppServerFailure("Diorama could not access its GitHub login in Keychain.") }
        return (try? JSONDecoder().decode(GitHubToken.self, from: data)) ?? String(data: data, encoding: .utf8).map { GitHubToken(accessToken: $0) }
    }
    public static func load() throws -> String? { try loadRecord()?.accessToken }
    public static func save(_ token: GitHubToken) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "github.com"] as CFDictionary
        let data = try JSONEncoder().encode(token)
        let update = SecItemUpdate(query, [kSecValueData: data] as CFDictionary)
        if update == errSecItemNotFound {
            var attributes: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                kSecAttrAccount: "github.com", kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            // The bundled credential helper is part of Diorama. Grant only these
            // two signed executables access, never all applications.
            var applications: [SecTrustedApplication] = []
            for path in [Bundle.main.executableURL?.path, Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/DioramaReporter").path].compactMap({ $0 }) where FileManager.default.isExecutableFile(atPath: path) {
                var application: SecTrustedApplication?
                if SecTrustedApplicationCreateFromPath(path, &application) == errSecSuccess, let application { applications.append(application) }
            }
            var access: SecAccess?
            if !applications.isEmpty, SecAccessCreate("Diorama GitHub" as CFString, applications as CFArray, &access) == errSecSuccess, let access { attributes[kSecAttrAccess] = access }
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppServerFailure("Could not save the GitHub login in Keychain.") }
        } else if update != errSecSuccess { throw AppServerFailure("Could not update the GitHub login in Keychain.") }
    }
    public static func remove() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "github.com"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppServerFailure("Could not remove the GitHub login from Keychain.") }
    }
}

public struct GitHubDeviceCode: Decodable, Sendable {
    public let device_code: String
    public let user_code: String
    public let verification_uri: String
    public let expires_in: Int
    public let interval: Int
}
public struct GitHubIdentity: Codable, Sendable, Equatable {
    public let login: String
    public let id: Int
}
public struct GitHubRepo: Codable, Sendable, Identifiable {
    public let id: Int
    public let full_name: String
    public let html_url: String
    public let default_branch: String
    public let `private`: Bool
}

/// Only Diorama-owned credentials are used. No gh login or ambient environment tokens.
public actor GitHubAccount {
    public static let shared = GitHubAccount()
    private var generation = 0
    private let session = URLSession(configuration: .ephemeral, delegate: GitHubRedirectPolicy(), delegateQueue: nil)
    private var gitOperations: [UUID: Task<String, Error>] = [:]
    private var refreshTask: Task<String?, Error>?
    private let configuredClientID: String?
    private let loadToken: @Sendable () throws -> GitHubToken?
    private let saveToken: @Sendable (GitHubToken) throws -> Void
    private let removeToken: @Sendable () throws -> Void
    private let transport: (@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse))?
    public init(clientID: String? = nil,
                loadToken: @escaping @Sendable () throws -> GitHubToken? = { try GitHubCredentials.loadRecord() },
                saveToken: @escaping @Sendable (GitHubToken) throws -> Void = { try GitHubCredentials.save($0) },
                removeToken: @escaping @Sendable () throws -> Void = { try GitHubCredentials.remove() },
                transport: (@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse))? = nil) {
        self.configuredClientID = clientID; self.loadToken = loadToken; self.saveToken = saveToken
        self.removeToken = removeToken; self.transport = transport
    }
    private func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let transport { return try await transport(request) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppServerFailure("GitHub returned an invalid response.") }
        return (data, response)
    }
    public static var clientID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "DioramaGitHubClientID") as? String)
            ?? ProcessInfo.processInfo.environment["DIORAMA_GITHUB_CLIENT_ID"]
        return value?.isEmpty == false ? value : nil
    }
    public func disconnect() throws {
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        for task in gitOperations.values { task.cancel() }
        try removeToken()
    }
    public func performGit(_ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        let expected = generation
        let id = UUID(); let task = Task { try await operation() }
        gitOperations[id] = task
        defer { gitOperations[id] = nil }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            guard expected == generation else { throw AppServerFailure("GitHub disconnected. Check the remote before retrying this operation.") }
            return result
        } onCancel: { task.cancel() }
    }
    public func identity() async throws -> GitHubIdentity {
        try JSONDecoder().decode(GitHubIdentity.self, from: await api("/user"))
    }
    public func startLogin() async throws -> GitHubDeviceCode {
        guard let client = configuredClientID ?? Self.clientID else { throw AppServerFailure("GitHub sign-in is not configured in this build. A Diorama OAuth client ID is required.") }
        generation += 1
        return try JSONDecoder().decode(GitHubDeviceCode.self, from: await publicRequest("https://github.com/login/device/code", body: ["client_id": client, "scope": "repo read:org workflow"]))
    }
    public func finishLogin(_ code: GitHubDeviceCode) async throws -> GitHubIdentity {
        guard let client = configuredClientID ?? Self.clientID else { throw AppServerFailure("GitHub sign-in is not configured.") }
        let expected = generation
        let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
        var interval = max(1, code.interval)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            guard expected == generation else { throw CancellationError() }
            let data = try await publicRequest("https://github.com/login/oauth/access_token", body: ["client_id": client, "device_code": code.device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            let value = try JSONDecoder().decode(WireValue.self, from: data)
            guard expected == generation else { throw CancellationError() }
            if let token = value["access_token"].string {
                try saveToken(Self.token(value, accessToken: token))
                return try await identity()
            }
            switch value["error"].string {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw AppServerFailure("GitHub sign-in was cancelled.")
            case "expired_token": throw AppServerFailure("The sign-in code expired. Connect again.")
            default: throw AppServerFailure("GitHub could not complete sign-in. Connect again.")
            }
        }
        throw AppServerFailure("The sign-in code expired. Connect again.")
    }
    private func publicRequest(_ url: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await self.request(request)
        guard response.statusCode == 200 else { throw AppServerFailure("GitHub sign-in is unavailable. Check your connection and retry.") }
        return data
    }
    private static func token(_ value: WireValue, accessToken: String) -> GitHubToken {
        GitHubToken(accessToken: accessToken, refreshToken: value["refresh_token"].string,
            expiresAt: value["expires_in"].number.map { Date().addingTimeInterval(TimeInterval($0)) })
    }
    public func accessToken() async throws -> String? {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.loadOrRefreshToken() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    private func loadOrRefreshToken() async throws -> String? {
        guard let stored = try loadToken() else { return nil }
        if let expiry = stored.expiresAt, expiry < Date().addingTimeInterval(60) {
            guard let refresh = stored.refreshToken, let client = configuredClientID ?? Self.clientID else { throw AppServerFailure("Reconnect GitHub in Settings.") }
            let expected = generation
            let data = try await publicRequest("https://github.com/login/oauth/access_token", body: ["client_id": client, "refresh_token": refresh, "grant_type": "refresh_token"])
            let value = try JSONDecoder().decode(WireValue.self, from: data)
            guard expected == generation else { throw CancellationError() }
            guard let token = value["access_token"].string else { throw AppServerFailure("Your GitHub login expired. Reconnect in Settings.") }
            try saveToken(Self.token(value, accessToken: token))
            return token
        }
        return stored.accessToken
    }
    public func api(_ path: String, method: String = "GET", body: WireValue? = nil) async throws -> Data {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), let url = URL(string: "https://api.github.com" + path), url.host == "api.github.com" else { throw AppServerFailure("Invalid GitHub destination.") }
        guard let token = try await accessToken() else { throw AppServerFailure("Connect GitHub in Settings to continue.") }
        let expected = generation
        var request = URLRequest(url: url); request.timeoutInterval = 30; request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await self.request(request)
        guard expected == generation else { throw AppServerFailure("GitHub disconnected. The operation may have completed; reconnect and check before retrying.") }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw AppServerFailure("Your GitHub authorization expired. Reconnect in Settings.")
        case 403 where response.value(forHTTPHeaderField: "X-GitHub-SSO") != nil: throw AppServerFailure("Your organization requires GitHub authorization approval.")
        case 429: throw AppServerFailure("GitHub is rate limiting requests. Try again later.")
        case 403 where response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0": throw AppServerFailure("GitHub's rate limit was reached. Try again later.")
        case 403: throw AppServerFailure("This GitHub account does not have permission for this operation.")
        case 404: throw GitHubAPIError(status: 404, message: "The GitHub repository or branch is unavailable, or this account cannot access it.")
        case 422: throw AppServerFailure("GitHub rejected this request. Check for an existing repository or PR, and verify the selected branches.")
        default: throw AppServerFailure("GitHub operation failed (HTTP \(response.statusCode)). Check its outcome before retrying.")
        }
    }
    public func repositories(page: Int = 1) async throws -> [GitHubRepo] {
        try JSONDecoder().decode([GitHubRepo].self, from: await api("/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member&page=\(max(1, page))"))
    }
    public func repository(_ name: String) async throws -> GitHubRepo {
        let repo = try Self.validRepository(name)
        return try JSONDecoder().decode(GitHubRepo.self, from: await api("/repos/" + repo))
    }
    public static func validRepository(_ value: String) throws -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { throw AppServerFailure("Choose a GitHub owner/repository.") }
        return value
    }
}
