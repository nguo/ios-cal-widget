import Foundation

/// Exchanges a long-lived Google OAuth refresh token for a short-lived access token via
/// the plain token endpoint — no GoogleSignIn SDK needed, so this runs in the widget
/// extension as well as the app. The refresh token is read from shared Keychain by the
/// caller and passed in.
public struct TokenRefreshService {
    public struct AccessToken: Equatable, Sendable {
        public let token: String
        public let expiresAt: Date
    }

    private struct TokenResponse: Codable {
        let access_token: String
        let expires_in: Int
    }

    public let clientID: String
    /// iOS OAuth clients are public and have no secret; kept optional for other client types.
    public let clientSecret: String?
    private let transport: HTTPTransport
    private let endpoint = URL(string: "https://oauth2.googleapis.com/token")!

    public init(clientID: String, clientSecret: String? = nil, transport: HTTPTransport = URLSession.shared) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.transport = transport
    }

    public func accessToken(refreshToken: String, now: Date = Date()) async throws -> AccessToken {
        var params = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        if let clientSecret { params["client_secret"] = clientSecret }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncode(params).data(using: .utf8)

        let (data, response) = try await transport.data(for: request)
        try Self.validate(response, data: data)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AccessToken(
            token: decoded.access_token,
            expiresAt: now.addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw HTTPError.nonHTTPResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw HTTPError.status(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    public static func formURLEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
