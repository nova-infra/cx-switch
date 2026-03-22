import Foundation

protocol AuthTokenExchanging: Sendable {
    func exchangeRefreshToken(_ refreshToken: String) async throws -> AuthTokens
}

enum AuthServiceError: Error, LocalizedError {
    case invalidResponse(statusCode: Int, body: String)
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let code, let body):
            return "Token exchange failed (\(code)): \(body)"
        case .missingToken:
            return "OpenAI did not return a complete token bundle."
        }
    }
}

final class AuthService: AuthTokenExchanging {
    private let session: URLSession
    private let clientId: String

    init(
        session: URLSession = .shared,
        clientId: String = "app_EMoamEEZ73f0CkXaXp7hrann"
    ) {
        self.session = session
        self.clientId = clientId
    }

    func exchangeRefreshToken(_ refreshToken: String) async throws -> AuthTokens {
        guard let url = URL(string: "https://auth.openai.com/oauth/token") else {
            throw AuthServiceError.invalidResponse(statusCode: 0, body: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        request.setValue("CX Switch/1.0", forHTTPHeaderField: "User-Agent")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "scope", value: "openid profile email"),
        ]
        // percentEncodedQuery handles URL encoding of special chars
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse(statusCode: 0, body: "No HTTP response")
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(http.statusCode) else {
            NSLog("[AuthService] token exchange failed: status=%d body=%@", http.statusCode, bodyText)
            throw AuthServiceError.invalidResponse(statusCode: http.statusCode, body: bodyText)
        }

        let decoder = JSONDecoder()
        let token = try decoder.decode(TokenResponse.self, from: data)
        guard let accessToken = token.accessToken, !accessToken.isEmpty else {
            throw AuthServiceError.missingToken
        }

        return AuthTokens(
            accessToken: accessToken,
            refreshToken: token.refreshToken ?? refreshToken,
            idToken: token.idToken,
            accountId: token.accountId
        )
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let idToken: String?
    let accountId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountId = "account_id"
    }
}
