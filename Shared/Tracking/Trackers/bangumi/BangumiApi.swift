//
//  BangumiApi.swift
//  Aidoku
//
//  Created by dyphire on 22/9/2025.
//

import Foundation

class BangumiApi {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    let oauth = OAuthClient(
        id: "bangumi",
        clientId: "bgm478768d0daf063854",
        clientSecret: "2d78114dc16ea3a4786de4f7c6afa3e1",
        baseUrl: "https://bgm.tv/oauth"
    )

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    func getAccessToken(authCode: String) async -> OAuthResponse? {
        guard let url = URL(string: oauth.baseUrl + "/access_token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "client_id": oauth.clientId,
            "client_secret": oauth.clientSecret!,
            "code": authCode,
            "redirect_uri": "aidoku://bangumi-auth"
        ]
        request.httpBody = body.percentEncoded()

        oauth.tokens = try? await URLSession.shared.object(from: request)
        oauth.saveTokens()
        return oauth.tokens
    }
}

// MARK: - Data
extension BangumiApi {
    func search(query: String, nsfw: Bool = false) async -> [BangumiSubject]? {
        // Try the new v0 API first
        let url = URL(string: "https://api.bgm.tv/v0/search/subjects?limit=20")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var filter: [String: Any] = ["type": [1]]
        if !nsfw {
            filter["nsfw"] = false
        }
        let searchBody: [String: Any] = ["keyword": query, "sort": "match", "filter": filter]
        request.httpBody = try? JSONSerialization.data(withJSONObject: searchBody)

        if let response: BangumiSearchResponse = try? await URLSession.shared.object(from: request) {
            return response.subjects
        }

        // Fallback to old API
        let fallbackUrl = URL(string: "https://api.bgm.tv/search/subject/\(query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")!
        var fallbackRequest = URLRequest(url: fallbackUrl)
        fallbackRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let fallbackResponse: BangumiSearchResponse? = try? await URLSession.shared.object(from: fallbackRequest)
        return fallbackResponse?.subjects
    }

    func getCurrentUser() async -> BangumiUser? {
        let url = URL(string: "https://api.bgm.tv/v0/me")!
        var request = oauth.authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let user: BangumiUser? = try? await URLSession.shared.object(from: request)
        return user
    }

    func getSubject(id: Int) async -> BangumiSubject? {
        let url = URL(string: "https://api.bgm.tv/v0/subjects/\(id)")!
        var request = oauth.authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let subject: BangumiSubject? = try? await URLSession.shared.object(from: request)
        return subject
    }

    func getSubjectState(id: Int) async -> BangumiCollection? {
        // First get current user info
        guard let user = await getCurrentUser() else {
            return nil
        }

        let url = URL(string: "https://api.bgm.tv/v0/users/\(user.username)/collections/\(id)")!
        var request = oauth.authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let collection = try? JSONDecoder().decode(BangumiCollection.self, from: data)
                return collection
            }
        } catch {
            // Network error - silently fail
        }
        return nil
    }

    @discardableResult
    func update(subject: Int, update: TrackUpdate) async -> Bool {
        let url = URL(string: "https://api.bgm.tv/v0/users/-/collections/\(subject)")!
        var request = oauth.authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"

        let collectionUpdate = BangumiCollectionUpdate(
            type: getStatusString(status: update.status),
            rate: update.score,
            comment: nil,
            tags: nil,
            vol_status: update.lastReadVolume.map { Int($0) },
            ep_status: update.lastReadChapter.map { Int($0) }
        )

        request.httpBody = try? encoder.encode(collectionUpdate)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200 || httpResponse.statusCode == 201
            }
        } catch {
            // Update error - silently fail
        }
        return false
    }

    private func request<T: Codable>(_ url: URL, method: String = "GET", body: Data? = nil) async -> T? {
        var request = oauth.authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = method
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        return try? await URLSession.shared.object(from: request)
    }
}

private extension BangumiApi {
    func getStatusString(status: TrackStatus?) -> BangumiCollectionStatus? {
        switch status {
            case .reading: return .doing
            case .planning: return .wish
            case .completed: return .collect
            case .dropped: return .dropped
            case .paused: return .on_hold
            case .rereading: return .doing
            default: return nil
        }
    }
}
