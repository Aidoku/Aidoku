//
// Created by Koding Dev on 19/7/2022.
//

import Foundation

class OAuthClient {
    let id: String
    let clientId: String
    let base: String

    var codeVerifier = ""
    var tokens: OAuthResponse?

    init(id: String, clientId: String, base: String) {
        self.id = id
        self.clientId = clientId
        self.base = base
    }

    lazy var authenticationUrl: String? = {
        guard let url = URL(string: "\(base)/authorize") else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_challenge", value: generatePkceChallenge()),
            URLQueryItem(name: "response_type", value: "code")
        ]
        return components?.url?.absoluteString
    }()

    func getAccessToken(authCode: String) async -> OAuthResponse? {
        guard let url = URL(string: "\(base)/token") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": authCode,
            "code_verifier": codeVerifier
        ].percentEncoded()
        tokens = try? await URLSession.shared.object(from: request)
        return tokens
    }

    func refreshAccessToken(refreshToken: String) async -> OAuthResponse? {
        guard let url = URL(string: "\(base)/token") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ].percentEncoded()
        tokens = try? await URLSession.shared.object(from: request)
        return tokens
    }

    func loadTokens() {
        guard let data = UserDefaults.standard.data(forKey: "Token.\(id).oauth") else {
            return
        }
        tokens = try? JSONDecoder().decode(OAuthResponse.self, from: data)
    }

    func authorizedRequest(for url: URL) -> URLRequest {
        if tokens == nil {
            loadTokens()
        }

        var request = URLRequest(url: url)
        request.addValue(
                "\(tokens?.tokenType ?? "Bearer") \(tokens?.accessToken ?? "")",
                forHTTPHeaderField: "Authorization"
        )
        return request
    }

    // MARK: - PKCE
    func generatePkceVerifier() -> String {
        var octets = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, octets.count, &octets)
        codeVerifier = base64(octets)
        return codeVerifier
    }

    func generatePkceChallenge() -> String {
        // TODO: Modify this for AniList
        // This would be correct for another oauth provider, but MAL only supports the "plain" option.
//        generatePkceVerifier()
//            .data(using: .ascii)
//            .map { SHA256.hash(data: $0) }
//            .map { base64($0) } ?? ""
        // So instead, the verifier is used as the challenge string.
        generatePkceVerifier()
    }

    // MARK: - Utils
    private func base64<S>(_ octets: S) -> String where S: Sequence, UInt8 == S.Element {
        let data = Data(octets)
        return data
                .base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: .whitespaces)
    }
}
