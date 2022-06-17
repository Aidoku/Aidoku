//
//  MyAnimeListApi.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation
import CryptoKit

class MyAnimeListApi {
    // Registered under Skitty's MAL account
    let clientId = "50cc1b37e2af29f668b087485ba46a46"

    let baseOAuthUrl = "https://myanimelist.net/v1/oauth2"
    let baseApiUrl = "https://api.myanimelist.net/v2"

    var codeVerifier = ""

    lazy var authenticationUrl: String? = {
        guard let url = URL(string: "\(baseOAuthUrl)/authorize") else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_challenge", value: generatePkceChallenge()),
            URLQueryItem(name: "response_type", value: "code")
        ]
        return components?.url?.absoluteString
    }()

    func getAccessToken(authCode: String) async -> MyAnimeListOAuth? {
        guard let url = URL(string: "\(baseOAuthUrl)/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": authCode,
            "code_verifier": codeVerifier
        ].percentEncoded()
        return try? await URLSession.shared.object(from: request)
    }
}

// MARK: - PKCE Utilities
extension MyAnimeListApi {

    func base64<S>(_ octets: S) -> String where S: Sequence, UInt8 == S.Element {
        let data = Data(octets)
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespaces)
    }

    func generatePkceVerifier() -> String {
        var octets = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, octets.count, &octets)
        codeVerifier = base64(octets)
        return codeVerifier
    }

    func generatePkceChallenge() -> String {
        // This would be correct for another oauth provider, but MAL only supports the "plain" option.
//        generatePkceVerifier()
//            .data(using: .ascii)
//            .map { SHA256.hash(data: $0) }
//            .map { base64($0) } ?? ""
        // So instead, the verifier is used as the challenge string.
        generatePkceVerifier()
    }
}
