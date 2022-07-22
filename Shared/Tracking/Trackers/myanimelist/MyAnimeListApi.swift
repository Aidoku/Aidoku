//
//  MyAnimeListApi.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation
import CryptoKit

class MyAnimeListApi {
    let oauth = OAuthClient(
            id: "myanimelist",
            clientId: "50cc1b37e2af29f668b087485ba46a46", // Registered under Skitty's MAL account
            base: "https://myanimelist.net/v1/oauth2"
    )

    let baseApiUrl = "https://api.myanimelist.net/v2"
}

// MARK: - Data
extension MyAnimeListApi {

    func search(query: String) async -> MyAnimeListSearchResponse? {
        guard var url = URL(string: "\(baseApiUrl)/manga") else {
            return nil
        }
        url.queryParameters = [
            "q": query.take(first: 64), // Search query can't be greater than 64 characters
            "nsfw": "true"
        ]
        return try? await URLSession.shared.object(from: oauth.authorizedRequest(for: url))
    }

    func getMangaDetails(id: Int) async -> MyAnimeListManga? {
        guard var url = URL(string: "\(baseApiUrl)/manga/\(id)") else {
            return nil
        }
        url.queryParameters = [
            "fields": "id,title,synopsis,num_chapters,main_picture,status,media_type,start_date"
        ]
        return try? await URLSession.shared.object(from: oauth.authorizedRequest(for: url))
    }

    func getMangaWithStatus(id: Int) async -> MyAnimeListManga? {
        guard var url = URL(string: "\(baseApiUrl)/manga/\(id)") else {
            return nil
        }
        url.queryParameters = [
            "fields": "num_volumes,num_chapters,my_list_status"
        ]
        return try? await URLSession.shared.object(from: oauth.authorizedRequest(for: url))
    }

    func getMangaStatus(id: Int) async -> MyAnimeListMangaStatus? {
        guard var url = URL(string: "\(baseApiUrl)/manga/\(id)") else {
            return nil
        }
        url.queryParameters = [
            "fields": "my_list_status"
        ]
        return (try? await URLSession.shared.object(from: oauth.authorizedRequest(for: url)) as MyAnimeListManga)?.myListStatus
    }

    func updateMangaStatus(id: Int, status: MyAnimeListMangaStatus) async {
        guard let url = URL(string: "\(baseApiUrl)/manga/\(id)/my_list_status") else {
            return
        }
        var request = oauth.authorizedRequest(for: url)
        request.httpMethod = "PUT"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = status.percentEncoded()
        _ = try? await URLSession.shared.data(for: request)
    }
}
