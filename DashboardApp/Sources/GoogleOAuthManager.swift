#if canImport(AppKit)
import AppKit
#endif
import CryptoKit
#if canImport(DashboardCore)
import DashboardCore
#endif
import Foundation
import Network
import Security

actor GoogleOAuthManager {
    static let shared = GoogleOAuthManager()

    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let keychainService = "me.wanshenl.KapiBoard.google"
    private let keychainAccount = "oauth-token"
    private let requiredScopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    var isConfigured: Bool {
        clientID != nil
    }

    var hasStoredToken: Bool {
        loadToken().map(hasRequiredScopes) ?? false
    }

    func validAccessToken() async -> String? {
        guard let token = loadToken() else {
            return nil
        }

        guard hasRequiredScopes(token) else {
            return nil
        }

        if token.expiryDate > Date().addingTimeInterval(60) {
            return token.accessToken
        }

        guard !token.refreshToken.isEmpty else {
            return nil
        }

        return try? await refreshAccessToken(token)
    }

    func authorize() async throws {
        Self.debugLog("authorize started")
        guard let clientID else {
            Self.debugLog("authorize failed: missing client id")
            throw GoogleOAuthError.missingClientID
        }

        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.pkceChallenge(for: verifier)
        let state = Self.randomBase64URL(byteCount: 16)
        let receiver = try OAuthLoopbackReceiver(expectedState: state)
        let redirectURI = try receiver.start()
        Self.debugLog("receiver started redirectURI=\(redirectURI)")

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: requiredScopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authorizationURL = components?.url else {
            throw URLError(.badURL)
        }

#if canImport(AppKit)
        await MainActor.run {
            _ = NSWorkspace.shared.open(authorizationURL)
        }
#endif

        Self.debugLog("waiting for oauth callback")
        let code = try await receiver.waitForCode()
        Self.debugLog("received oauth callback codeLength=\(code.count)")
        let token = try await exchangeAuthorizationCode(code, redirectURI: redirectURI, verifier: verifier)
        Self.debugLog("exchanged token expires=\(token.expiryDate) hasRefresh=\(!token.refreshToken.isEmpty) scopes=\(token.scope ?? "")")
        try saveToken(token)
        Self.debugLog("saved token")
        guard loadToken().map(hasRequiredScopes) == true else {
            Self.debugLog("token readback failed or scopes missing")
            throw GoogleOAuthError.tokenPersistenceFailed
        }
        Self.debugLog("token readback succeeded")
    }

    func signOut() throws {
        try deleteToken()
    }

    private var clientID: String? {
        let defaultsValue = UserDefaults.standard.string(forKey: "googleClientID")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let defaultsValue, !defaultsValue.isEmpty {
            Self.debugLog("google client id loaded source=defaults")
            return defaultsValue
        }

        if let configValue = Self.localConfig()?.googleClientID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configValue.isEmpty {
            Self.debugLog("google client id loaded source=local-config")
            return configValue
        }

        let environmentValue = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            Self.debugLog("google client id loaded source=environment")
            return environmentValue
        }

        return nil
    }

    private var clientSecret: String? {
        let defaultsValue = UserDefaults.standard.string(forKey: "googleClientSecret")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let defaultsValue, !defaultsValue.isEmpty {
            Self.debugLog("google client secret loaded source=defaults")
            return defaultsValue
        }

        if let configValue = Self.localConfig()?.googleClientSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configValue.isEmpty {
            Self.debugLog("google client secret loaded source=local-config")
            return configValue
        }

        let environmentValue = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            Self.debugLog("google client secret loaded source=environment")
            return environmentValue
        }

        return nil
    }

    private func exchangeAuthorizationCode(_ code: String, redirectURI: String, verifier: String) async throws -> GoogleOAuthToken {
        var fields = [
            "client_id": clientID ?? "",
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        if let clientSecret {
            fields["client_secret"] = clientSecret
        }

        let response = try await tokenRequest(fields)

        return GoogleOAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? "",
            expiryDate: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            scope: response.scope,
            tokenType: response.tokenType
        )
    }

    private func refreshAccessToken(_ token: GoogleOAuthToken) async throws -> String {
        var fields = [
            "client_id": clientID ?? "",
            "refresh_token": token.refreshToken,
            "grant_type": "refresh_token"
        ]
        if let clientSecret {
            fields["client_secret"] = clientSecret
        }

        let response = try await tokenRequest(fields)

        let refreshedToken = GoogleOAuthToken(
            accessToken: response.accessToken,
            refreshToken: token.refreshToken,
            expiryDate: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            scope: response.scope ?? token.scope,
            tokenType: response.tokenType
        )
        try saveToken(refreshedToken)
        return refreshedToken.accessToken
    }

    private func hasRequiredScopes(_ token: GoogleOAuthToken) -> Bool {
        let grantedScopes = Set((token.scope ?? "").split(separator: " ").map(String.init))
        return requiredScopes.allSatisfy { grantedScopes.contains($0) }
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { key, value in "\(Self.formEncode(key))=\(Self.formEncode(value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            let message = Self.googleErrorSummary(from: body)
            Self.debugLog("token request failed status=\(httpResponse.statusCode) message=\(message)")
            throw GoogleOAuthError.tokenRequestFailed(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        } catch {
            Self.debugLog("token response decode failed error=\(error.localizedDescription) bytes=\(data.count)")
            throw error
        }
    }

    private func loadToken() -> GoogleOAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(GoogleOAuthToken.self, from: data)
    }

    private func saveToken(_ token: GoogleOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        Self.debugLog("keychain update status=\(status)")
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            Self.debugLog("keychain add status=\(addStatus)")
            guard addStatus == errSecSuccess else {
                throw GoogleOAuthError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw GoogleOAuthError.keychain(status)
        }
    }

    private func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleOAuthError.keychain(status)
        }
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func localConfig() -> GoogleOAuthLocalConfig? {
        let configuredPath = ProcessInfo.processInfo.environment["KAPIBOARD_GOOGLE_CONFIG"]
        let homeConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kapiboard")
            .appendingPathComponent("google.json")
            .path
        let repoConfig = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Config")
            .appendingPathComponent("google.local.json")
            .path

        for path in [configuredPath, homeConfig, repoConfig].compactMap({ $0 }) {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let config = try? JSONDecoder().decode(GoogleOAuthLocalConfig.self, from: data) else {
                continue
            }
            return config
        }

        return nil
    }

    private static func googleErrorSummary(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let response = try? JSONDecoder().decode(GoogleTokenErrorResponse.self, from: data) else {
            return body.isEmpty ? "No response body." : "OAuth endpoint returned an unparseable error body."
        }

        if let description = response.errorDescription, !description.isEmpty {
            return "\(response.error): \(description)"
        }
        return response.error
    }

    fileprivate static func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["KAPIBOARD_GOOGLE_DEBUG"] == "1" else {
            return
        }

        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library")
            .appendingPathComponent("Group Containers")
            .appendingPathComponent("group.me.wanshenl.KapiBoard")
            .appendingPathComponent("google-oauth-debug.log")

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else {
            return
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

final class OAuthLoopbackReceiver: @unchecked Sendable {
    private let expectedState: String
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?
    private var didFinish = false

    init(expectedState: String) throws {
        self.expectedState = expectedState
    }

    func start() throws -> String {
        let port = try Self.availablePort()
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port) ?? .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            GoogleOAuthManager.debugLog("loopback received connection")
            self?.handle(connection)
        }
        listener.start(queue: .main)

        return "http://127.0.0.1:\(port)/oauth2redirect"
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            if let pendingResult {
                self.pendingResult = nil
                continuation.resume(with: pendingResult)
                return
            }
            self.continuation = continuation
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                GoogleOAuthManager.debugLog("loopback failed: unreadable request")
                self?.finish(connection: connection, result: .failure(GoogleOAuthError.loopbackFailed))
                return
            }

            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2,
                  let url = URL(string: "http://127.0.0.1\(parts[1])"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                GoogleOAuthManager.debugLog("loopback failed: invalid request line")
                self.finish(connection: connection, result: .failure(GoogleOAuthError.loopbackFailed))
                return
            }

            let queryItems = components.queryItems ?? []
            let state = queryItems.first { $0.name == "state" }?.value
            let code = queryItems.first { $0.name == "code" }?.value

            guard state == self.expectedState, let code else {
                GoogleOAuthManager.debugLog("loopback failed: invalid state or missing code")
                self.finish(connection: connection, result: .failure(GoogleOAuthError.invalidState))
                return
            }

            GoogleOAuthManager.debugLog("loopback parsed codeLength=\(code.count)")
            self.finish(connection: connection, result: .success(code))
        }
    }

    private func finish(connection: NWConnection, result: Result<String, Error>) {
        guard !didFinish else {
            connection.cancel()
            return
        }
        didFinish = true

        let body = "<html><body><h3>KapiBoard connected. You can close this window.</h3></body></html>"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
        listener?.cancel()
        listener = nil

        if let continuation {
            continuation.resume(with: result)
        } else {
            pendingResult = result
        }
        continuation = nil
    }

    private static func availablePort() throws -> UInt16 {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFileDescriptor >= 0 else {
            throw GoogleOAuthError.loopbackFailed
        }
        defer {
            close(socketFileDescriptor)
        }

        var value: Int32 = 1
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(socketFileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            throw GoogleOAuthError.loopbackFailed
        }

        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(socketFileDescriptor, socketAddress, &boundAddressLength)
            }
        }
        guard nameStatus == 0 else {
            throw GoogleOAuthError.loopbackFailed
        }

        return UInt16(bigEndian: boundAddress.sin_port)
    }
}

private struct GoogleOAuthToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiryDate: Date
    var scope: String?
    var tokenType: String
}

private struct GoogleTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int
    var refreshToken: String?
    var scope: String?
    var tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

private struct GoogleTokenErrorResponse: Decodable {
    var error: String
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct GoogleOAuthLocalConfig: Decodable {
    var googleClientID: String?
    var googleClientSecret: String?
}

enum GoogleOAuthError: LocalizedError {
    case missingClientID
    case missingRefreshToken
    case tokenRequestFailed(Int, String)
    case keychain(OSStatus)
    case tokenPersistenceFailed
    case loopbackFailed
    case invalidState

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Missing GOOGLE_CLIENT_ID. Create a Google OAuth Desktop client and relaunch with GOOGLE_CLIENT_ID set."
        case .missingRefreshToken:
            "Google did not return a refresh token. Reconnect Google Calendar."
        case let .tokenRequestFailed(status, body):
            "Google token request failed with HTTP \(status): \(body)"
        case let .keychain(status):
            "Keychain operation failed with status \(status)."
        case .tokenPersistenceFailed:
            "Google connected in the browser, but KapiBoard could not read the saved token from Keychain."
        case .loopbackFailed:
            "OAuth loopback receiver failed."
        case .invalidState:
            "OAuth state check failed."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
