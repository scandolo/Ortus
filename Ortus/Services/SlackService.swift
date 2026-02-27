import Foundation

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

    // MARK: - Search

    func searchMessages(query: String, count: Int = 20) async throws -> [SlackSearchMatch] {
        let params = ["query": query, "count": String(count), "sort": "timestamp", "sort_dir": "desc"]
        let response: SlackSearchResponse = try await apiCall("search.messages", params: params)
        guard response.ok else { throw SlackError.apiError(response.error ?? "Unknown") }
        return response.messages?.matches ?? []
    }

    // MARK: - Conversations

    func getChannelHistory(channelID: String, limit: Int = 30) async throws -> [SlackMessage] {
        let params = ["channel": channelID, "limit": String(limit)]
        let response: SlackConversationsHistoryResponse = try await apiCall("conversations.history", params: params)
        guard response.ok else { throw SlackError.apiError(response.error ?? "Unknown") }
        return response.messages ?? []
    }

    func listChannels(limit: Int = 200) async throws -> [SlackChannel] {
        let params = ["limit": String(limit), "types": "public_channel,private_channel", "exclude_archived": "true"]
        let response: SlackConversationsListResponse = try await apiCall("conversations.list", params: params)
        guard response.ok else { throw SlackError.apiError(response.error ?? "Unknown") }
        return response.channels ?? []
    }

    // MARK: - Users

    func getUserInfo(userID: String) async throws -> SlackUser {
        let params = ["user": userID]
        let response: SlackUserInfoResponse = try await apiCall("users.info", params: params)
        guard response.ok, let user = response.user else { throw SlackError.apiError(response.error ?? "Unknown") }
        return user
    }

    // MARK: - Auth Test

    func testAuth() async throws -> SlackAuthTestResponse {
        let response: SlackAuthTestResponse = try await apiCall("auth.test", params: [:])
        guard response.ok else { throw SlackError.apiError(response.error ?? "Unknown") }
        return response
    }

    // MARK: - Generic API Call

    private func apiCall<T: Codable>(_ method: String, params: [String: String]) async throws -> T {
        guard let token else { throw SlackError.noToken }

        var components = URLComponents(string: baseURL + method)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 3
            try await Task.sleep(for: .seconds(retryAfter))
            return try await apiCall(method, params: params)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    enum SlackError: LocalizedError {
        case noToken
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noToken: "No Slack token. Please connect Slack in Settings."
            case .apiError(let msg): "Slack API error: \(msg)"
            }
        }
    }
}
