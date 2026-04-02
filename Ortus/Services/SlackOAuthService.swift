import Foundation
import Network
import AppKit
import CryptoKit

@MainActor
final class SlackOAuthService: ObservableObject {
    @Published var isConnected = false
    @Published var teamName: String?
    @Published var isAuthenticating = false
    @Published var error: String?

    private var listener: NWListener?
    private var connection: NWConnection?
    private let appConfiguration = SlackAppConfiguration.shared
    private var pendingOAuthState: String?
    private var pendingCodeVerifier: String?

    var hasBundledInstallFlow: Bool {
        appConfiguration.hasBundledInstallFlow
    }

    init() {
        // Check if we already have a token
        if KeychainService.load(.slackToken) != nil {
            isConnected = true
            teamName = KeychainService.load(.slackTeamName)
        }
    }

    var clientId: String {
        KeychainService.load(.slackClientId) ?? ""
    }

    var clientSecret: String {
        KeychainService.load(.slackClientSecret) ?? ""
    }

    func startOAuthFlow() {
        error = nil

        if hasBundledInstallFlow {
            startBundledOAuthFlow()
            return
        }

        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            error = "Please set your Slack Client ID and Client Secret in Settings first."
            return
        }

        startLegacyOAuthFlow()
    }

    func handleOAuthCallback(url: URL) {
        guard hasBundledInstallFlow else { return }
        guard url.scheme?.caseInsensitiveCompare(appConfiguration.callbackScheme) == .orderedSame else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        if let oauthError = queryItems.first(where: { $0.name == "error" })?.value {
            error = "Slack authorization failed: \(oauthError)"
            isAuthenticating = false
            clearPendingOAuthState()
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            error = "No authorization code received from Slack."
            isAuthenticating = false
            clearPendingOAuthState()
            return
        }

        guard let state = queryItems.first(where: { $0.name == "state" })?.value,
              state == pendingOAuthState else {
            error = "Slack authorization state did not match the request."
            isAuthenticating = false
            clearPendingOAuthState()
            return
        }

        isAuthenticating = true
        Task {
            do {
                try await exchangeBundledCodeForToken(code: code)
            } catch {
                self.error = "Token exchange failed: \(error.localizedDescription)"
            }
            self.isAuthenticating = false
        }
    }

    func disconnect() {
        KeychainService.delete(.slackToken)
        KeychainService.delete(.slackTeamName)
        isConnected = false
        teamName = nil
        clearPendingOAuthState()
        stopServer()
    }

    private func startLegacyOAuthFlow() {
        isAuthenticating = true

        do {
            let port = try startLoopbackServer()
            let redirectURI = "http://127.0.0.1:\(port)/callback"
            let authURL = "https://slack.com/oauth/v2/authorize?client_id=\(clientId)&user_scope=\(appConfiguration.userScopesString)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)"

            if let url = URL(string: authURL) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            self.error = "Failed to start OAuth server: \(error.localizedDescription)"
            isAuthenticating = false
        }
    }

    private func startBundledOAuthFlow() {
        let state = randomURLSafeString(byteCount: 24)
        let verifier = randomURLSafeString(byteCount: 48)
        let challenge = codeChallenge(for: verifier)

        pendingOAuthState = state
        pendingCodeVerifier = verifier
        isAuthenticating = true

        let redirectURI = appConfiguration.bundledRedirectURL
        let authURL = "https://slack.com/oauth/v2/authorize?client_id=\(appConfiguration.bundledClientID)&user_scope=\(appConfiguration.userScopesString)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&state=\(state)&code_challenge_method=S256&code_challenge=\(challenge)"

        if let url = URL(string: authURL) {
            NSWorkspace.shared.open(url)
        } else {
            error = "Failed to create Slack authorization URL."
            isAuthenticating = false
            clearPendingOAuthState()
        }
    }

    // MARK: - Loopback Server

    private nonisolated func startLoopbackServer() throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

        let newListener = try NWListener(using: params)

        let portBox = PortBox()

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = newListener.port?.rawValue {
                    portBox.port = port
                }
            case .failed(let error):
                Task { @MainActor [weak self] in
                    self?.error = "Server failed: \(error.localizedDescription)"
                    self?.isAuthenticating = false
                }
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.handleConnection(connection)
            }
        }

        newListener.start(queue: .main)

        // Wait briefly for the port to be assigned
        let deadline = Date().addingTimeInterval(2)
        while portBox.port == 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        let resolvedPort = portBox.port
        guard resolvedPort != 0 else {
            throw OAuthError.portBindFailed
        }

        Task { @MainActor [weak self] in
            self?.listener = newListener
        }

        return resolvedPort
    }

    private func handleConnection(_ connection: NWConnection) {
        self.connection = connection
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                await self?.processCallback(request: request, connection: connection)
            }
        }
    }

    private func processCallback(request: String, connection: NWConnection) async {
        // Parse the authorization code from the HTTP request
        guard let codeLine = request.split(separator: "\r\n").first,
              let urlPath = codeLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(urlPath)) else {
            sendResponse(to: connection, html: "<h1>Error</h1><p>No authorization code received.</p>")
            stopServer()
            error = "No authorization code received from Slack."
            isAuthenticating = false
            return
        }

        if let oauthError = components.queryItems?.first(where: { $0.name == "error" })?.value {
            sendResponse(to: connection, html: "<h1>Authorization cancelled</h1><p>You can close this tab and return to Ortus.</p>")
            stopServer()
            error = "Slack authorization failed: \(oauthError)"
            isAuthenticating = false
            return
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            sendResponse(to: connection, html: "<h1>Error</h1><p>No authorization code received.</p>")
            stopServer()
            error = "No authorization code received from Slack."
            isAuthenticating = false
            return
        }

        sendResponse(to: connection, html: "<h1>Connected!</h1><p>You can close this tab and return to Ortus.</p><script>window.close()</script>")

        // Exchange code for token
        let port = listener?.port?.rawValue ?? 0
        let redirectURI = "http://127.0.0.1:\(port)/callback"

        stopServer()

        do {
            try await exchangeLegacyCodeForToken(code: code, redirectURI: redirectURI)
        } catch {
            self.error = "Token exchange failed: \(error.localizedDescription)"
        }
        isAuthenticating = false
    }

    private func exchangeLegacyCodeForToken(code: String, redirectURI: String) async throws {
        var request = URLRequest(url: URL(string: "https://slack.com/api/oauth.v2.access")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthorizationHeader(), forHTTPHeaderField: "Authorization")

        request.httpBody = formBody([
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectURI,
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SlackOAuthResponse.self, from: data)

        guard response.ok else {
            throw OAuthError.tokenExchangeFailed(response.error ?? "Unknown error")
        }

        try await finishOAuthConnection(response: response)
    }

    private func exchangeBundledCodeForToken(code: String) async throws {
        guard let codeVerifier = pendingCodeVerifier else {
            throw OAuthError.tokenExchangeFailed("Missing PKCE verifier")
        }

        var request = URLRequest(url: URL(string: "https://slack.com/api/oauth.v2.user.access")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": appConfiguration.bundledClientID,
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": appConfiguration.bundledRedirectURL,
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SlackOAuthResponse.self, from: data)

        guard response.ok else {
            throw OAuthError.tokenExchangeFailed(response.error ?? "Unknown error")
        }

        try await finishOAuthConnection(response: response)
    }

    private func finishOAuthConnection(response: SlackOAuthResponse) async throws {
        guard let accessToken = response.resolvedAccessToken else {
            throw OAuthError.tokenExchangeFailed("No access token returned")
        }

        try KeychainService.save(accessToken, for: .slackToken)

        if let returnedTeamName = response.team?.name, !returnedTeamName.isEmpty {
            try KeychainService.save(returnedTeamName, for: .slackTeamName)
            teamName = returnedTeamName
        } else if let fetchedTeamName = try await fetchTeamName(accessToken: accessToken) {
            try KeychainService.save(fetchedTeamName, for: .slackTeamName)
            teamName = fetchedTeamName
        } else {
            KeychainService.delete(.slackTeamName)
            teamName = nil
        }

        isConnected = true
        clearPendingOAuthState()
    }

    private func fetchTeamName(accessToken: String) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://slack.com/api/auth.test")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SlackAuthTestResponse.self, from: data)

        guard response.ok else {
            throw OAuthError.tokenExchangeFailed(response.error ?? "Auth test failed")
        }

        return response.team
    }

    private func formBody(_ params: [String: String]) -> Data {
        let encoded = params.map { key, value in
            "\(key)=\(urlEncode(value))"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    private func basicAuthorizationHeader() -> String {
        let credentials = "\(clientId):\(clientSecret)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func urlEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func randomURLSafeString(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func clearPendingOAuthState() {
        pendingOAuthState = nil
        pendingCodeVerifier = nil
    }

    private func sendResponse(to connection: NWConnection, html: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func stopServer() {
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
    }

    private class PortBox: @unchecked Sendable {
        var port: UInt16 = 0
    }

    enum OAuthError: LocalizedError {
        case portBindFailed
        case tokenExchangeFailed(String)

        var errorDescription: String? {
            switch self {
            case .portBindFailed:
                "Failed to bind loopback server port"
            case .tokenExchangeFailed(let reason):
                "Token exchange failed: \(reason)"
            }
        }
    }
}
