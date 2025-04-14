//
//  ShikimoriApi.swift
//  Aidoku
//
//  Created by Vova Lapskiy on 02.11.2024.
//

import Foundation

class ShikimoriApi {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let userAgent = "Aidoku"
    private let dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxx"

    // Registered under Skitty's Shikimori account
    var oauth = OAuthClient(
        id: "shikimori",
        clientId: "0pRPZsB87w9mp0gQe1HZbSiGt7FfVzJohPGhJKjayW4",
        clientSecret: "42vg9aoyPBnrvFoH1ey2GxbO24eVufOe8D0B6P756e8",
        baseUrl: "https://shikimori.one"
    )
}

extension ShikimoriApi {
    func getAuthenticationUrl() -> String? {
        guard let url = URL(string: oauth.baseUrl + "/oauth/authorize") else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        let queryItems = [
            URLQueryItem(name: "client_id", value: oauth.clientId),
            URLQueryItem(name: "redirect_uri", value: "aidoku://shikimori-auth"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "user_rates")
        ]
        components?.queryItems = queryItems
        return components?.url?.absoluteString
    }

    func getAccessToken(authCode: String) async -> OAuthResponse? {
        guard let url = URL(string: oauth.baseUrl + "/oauth/token") else { return nil }
        let boundary = "--" + String(UUID().hashValue)
        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = multipart(params: [
            "grant_type": "authorization_code",
            "client_id": oauth.clientId,
            "client_secret": oauth.clientSecret!,
            "redirect_uri": "aidoku://shikimori-auth",
            "scope": "users_rate",
            "code": authCode
        ], boundary: boundary)
        oauth.tokens = try? await URLSession.shared.object(from: request)
        oauth.saveTokens()
        return oauth.tokens
    }

    // MARK: API Methods - Data

    func search(query: String, censored: Bool = false) async -> GraphQLResponse<ShikimoriMangas>? {
        await requestGraphQL(
            GraphQLVariableQuery(
                query: ShikimoriQueries.searchQuery,
                variables: ShikimoriSearchVars(
                    search: query,
                    censored: censored
                )
            )
        )
    }

    func register(trackId: String, hasReadChapters: Bool) async -> String? {
        var query: [String: String] = [:]
        query["user_rate[user_id]"] = await getUser()
        query["user_rate[target_id]"] = trackId
        query["user_rate[target_type]"] = "Manga"
        query["user_rate[status]"] = hasReadChapters ? "watching" : "planned"

        guard var url = URL(string: oauth.baseUrl + "/api/v2/user_rates") else { return nil }
        url.queryParameters = query
        var request = authorizedRequest(for: url)
        request.httpMethod = "POST"

        guard
            let data = try? await requestData(urlRequest: request),
            let rate = try? decoder.decode(ShikimoriUserRate.self, from: data)
        else { return nil }

        return String(rate.id)
    }

    func update(trackId: String, update: TrackUpdate) async {
        var query: [String: String] = [:]
        if let status = update.status {
            query["user_rate[status]"] = getStatusFromTrack(status: status)
        }
        if let score = update.score {
            query["user_rate[score]"] = String(score)
        }
        if let lastReadChapter = update.lastReadChapter {
            query["user_rate[chapters]"] = String(lastReadChapter)
        }
        if let lastReadVolume = update.lastReadVolume {
            query["user_rate[volumes]"] = String(lastReadVolume)
        }

        guard var url = URL(string: oauth.baseUrl + "/api/v2/user_rates/\(trackId)") else { return }
        url.queryParameters = query
        var request = authorizedRequest(for: url)
        request.httpMethod = "PATCH"

        do {
            try await requestData(urlRequest: request)
        } catch {
            LogManager.logger.error("Shikimori Tracker: error updating tracker for \(trackId)")
        }
    }

    func getState(_ trackId: String) async -> TrackState {
        guard
            let url = URL(string: oauth.baseUrl + "/api/v2/user_rates/\(trackId)"),
            let data = try? await requestData(urlRequest: authorizedRequest(for: url)),
            let rate = try? decoder.decode(ShikimoriUserRate.self, from: data)
        else {
            return TrackState()
        }
        return TrackState(
            score: rate.score,
            status: getStatusFromString(status: rate.status),
            lastReadChapter: Float(rate.chapters),
            lastReadVolume: rate.volumes,
            startReadDate: rate.createdAt.date(format: dateFormat),
            finishReadDate: getStatusFromString(status: rate.status) == .completed
                ? rate.updatedAt.date(format: dateFormat)
                : nil
        )
    }

    func getMangaIdByRate(trackId: String) async -> String? {
        guard
            let url = URL(string: oauth.baseUrl + "/api/v2/user_rates/\(trackId)"),
            let data = try? await requestData(urlRequest: authorizedRequest(for: url)),
            let rate = try? decoder.decode(ShikimoriUserRate.self, from: data)
        else {
            return nil
        }
        return String(rate.targetId)
    }
}

private extension ShikimoriApi {
    func multipart(params: [String: String], boundary: String) -> Data? {
        var body = ""
        params.forEach {
            body += "--\(boundary)\r\n"
            body += "Content-Disposition: form-data; name=\"\($0.key)\"\r\n"
            body += "\r\n"
            body += $0.value
            body += "\r\n"
        }
        body += "--\(boundary)--"
        return body.data(using: .utf8)
    }

    func getStatusFromTrack(status: TrackStatus) -> String {
        switch status {
        case .completed: return "completed"
        case .dropped: return "dropped"
        case .paused: return "on_hold"
        case .planning: return "planned"
        case .reading: return "watching"
        case .rereading: return "rewatching"
        default: return ""
        }
    }

    func getStatusFromString(status: String?) -> TrackStatus {
        switch status {
        case "completed": return .completed
        case "dropped": return .dropped
        case "on_hold": return .paused
        case "planned": return .planning
        case "watching": return .reading
        case "rewatching": return .rereading
        case nil: return .none
        default: return .planning
        }
    }

    func getUser() async -> String? {
        let key: String = "Tracker.\(oauth.id).user_id"
        if UserDefaults.standard.string(forKey: key) == nil {
            guard
                let url = URL(string: oauth.baseUrl + "/api/users/whoami"),
                let data = try? await requestData(urlRequest: authorizedRequest(for: url)),
                let resp = try? decoder.decode(ShikimoriUser.self, from: data)
            else {
                return nil
            }
            UserDefaults.standard.set(String(resp.userId), forKey: key)
            return String(resp.userId)
        }
        return UserDefaults.standard.string(forKey: key)
    }

    private func requestGraphQL<T: Codable, D: Encodable>(_ data: D) async -> GraphQLResponse<T>? {
        guard let url = URL(string: oauth.baseUrl + "/api/graphql") else { return nil }
        var request = URLRequest(url: url)

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try? encoder.encode(data)

        return try? await URLSession.shared.object(from: request)
    }

    func authorizedRequest(for url: URL) -> URLRequest {
        if oauth.tokens == nil { oauth.loadTokens() }
        var request = URLRequest(url: url)
        request.addValue(
            "Bearer \(oauth.tokens?.accessToken ?? "")",
            forHTTPHeaderField: "Authorization"
        )
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    @discardableResult
    func requestData(urlRequest: URLRequest) async throws -> Data {
        var (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode

        if oauth.tokens == nil {
            oauth.loadTokens()
        }

        // check if token expired
        if statusCode == 401 || oauth.tokens!.expired {
            // refresh access token
            guard let url = URL(string: oauth.baseUrl + "/oauth/token") else { return data }
            var request = URLRequest(url: url)
            let boundary = "--" + String(UUID().hashValue)
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.httpMethod = "POST"
            request.httpBody = multipart(params: [
                "client_id": oauth.clientId,
                "client_secret": oauth.clientSecret!,
                "refresh_token": oauth.tokens?.refreshToken ?? "",
                "grant_type": "refresh_token"
            ], boundary: boundary)
            oauth.tokens = try await URLSession.shared.object(from: request)
            oauth.saveTokens()

            // try request again
            if let newAuthorization = URLRequest(url: url).value(forHTTPHeaderField: "Authorization") {
                var newRequest = urlRequest
                newRequest.setValue(newAuthorization, forHTTPHeaderField: "Authorization")
                newRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                (data, _) = try await URLSession.shared.data(for: newRequest)
            }
        }

        return data
    }
}
