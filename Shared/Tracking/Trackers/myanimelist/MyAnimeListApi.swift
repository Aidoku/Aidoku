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

    var oauthTokens: MyAnimeListOAuth?

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
}

// MARK: - Tokens
extension MyAnimeListApi {
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
        oauthTokens = try? await URLSession.shared.object(from: request)
        return oauthTokens
    }

    func refreshAccessToken(refreshToken: String) async -> MyAnimeListOAuth? {
        guard let url = URL(string: "\(baseOAuthUrl)/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ].percentEncoded()
        oauthTokens = try? await URLSession.shared.object(from: request)
        return oauthTokens
    }

    func loadOAuthTokens() {
        guard let data = UserDefaults.standard.data(forKey: "Token.myanimelist.oauth") else { return }
        oauthTokens = try? JSONDecoder().decode(MyAnimeListOAuth.self, from: data)
    }

    func authorizedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue(
            "\(oauthTokens?.tokenType ?? "Bearer") \(oauthTokens?.accessToken ?? "")",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }
}

// MARK: - Data
extension MyAnimeListApi {

    func search(query: String) async -> MyAnimeListSearchResponse? {
        if oauthTokens == nil { loadOAuthTokens() }
        guard var url = URL(string: "\(baseApiUrl)/manga") else { return nil }
        url.queryParameters = [
            "q": query.take(first: 64), // Search query can't be greater than 64 characters
            "nsfw": "true"
        ]
        return try? await URLSession.shared.object(from: authorizedRequest(for: url))
    }

    func getMangaDetails(id: Int) async -> MyAnimeListManga? {
        if oauthTokens == nil { loadOAuthTokens() }
        guard var url = URL(string: "\(baseApiUrl)/manga/\(id)") else { return nil }
        url.queryParameters = [
            "fields": "id,title,synopsis,num_chapters,main_picture,status,media_type,start_date"
        ]
        return try? await URLSession.shared.object(from: authorizedRequest(for: url))
    }

    func getMangaWithStatus(id: Int) async -> MyAnimeListManga? {
        if oauthTokens == nil { loadOAuthTokens() }
        guard var url = URL(string: "\(baseApiUrl)/manga/\(id)") else { return nil }
        url.queryParameters = [
            "fields": "num_volumes,num_chapters,my_list_status"
        ]
        return try? await URLSession.shared.object(from: authorizedRequest(for: url))
    }

    func getMangaStatus(id: Int) async -> MyAnimeListMangaStatus? {
        if oauthTokens == nil { loadOAuthTokens() }
        guard var url = URL(string: "\(baseApiUrl)/manga/\(id)") else { return nil }
        url.queryParameters = [
            "fields": "my_list_status"
        ]
        return (try? await URLSession.shared.object(from: authorizedRequest(for: url)) as MyAnimeListManga)?.myListStatus
    }

    func updateMangaStatus(id: Int, status: MyAnimeListMangaStatus) async {
        if oauthTokens == nil { loadOAuthTokens() }
        guard let url = URL(string: "\(baseApiUrl)/manga/\(id)/my_list_status") else { return }
        var request = authorizedRequest(for: url)
        request.httpMethod = "PUT"
        request.httpBody = status.percentEncoded()
        _ = try? await URLSession.shared.data(for: request)
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
