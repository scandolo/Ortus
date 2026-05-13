import Foundation

/// Thin Slack client used solely to update the user's profile status and DND
/// during Ortus focus sessions. Read-side queries (search, channel history, etc.)
/// happen through the AI chat's local Claude Code + Slack MCP — not here.
@MainActor
final class SlackService: ObservableObject {
    private let baseURL = "https://slack.com/api/"
    private let session = URLSession.shared

    var token: String? {
        KeychainService.load(.slackToken)
    }

    var isConnected: Bool {
        token != nil
    }

    // MARK: - Status & DND

    /// Sets the user's Slack profile status. Pass an expiration date so Slack auto-clears it.
    func setStatus(text: String, emoji: String, expiration: Date?) async throws {
        var profile: [String: Any] = [
            "status_text": text,
            "status_emoji": emoji,
        ]
        if let expiration {
            profile["status_expiration"] = Int(expiration.timeIntervalSince1970)
        } else {
            profile["status_expiration"] = 0
        }
        let response: SlackBasicResponse = try await apiPost("users.profile.set", body: ["profile": profile])
        guard response.ok else { throw SlackError.apiError(response.error ?? "Unknown") }
    }

    /// Clears the user's Slack profile status.
    func clearStatus() async throws {
        try await setStatus(text: "", emoji: "", expiration: nil)
    }

    /// Snoozes Slack notifications for the given number of minutes (Slack DND).
    func setSnooze(minutes: Int) async throws {
        let response: SlackBasicResponse = try await apiGet("dnd.setSnooze", params: ["num_minutes": String(minutes)])
        guard response.ok else { throw SlackError.apiError(response.error ?? "Unknown") }
    }

    /// Ends the user's current snooze window. Treats "snooze_not_active" as success.
    func endSnooze() async throws {
        let response: SlackBasicResponse = try await apiGet("dnd.endSnooze", params: [:])
        guard response.ok || response.error == "snooze_not_active" else {
            throw SlackError.apiError(response.error ?? "Unknown")
        }
    }

    // MARK: - HTTP Helpers

    private func apiGet<T: Codable>(_ method: String, params: [String: String]) async throws -> T {
        guard let token else { throw SlackError.noToken }

        var components = URLComponents(string: baseURL + method)!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 3
            try await Task.sleep(for: .seconds(retryAfter))
            return try await apiGet(method, params: params)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func apiPost<T: Codable>(_ method: String, body: [String: Any]) async throws -> T {
        guard let token else { throw SlackError.noToken }

        var request = URLRequest(url: URL(string: baseURL + method)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 3
            try await Task.sleep(for: .seconds(retryAfter))
            return try await apiPost(method, body: body)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    enum SlackError: LocalizedError {
        case noToken
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noToken: "Slack isn't connected. Connect it in Settings to enable status updates."
            case .apiError(let msg): "Slack API error: \(msg)"
            }
        }
    }
}
