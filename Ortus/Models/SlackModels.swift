import Foundation

// MARK: - Search

struct SlackSearchResponse: Codable {
    let ok: Bool
    let messages: SlackSearchMessages?
    let error: String?
}

struct SlackSearchMessages: Codable {
    let matches: [SlackSearchMatch]
    let total: Int
}

struct SlackSearchMatch: Codable {
    let text: String
    let username: String?
    let ts: String
    let channel: SlackSearchChannel?
    let permalink: String?
}

struct SlackSearchChannel: Codable {
    let id: String
    let name: String
}

// MARK: - Conversations

struct SlackConversationsListResponse: Codable {
    let ok: Bool
    let channels: [SlackChannel]?
    let error: String?
}

struct SlackChannel: Codable {
    let id: String
    let name: String?
    let isChannel: Bool?
    let isMember: Bool?
    let topic: SlackTopic?
    let purpose: SlackTopic?

    enum CodingKeys: String, CodingKey {
        case id, name, topic, purpose
        case isChannel = "is_channel"
        case isMember = "is_member"
    }
}

struct SlackTopic: Codable {
    let value: String
}

struct SlackConversationsHistoryResponse: Codable {
    let ok: Bool
    let messages: [SlackMessage]?
    let error: String?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case ok, messages, error
        case hasMore = "has_more"
    }
}

struct SlackMessage: Codable {
    let type: String?
    let user: String?
    let text: String
    let ts: String
    let botId: String?

    enum CodingKeys: String, CodingKey {
        case type, user, text, ts
        case botId = "bot_id"
    }
}

// MARK: - Users

struct SlackUserInfoResponse: Codable {
    let ok: Bool
    let user: SlackUser?
    let error: String?
}

struct SlackUser: Codable {
    let id: String
    let name: String
    let realName: String?
    let profile: SlackProfile?

    enum CodingKeys: String, CodingKey {
        case id, name, profile
        case realName = "real_name"
    }
}

struct SlackProfile: Codable {
    let displayName: String?
    let realName: String?
    let statusText: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case realName = "real_name"
        case statusText = "status_text"
    }
}

// MARK: - OAuth

struct SlackOAuthResponse: Codable {
    let ok: Bool
    let accessToken: String?
    let tokenType: String?
    let authedUser: SlackAuthedUser?
    let team: SlackTeam?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, team, error
        case accessToken = "access_token"
        case tokenType = "token_type"
        case authedUser = "authed_user"
    }

    var resolvedAccessToken: String? {
        authedUser?.accessToken ?? accessToken
    }
}

struct SlackAuthedUser: Codable {
    let id: String
    let accessToken: String
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

struct SlackTeam: Codable {
    let id: String
    let name: String?
}

// MARK: - Auth Test

struct SlackAuthTestResponse: Codable {
    let ok: Bool
    let team: String?
    let user: String?
    let userId: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, team, user, error
        case userId = "user_id"
    }
}
