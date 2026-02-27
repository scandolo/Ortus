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

    private let userScopes = "search:read,channels:history,groups:history,im:history,mpim:history,users:read,channels:read,groups:read"

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
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            error = "Please set your Slack Client ID and Client Secret in Settings first."
            return
        }

        isAuthenticating = true
        error = nil

        do {
            let port = try startLoopbackServer()
            let redirectURI = "http://127.0.0.1:\(port)/callback"
            let authURL = "https://slack.com/oauth/v2/authorize?client_id=\(clientId)&user_scope=\(userScopes)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)"

            if let url = URL(string: authURL) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            self.error = "Failed to start OAuth server: \(error.localizedDescription)"
            isAuthenticating = false
        }
    }

    func disconnect() {
        KeychainService.delete(.slackToken)
        KeychainService.delete(.slackTeamName)
        isConnected = false
        teamName = nil
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
              let components = URLComponents(string: String(urlPath)),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
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
        if let team = response.team {
            try KeychainService.save(team.name, for: .slackTeamName)
            teamName = team.name
        }
        isConnected = true
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
