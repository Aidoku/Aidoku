//
//  BangumiApi.swift
//  Aidoku
//
//  Created by dyphire on 22/9/2025.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

class BangumiApi {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userAgent = "Aidoku/Aidoku (https://github.com/Aidoku/Aidoku)"

    let oauth = OAuthClient(
        id: "bangumi",
        clientId: "bgm479068d16523bfca2",
        clientSecret: "d6328f094c5e43a082b6141ab1f4ecc5",
        baseUrl: "https://bgm.tv/oauth"
    )

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    func authorizedRequest(for url: URL) -> URLRequest {
        oauth.authorizedRequest(for: url, additionalHeaders: ["User-Agent": userAgent])
    }

    func getAccessToken(authCode: String) async -> OAuthResponse? {
        guard let url = URL(string: oauth.baseUrl + "/access_token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

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

    func refreshAccessToken() async -> OAuthResponse? {
        guard let refreshToken = oauth.tokens?.refreshToken else { return nil }

        guard let url = URL(string: oauth.baseUrl + "/access_token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let body = [
            "grant_type": "refresh_token",
            "client_id": oauth.clientId,
            "client_secret": oauth.clientSecret!,
            "refresh_token": refreshToken,
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

        // Add type parameter (type=1 for books/manga)
        var filter: [String: Any] = ["type": [1]]
        if !nsfw {
            filter["nsfw"] = false
        }
        let searchBody: [String: Any] = ["keyword": query, "sort": "match", "filter": filter]
        let body = try? JSONSerialization.data(withJSONObject: searchBody)

        if let response: BangumiSearchResponse = await request(url, method: "POST", body: body) {
            return response.subjects
        }

        // Fallback to old API
        var fallbackUrl = URL(string: "https://api.bgm.tv/search/subject/\(query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")!
        // Add type parameter (type=1 for books/manga)
        if var urlComponents = URLComponents(url: fallbackUrl, resolvingAgainstBaseURL: false) {
            urlComponents.queryItems = [URLQueryItem(name: "type", value: "1")]
            if let urlWithType = urlComponents.url {
                fallbackUrl = urlWithType
            }
        }
        var fallbackRequest = URLRequest(url: fallbackUrl)
        fallbackRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        fallbackRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let fallbackResponse: BangumiSearchResponse? = try? await URLSession.shared.object(from: fallbackRequest)
        return fallbackResponse?.subjects
    }

    func getUser() async -> BangumiUser? {
        let url = URL(string: "https://api.bgm.tv/v0/me")!
        return await request(url)
    }

    func getSubject(id: Int) async -> BangumiSubject? {
        let url = URL(string: "https://api.bgm.tv/v0/subjects/\(id)")!
        return await request(url)
    }

    func getSubjectState(id: Int) async -> BangumiCollection? {
        // First get current user info
        guard let user = await getUser() else {
            return nil
        }

        let url = URL(string: "https://api.bgm.tv/v0/users/\(user.username)/collections/\(id)")!
        return await request(url)
    }

    @discardableResult
    func update(subject: Int, update: TrackUpdate) async -> Bool {
        let url = URL(string: "https://api.bgm.tv/v0/users/-/collections/\(subject)")!
        var request = authorizedRequest(for: url)
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
            let (_, response) = try await requestData(urlRequest: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200 || httpResponse.statusCode == 201
            }
            return false
        } catch {
            // Update error - silently fail
            return false
        }
    }

    private func requestData(urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        var (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode

        if oauth.tokens == nil {
            oauth.loadTokens()
        }

        // Check if token expired (401 Unauthorized)
        if statusCode == 401 || statusCode == 40101 || statusCode == 40102 || oauth.tokens?.expired == true {
            // ensure we have a refresh token, otherwise we need to fully re-auth
            guard oauth.tokens?.refreshToken != nil else {
                if !oauth.tokens!.askedForRefresh {
                    oauth.tokens!.askedForRefresh = true
                    oauth.saveTokens()
#if !os(macOS)
                    await (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
                        title: String(format: NSLocalizedString("%@_TRACKER_LOGIN_NEEDED"), "Bangumi"),
                        message: String(format: NSLocalizedString("%@_TRACKER_LOGIN_NEEDED_TEXT"), "Bangumi")
                    )
#endif
                }
                return (data, response)
            }

            // Try to refresh token and retry request
            guard await refreshAccessToken() != nil else {
                return (data, response)
            }

            // Retry the original request with refreshed token
            if let newAuthorization = oauth.authorizedRequest(for: urlRequest.url!).value(forHTTPHeaderField: "Authorization") {
                var newRequest = urlRequest
                newRequest.setValue(newAuthorization, forHTTPHeaderField: "Authorization")
                newRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                (data, response) = try await URLSession.shared.data(for: newRequest)
            }
        }

        return (data, response)
    }

    private func request<T: Codable>(_ url: URL, method: String = "GET", body: Data? = nil) async -> T? {
        var request = authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        guard let (data, _) = try? await requestData(urlRequest: request) else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
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
