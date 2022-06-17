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
        guard let baseUrl = URL(string: "\(baseOAuthUrl)/authorize") else { return nil }
        var components = URLComponents(url: baseUrl, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_challenge", value: generatePkceChallenge()),
            URLQueryItem(name: "response_type", value: "code")
        ]
        return components?.url?.absoluteString
    }()
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
        var octets = [UInt8](repeating: 0, count: 40)
        _ = SecRandomCopyBytes(kSecRandomDefault, octets.count, &octets)
        codeVerifier = base64(octets)
        return codeVerifier
    }

    func generatePkceChallenge() -> String {
        let challenge = generatePkceVerifier()
            .data(using: .ascii)
            .map { SHA256.hash(data: $0) }
            .map { base64($0) }
        return challenge ?? ""
    }
}
