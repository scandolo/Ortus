import Foundation

enum SlackTools {
    // MARK: - Tool Definitions for Claude API

    static let definitions: [[String: Any]] = [
        [
            "name": "search_messages",
            "description": "Search Slack messages across all channels. Returns matching messages with channel name, author, text, and timestamp.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search query. Supports Slack search modifiers like 'in:#channel', 'from:@user', 'before:2024-01-01', etc.",
                    ],
                    "count": [
                        "type": "integer",
                        "description": "Number of results to return (default 20, max 100).",
                    ],
                ],
                "required": ["query"],
            ] as [String: Any],
        ],
        [
            "name": "read_channel_history",
            "description": "Read recent messages from a Slack channel. Returns messages in reverse chronological order.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "channel_id": [
                        "type": "string",
                        "description": "The Slack channel ID (e.g., C01ABC123). Use list_channels to find channel IDs.",
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Number of messages to retrieve (default 30, max 100).",
                    ],
                ],
                "required": ["channel_id"],
            ] as [String: Any],
        ],
        [
            "name": "list_channels",
            "description": "List Slack channels the user has access to. Returns channel names and IDs.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of channels to return (default 200).",
                    ],
                ],
                "required": [] as [String],
            ] as [String: Any],
        ],
        [
            "name": "get_user_info",
            "description": "Get information about a Slack user by their user ID. Returns their display name, real name, and status.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "user_id": [
                        "type": "string",
                        "description": "The Slack user ID (e.g., U01ABC123).",
                    ],
                ],
                "required": ["user_id"],
            ] as [String: Any],
        ],
    ]

    // MARK: - Tool Execution

    @MainActor
    static func execute(name: String, input: [String: Any], slackService: SlackService) async -> String {
        do {
            switch name {
            case "search_messages":
                return try await executeSearch(input: input, slackService: slackService)
            case "read_channel_history":
                return try await executeReadHistory(input: input, slackService: slackService)
            case "list_channels":
                return try await executeListChannels(input: input, slackService: slackService)
            case "get_user_info":
                return try await executeGetUserInfo(input: input, slackService: slackService)
            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Individual Executors

    @MainActor
    private static func executeSearch(input: [String: Any], slackService: SlackService) async throws -> String {
        guard let query = input["query"] as? String else {
            return "Error: 'query' parameter is required."
        }
        let count = (input["count"] as? Int) ?? 20
        let matches = try await slackService.searchMessages(query: query, count: count)

        if matches.isEmpty {
            return "No messages found for query: \(query)"
        }

        var result = "Found \(matches.count) messages:\n\n"
        for match in matches {
            let channel = match.channel?.name ?? "unknown"
            let user = match.username ?? "unknown"
            let time = formatTimestamp(match.ts)
            result += "[\(time)] #\(channel) - \(user): \(match.text)\n\n"
        }
        return result
    }

    @MainActor
    private static func executeReadHistory(input: [String: Any], slackService: SlackService) async throws -> String {
        guard let channelID = input["channel_id"] as? String else {
            return "Error: 'channel_id' parameter is required."
        }
        let limit = (input["limit"] as? Int) ?? 30
        let messages = try await slackService.getChannelHistory(channelID: channelID, limit: limit)

        if messages.isEmpty {
            return "No messages found in this channel."
        }

        var result = "Recent \(messages.count) messages:\n\n"
        for msg in messages.reversed() {
            let user = msg.user ?? msg.botId ?? "unknown"
            let time = formatTimestamp(msg.ts)
            result += "[\(time)] \(user): \(msg.text)\n\n"
        }
        return result
    }

    @MainActor
    private static func executeListChannels(input: [String: Any], slackService: SlackService) async throws -> String {
        let limit = (input["limit"] as? Int) ?? 200
        let channels = try await slackService.listChannels(limit: limit)

        if channels.isEmpty {
            return "No channels found."
        }

        var result = "Channels (\(channels.count)):\n\n"
        for channel in channels {
            let name = channel.name ?? "unnamed"
            let topic = channel.topic?.value.isEmpty == false ? " — \(channel.topic!.value)" : ""
            result += "• #\(name) (ID: \(channel.id))\(topic)\n"
        }
        return result
    }

    @MainActor
    private static func executeGetUserInfo(input: [String: Any], slackService: SlackService) async throws -> String {
        guard let userID = input["user_id"] as? String else {
            return "Error: 'user_id' parameter is required."
        }
        let user = try await slackService.getUserInfo(userID: userID)

        var result = "User: \(user.realName ?? user.name)\n"
        result += "Display name: \(user.profile?.displayName ?? "N/A")\n"
        if let status = user.profile?.statusText, !status.isEmpty {
            result += "Status: \(status)\n"
        }
        return result
    }

    // MARK: - Helpers

    private static func formatTimestamp(_ ts: String) -> String {
        guard let interval = Double(ts) else { return ts }
        let date = Date(timeIntervalSince1970: interval)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
