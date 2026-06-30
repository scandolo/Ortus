import Foundation
import Network
import AppKit

@MainActor
final class SlackOAuthService: ObservableObject {
    @Published var isConnected = false
    @Published var teamName: String?
    @Published var isAuthenticating = false
    @Published var error: String?

    private var listener: NWListener?
    private var connection: NWConnection?

    private let userScopes = "users.profile:write,dnd:write"

    /// Fixed loopback port for the OAuth callback. Slack matches redirect URIs exactly
    /// (no wildcards), so a random per-launch port can't be whitelisted. This is the
    /// port the user adds to their Slack app's Redirect URLs config.
    nonisolated static let callbackPort: UInt16 = 53124
    nonisolated static var callbackURL: String { "http://127.0.0.1:\(callbackPort)/callback" }

    /// Non-secret connection state cached in UserDefaults. Reading these on launch
    /// instead of the keychain means the app doesn't trigger a keychain prompt every
    /// time it starts up — the actual token still lives in the keychain and is only
    /// fetched lazily when we need to make a Slack API call.
    private static let isConnectedKey = "ortus.slack.isConnected"
    private static let teamNameKey = "ortus.slack.teamName"

    init() {
        let defaults = UserDefaults.standard
        isConnected = defaults.bool(forKey: Self.isConnectedKey)
        teamName = defaults.string(forKey: Self.teamNameKey)
    }

    /// In-memory caches for the OAuth client credentials. These getters are
    /// called twice during the OAuth flow (and historically on every Settings
    /// open), so reading the keychain each time was firing the password prompt
    /// repeatedly. After the first read per process, subsequent accesses are
    /// served from memory.
    private var cachedClientId: String?
    private var cachedClientSecret: String?

    var clientId: String {
        if let cachedClientId { return cachedClientId }
        let value = KeychainService.load(.slackClientId) ?? ""
        cachedClientId = value
        return value
    }

    var clientSecret: String {
        if let cachedClientSecret { return cachedClientSecret }
        let value = KeychainService.load(.slackClientSecret) ?? ""
        cachedClientSecret = value
        return value
    }

    /// Called when the user re-saves credentials in Settings so the next read
    /// pulls the fresh values from the keychain instead of the stale cache.
    func invalidateCredentialsCache() {
        cachedClientId = nil
        cachedClientSecret = nil
    }

    func startOAuthFlow() {
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            error = "Please set your Slack Client ID and Client Secret in Settings first."
            return
        }

        isAuthenticating = true
        error = nil

        do {
            _ = try startLoopbackServer()
            let redirectURI = Self.callbackURL
            let authURL = "https://slack.com/oauth/v2/authorize?client_id=\(clientId)&user_scope=\(userScopes)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)"

            if let url = URL(string: authURL) {
                NSWorkspace.shared.open(url)
            }
        } catch let err as OAuthError {
            self.error = err.errorDescription
            isAuthenticating = false
        } catch {
            self.error = "Failed to start OAuth server: \(error.localizedDescription)"
            isAuthenticating = false
        }
    }

    func disconnect() {
        KeychainService.delete(.slackToken)
        KeychainService.delete(.slackTeamName)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.isConnectedKey)
        defaults.removeObject(forKey: Self.teamNameKey)
        invalidateCredentialsCache()
        isConnected = false
        teamName = nil
        Analytics.capture("slack_disconnected")
        NotificationCenter.default.post(name: .ortusSlackTokenChanged, object: nil)
    }

    // MARK: - Loopback Server

    private nonisolated func startLoopbackServer() throws -> UInt16 {
        let params = NWParameters.tcp
        guard let port = NWEndpoint.Port(rawValue: Self.callbackPort) else {
            throw OAuthError.portBindFailed
        }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)

        let newListener: NWListener
        do {
            newListener = try NWListener(using: params)
        } catch {
            throw OAuthError.portInUse(Self.callbackPort)
        }

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
              let components = URLComponents(string: String(urlPath)),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            sendResponse(to: connection, html: "<h1>Error</h1><p>No authorization code received.</p>")
            stopServer()
            error = "No authorization code received from Slack."
            isAuthenticating = false
            return
        }

        sendResponse(to: connection, html: "<h1>Connected!</h1><p>You can close this tab and return to Ortus.</p><script>window.close()</script>")

        // Exchange code for token. Must use the same redirect_uri as the authorize step.
        let redirectURI = Self.callbackURL

        stopServer()

        do {
            try await exchangeCodeForToken(code: code, redirectURI: redirectURI)
        } catch {
            self.error = "Token exchange failed: \(error.localizedDescription)"
        }
        isAuthenticating = false
    }

    private func exchangeCodeForToken(code: String, redirectURI: String) async throws {
        var request = URLRequest(url: URL(string: "https://slack.com/api/oauth.v2.access")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SlackOAuthResponse.self, from: data)

        guard response.ok, let authedUser = response.authedUser else {
            throw OAuthError.tokenExchangeFailed(response.error ?? "Unknown error")
        }

        try KeychainService.save(authedUser.accessToken, for: .slackToken)
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.isConnectedKey)
        if let team = response.team {
            try KeychainService.save(team.name, for: .slackTeamName)
            defaults.set(team.name, forKey: Self.teamNameKey)
            teamName = team.name
        }
        isConnected = true
        Analytics.capture("slack_connected")
        NotificationCenter.default.post(name: .ortusSlackTokenChanged, object: nil)
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
        case portInUse(UInt16)
        case tokenExchangeFailed(String)

        var errorDescription: String? {
            switch self {
            case .portBindFailed:
                "Failed to bind loopback server port"
            case .portInUse(let port):
                "Port \(port) is already in use. Quit whatever is using it and try again."
            case .tokenExchangeFailed(let reason):
                "Token exchange failed: \(reason)"
            }
        }
    }
}
