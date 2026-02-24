//
//  MangaBakaApi.swift
//  Aidoku
//
//  Created by Skitty on 2/24/26.
//

import Foundation

actor MangaBakaApi {
    let baseApiUrl = URL(string: "https://api.mangabaka.dev")!

    // registered under skitty's MangaBaka account
    nonisolated let oauth = OAuthClient(
        id: "mangabaka",
        clientId: "rhqyADkXfqdmFVZcslegTvgLvLeOpFdz",
        baseUrl: "https://mangabaka.org/auth/oauth2",
        challengeMethod: .s256
    )

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func refreshAccessToken() async -> OAuthResponse? {
        guard let refreshToken = await oauth.tokens?.refreshToken else { return nil }

        guard let url = URL(string: oauth.baseUrl + "/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = [
            "client_id": oauth.clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
            "redirect_uri": "aidoku://mangabaka-auth"
        ].percentEncoded()
        let response: OAuthResponse? = try? await URLSession.shared.object(from: request)
        await oauth.setTokens(response)
        return response
    }

    private func requestData(urlRequest: URLRequest) async throws -> Data {
        var (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode

        if await oauth.tokens == nil {
            await oauth.loadTokens()
        }

        let tokenExpired = await oauth.tokens?.expired == true

        // check if token expired
        if statusCode == 400 || statusCode == 401 || statusCode == 403 || tokenExpired {
            // ensure we have a refresh token, otherwise we need to fully re-auth
            let reloginNeeded = await oauth.checkIfReloginNeeded(trackerName: "MangaBaka")
            guard !reloginNeeded else {
                return data
            }

            // refresh access token
            if await refreshAccessToken() != nil {
                // try request again with refreshed token
                let newAuthorization = await oauth.authorizedRequest(for: URL(string: oauth.baseUrl + "/token")!)
                    .value(forHTTPHeaderField: "Authorization")
                if let newAuthorization {
                    var newRequest = urlRequest
                    newRequest.setValue(newAuthorization, forHTTPHeaderField: "Authorization")
                    (data, _) = try await URLSession.shared.data(for: newRequest)
                }
            }
        }

        return data
    }

    private func requestData(url: URL) async throws -> Data {
        try await requestData(urlRequest: oauth.authorizedRequest(for: url))
    }

    private func object<T: Decodable>(from url: URL) async throws -> T {
        try decoder.decode(T.self, from: try await requestData(url: url))
    }

    private func object<T: Decodable>(from request: URLRequest) async throws -> T {
        try decoder.decode(T.self, from: try await requestData(urlRequest: request))
    }
}

extension MangaBakaApi {
    func search(query: String, nsfw: Bool = true) async throws -> [MangaBakaSeries] {
        guard
            let url = URL(string: "./v1/series/search", relativeTo: baseApiUrl),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        else {
            throw MangaBakaApiError.invalidURL
        }
        var queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        if !nsfw {
            queryItems += [
                URLQueryItem(name: "not_content_rating", value: "erotica"),
                URLQueryItem(name: "not_content_rating", value: "pornographic")
            ]
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MangaBakaApiError.invalidURL
        }
        let results: MangaBakaResponse<[MangaBakaSeries]> = try await object(from: url)
        if let data = results.data {
            return data
        } else {
            throw MangaBakaApiError.apiError(message: results.message ?? results.issues?.first?.message ?? "Unknown error")
        }
    }

    func getSeries(id: Int) async throws -> MangaBakaSeries {
        guard let url = URL(string: "./v1/series/\(id)", relativeTo: baseApiUrl) else {
            throw MangaBakaApiError.invalidURL
        }
        let results: MangaBakaResponse<MangaBakaSeries> = try await object(from: url)
        if let data = results.data {
            return data
        } else {
            throw MangaBakaApiError.apiError(message: results.message ?? results.issues?.first?.message ?? "Unknown error")
        }
    }

    func getLibraryEntry(seriesId: Int) async throws -> MangaBakaLibraryEntry {
        guard let url = URL(string: "./v1/my/library/\(seriesId)", relativeTo: baseApiUrl) else {
            throw MangaBakaApiError.invalidURL
        }
        let results: MangaBakaResponse<MangaBakaLibraryEntry> = try await object(from: url)
        if let data = results.data {
            return data
        } else {
            throw MangaBakaApiError.apiError(message: results.message ?? results.issues?.first?.message ?? "Unknown error")
        }
    }

    func getLibraryEntries(seriesIds: [Int]) async throws -> [MangaBakaLibraryEntry] {
        guard
            let url = URL(string: "./v1/my/library/batch", relativeTo: baseApiUrl),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        else {
            throw MangaBakaApiError.invalidURL
        }
        components.queryItems = seriesIds.map { URLQueryItem(name: "series_id", value: String($0)) }
        guard let url = components.url else {
            throw MangaBakaApiError.invalidURL
        }
        let request = await oauth.authorizedRequest(for: url)
        let results: MangaBakaResponse<[MangaBakaLibraryEntry]> = try await object(from: request)
        if let data = results.data {
            return data
        } else {
            throw MangaBakaApiError.apiError(message: results.message ?? results.issues?.first?.message ?? "Unknown error")
        }
    }

    func updateLibraryEntry(seriesId: Int, create: Bool = false, data: MangaBakaLibraryEntry) async throws {
        guard let url = URL(string: "./v1/my/library/\(seriesId)", relativeTo: baseApiUrl) else {
            throw MangaBakaApiError.invalidURL
        }
        var request = await oauth.authorizedRequest(for: url)
        request.httpMethod = create ? "POST" : "PATCH"
        request.httpBody = try? encoder.encode(data)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await requestData(urlRequest: request)
    }
}

enum MangaBakaApiError: Error {
    case invalidURL
    case apiError(message: String)
    case todo
}
