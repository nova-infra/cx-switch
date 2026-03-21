import Foundation

struct AuthBlob: Codable {
    var authMode: String?
    var lastRefresh: String?
    var tokens: AuthTokens?
    var openaiApiKey: String?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case lastRefresh = "last_refresh"
        case tokens
        case openaiApiKey = "OPENAI_API_KEY"
    }
}

struct AuthTokens: Codable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var accountId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountId = "account_id"
    }
}
