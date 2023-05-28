//
//  MyAnimeListApi.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation
import CryptoKit

class MyAnimeListApi {

    private let decoder = JSONDecoder()

    let baseApiUrl = "https://api.myanimelist.net/v2"

    // Registered under Skitty's MAL account
    let oauth = OAuthClient(
        id: "myanimelist",
        clientId: "50cc1b37e2af29f668b087485ba46a46",
        baseUrl: "https://myanimelist.net/v1/oauth2",
        challengeMethod: .plain
    )

    private func requestData(url: URL) async throws -> Data {
        var (data, response) = try await URLSession.shared.data(for: oauth.authorizedRequest(for: url))

        // check if token expired
        if oauth.tokens?.expired ?? true || (response as? HTTPURLResponse)?.statusCode == 401 {
            // refresh access token
            guard let url = URL(string: baseApiUrl + "/token") else { return data }
            var request = oauth.authorizedRequest(for: url)
            request.httpMethod = "POST"
            request.httpBody = [
                "client_id": oauth.clientId,
                "refresh_token": oauth.tokens?.refreshToken,
                "grant_type": "refresh_token"
            ].percentEncoded()
            oauth.tokens = try await URLSession.shared.object(from: request)
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth.tokens), forKey: "Token.\(oauth.id).oauth")

            // try request again
            (data, _) = try await URLSession.shared.data(for: oauth.authorizedRequest(for: url))
        }

        return data
    }

    private func request<T: Codable>(url: URL) async throws -> T {
        try decoder.decode(T.self, from: try await requestData(url: url))
    }
}

// MARK: - Data
extension MyAnimeListApi {

    func search(query: String) async -> MyAnimeListSearchResponse? {
        guard var url = URL(string: baseApiUrl + "/manga") else { return nil }
        url.queryParameters = [
            "q": query.take(first: 64), // Search query can't be greater than 64 characters
            "nsfw": "true"
        ]
        return try? await self.request(url: url)
    }

    func getMangaDetails(id: Int) async -> MyAnimeListManga? {
        guard var url = URL(string: baseApiUrl + "/manga/\(id)") else { return nil }
        url.queryParameters = [
            "fields": "id,title,synopsis,num_chapters,main_picture,status,media_type,start_date,my_list_status"
        ]
        return try? await self.request(url: url)
    }

    func getMangaWithStatus(id: Int) async -> MyAnimeListManga? {
        guard var url = URL(string: baseApiUrl + "/manga/\(id)") else { return nil }
        url.queryParameters = [
            "fields": "num_volumes,num_chapters,my_list_status"
        ]
        return try? await self.request(url: url)
    }

    func getMangaStatus(id: Int) async -> MyAnimeListMangaStatus? {
        guard var url = URL(string: baseApiUrl + "/manga/\(id)") else { return nil }
        url.queryParameters = [
            "fields": "my_list_status"
        ]
        return (try? await self.request(url: url) as MyAnimeListManga)?.myListStatus
    }

    func updateMangaStatus(id: Int, status: MyAnimeListMangaStatus) async {
        guard let url = URL(string: baseApiUrl + "/manga/\(id)/my_list_status") else { return }
        var request = oauth.authorizedRequest(for: url)
        request.httpMethod = "PATCH"
        request.httpBody = status.percentEncoded()
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        _ = try? await self.requestData(url: url)
    }
}
