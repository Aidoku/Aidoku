//
//  BangumiApi.swift
//  Aidoku
//
//  Created by dyphire on 22/9/2025.
//

import Foundation

enum BangumiApiError: Error {
    case notLoggedIn
    /// e.g. progress update on an uncollected subject
    case notFound
    case requestFailed
}

actor BangumiApi {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userAgent = "Aidoku/Aidoku (https://github.com/Aidoku/Aidoku)"

    let apiBase: URL

    nonisolated let oauth = OAuthClient(
        id: "bangumi",
        clientId: "bgm479068d16523bfca2",
        clientSecret: "d6328f094c5e43a082b6141ab1f4ecc5",
        baseUrl: "https://bgm.tv/oauth"
    )

    init(apiBase: URL = URL(string: "https://next.bgm.tv")!) {
        self.apiBase = apiBase
        decoder.dateDecodingStrategy = .iso8601
    }

    func authorizedRequest(for url: URL) async -> URLRequest {
        await oauth.authorizedRequest(for: url, additionalHeaders: ["User-Agent": userAgent])
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

        let response: OAuthResponse? = try? await URLSession.shared.object(from: request)
        await oauth.setTokens(response)
        return response
    }

    func refreshAccessToken() async -> OAuthResponse? {
        guard let refreshToken = await oauth.tokens?.refreshToken else { return nil }

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

        let response: OAuthResponse? = try? await URLSession.shared.object(from: request)
        await oauth.setTokens(response)
        return response
    }
}

// MARK: - Data
extension BangumiApi {
    private nonisolated func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: apiBase) else {
            throw BangumiApiError.requestFailed
        }
        return url
    }

    func search(query: String, nsfw: Bool = false) async throws -> [BangumiSubject] {
        let url = try endpoint("p1/search/subjects?limit=20")
        let searchBody = BangumiSearchRequest(
            keyword: query,
            sort: "match",
            filter: .init(type: [1], nsfw: nsfw)
        )
        let response: BangumiSearchResponse = try await request(
            url, method: "POST", body: try encoder.encode(searchBody)
        )
        return response.data ?? []
    }

    func getSubject(id: Int) async throws -> BangumiSubject {
        try await request(try endpoint("p1/subjects/\(id)"))
    }

    func update(subject id: Int, update: TrackUpdate) async throws {
        var collectionType = update.status.flatMap { getStatusString(status: $0) }?.rawValue
        var rate = update.score
        let progressBody = BangumiProgressPatch(
            epStatus: update.lastReadChapter.map { Int($0.rounded(.down)) },
            volStatus: update.lastReadVolume
        )

        let hasCollectionUpdate = collectionType != nil || rate != nil
        let hasProgressUpdate = progressBody.epStatus != nil || progressBody.volStatus != nil
        guard hasCollectionUpdate || hasProgressUpdate else { return }

        let url = try endpoint("p1/collections/subjects/\(id)")

        if hasCollectionUpdate && (collectionType == nil || rate == nil) {
            let interest = try await getSubject(id: id).interest
            if collectionType == nil {
                collectionType = interest?.type ?? BangumiCollectionStatus.doing.rawValue
            }
            if rate == nil {
                rate = interest?.rate ?? 0
            }
        }

        if hasCollectionUpdate, let collectionType, let rate {
            try await send(url, method: "PUT", body: BangumiCollectionPut(
                type: collectionType,
                rate: rate
            ))
        }

        if hasProgressUpdate {
            do {
                try await send(url, method: "PATCH", body: progressBody)
            } catch BangumiApiError.notFound where !hasCollectionUpdate {
                // PATCH 404s on uncollected subjects: create a default collection first
                try await send(url, method: "PUT", body: BangumiCollectionPut(
                    type: BangumiCollectionStatus.doing.rawValue,
                    rate: 0
                ))
                try await send(url, method: "PATCH", body: progressBody)
            }
        }
    }
}

// MARK: - Networking
private extension BangumiApi {
    func request<T: Decodable>(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, _) = try await perform(url, method: method, body: body)
        guard let decoded = try? decoder.decode(T.self, from: data) else {
            throw BangumiApiError.requestFailed
        }
        return decoded
    }

    @discardableResult
    func send<B: Encodable>(_ url: URL, method: String, body: B) async throws -> HTTPURLResponse {
        try await perform(url, method: method, body: try encoder.encode(body)).1
    }

    @discardableResult
    func perform(_ url: URL, method: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = await authorizedRequest(for: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await dataWithAuthRetry(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BangumiApiError.requestFailed
        }
        switch httpResponse.statusCode {
            case 200..<300:
                return (data, httpResponse)
            case 404:
                throw BangumiApiError.notFound
            default:
                throw BangumiApiError.requestFailed
        }
    }

    func dataWithAuthRetry(for request: URLRequest) async throws -> (Data, URLResponse) {
        if await oauth.tokens == nil {
            await oauth.loadTokens()
        }

        var (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 401 else {
            return (data, response)
        }

        // Ensure we have a refresh token, otherwise we need to fully re-auth.
        let reloginNeeded = await oauth.checkIfReloginNeeded(trackerName: "Bangumi")
        guard !reloginNeeded, await refreshAccessToken() != nil, let url = request.url else {
            throw BangumiApiError.notLoggedIn
        }

        // Retry the original request with the refreshed token.
        var retried = request
        if let authorization = await oauth.authorizedRequest(for: url)
            .value(forHTTPHeaderField: "Authorization") {
            retried.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        (data, response) = try await URLSession.shared.data(for: retried)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            throw BangumiApiError.notLoggedIn
        }
        return (data, response)
    }

    func getStatusString(status: TrackStatus) -> BangumiCollectionStatus? {
        switch status {
            case .reading: return .doing
            case .planning: return .wish
            case .completed: return .collect
            case .dropped: return .dropped
            case .paused: return .onHold
            case .rereading: return .doing
            default: return nil
        }
    }
}
