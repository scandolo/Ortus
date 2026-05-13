import Foundation

// MARK: - OAuth

struct SlackOAuthResponse: Codable {
    let ok: Bool
    let authedUser: SlackAuthedUser?
    let team: SlackTeam?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, team, error
        case authedUser = "authed_user"
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
    let name: String
}

// MARK: - Basic Response

/// Generic response shape for write endpoints that only return ok/error.
struct SlackBasicResponse: Codable {
    let ok: Bool
    let error: String?
}
