//
//  AniListApi.swift
//  Aidoku
//
//  Created by Koding Dev on 19/7/2022.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

actor AniListApi {
    private let encoder = JSONEncoder()

    // Registered under Skitty's AniList account
    nonisolated let oauth = OAuthClient(
        id: "anilist",
        clientId: "8912",
        baseUrl: "https://anilist.co/api/v2/oauth"
    )

    var scoreType: String?
}

// MARK: - Data
extension AniListApi {
    func search(query: String, nsfw: Bool = true) async -> ALPage? {
        let response: GraphQLResponse<AniListSearchResponse>? = await request(
            GraphQLVariableQuery(
                query: nsfw ? AniListQueries.searchQueryNsfw : AniListQueries.searchQuery,
                variables: AniListSearchVars(search: query)
            )
        )
        return response?.data.Page
    }

    func getMedia(id: Int) async -> Media? {
        let response: GraphQLResponse<AniListMediaStatusResponse>? = await request(
            GraphQLVariableQuery(query: AniListQueries.mediaQuery, variables: AniListMediaStatusVars(id: id))
        )
        return response?.data.Media
    }

    func getMediaState(id: Int) async -> Media? {
        let response: GraphQLResponse<AniListMediaStatusResponse>? = await request(
            GraphQLVariableQuery(query: AniListQueries.mediaStatusQuery, variables: AniListMediaStatusVars(id: id))
        )
        return response?.data.Media
    }

    @discardableResult
    func update(media: Int, update: TrackUpdate) async -> GraphQLResponse<AniListUpdateResponse>? {
        await request(
            GraphQLVariableQuery(
                query: AniListQueries.updateMediaQuery,
                variables: AniListUpdateMediaVars(
                    id: media,
                    status: update.status != nil ? getStatusString(status: update.status!) : nil,
                    progress: update.lastReadChapter != nil ? Int(update.lastReadChapter!) : nil,
                    volumes: update.lastReadVolume,
                    score: update.score,
                    startedAt: encodeDate(update.startReadDate),
                    completedAt: encodeDate(update.finishReadDate)
                )
            )
        )
    }

    func getUser() async -> User? {
        let response: GraphQLResponse<AniListViewerResponse>? = await request(
            GraphQLQuery(query: AniListQueries.viewerQuery)
        )
        return response?.data.Viewer
    }

    private func request<T: Codable & Sendable, D: Encodable>(_ data: D) async -> GraphQLResponse<T>? {
        let url = URL(string: "https://graphql.anilist.co")!
        var request = await oauth.authorizedRequest(for: url)

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try? encoder.encode(data)

        let response: GraphQLResponse<T>? = try? await URLSession.shared.object(from: request)
        // check if token is invalid
        if let response, let errors = response.errors, errors.contains(where: { $0.status == 400 }) {
            // don't show the relogin alert if we're not logged in in the first place
            let isLoggedIn = UserDefaults.standard.string(forKey: "Tracker.anilist.token") != nil
            if isLoggedIn {
                await oauth.showReloginAlert(trackerName: "AniList")
            }
        }

        return response
    }

    func getStoreType() async -> String {
        if let scoreType {
            return scoreType
        }
        let user = await getUser()
        scoreType = user?.mediaListOptions?.scoreFormat
        return scoreType ?? "POINT_10"
    }
}

private extension AniListApi {
    func encodeDate(_ value: Date?) -> AniListDate? {
        if let date = value {
            if date == Date(timeIntervalSince1970: 0) {
                return AniListDate(year: 0, month: 0, day: 0)
            }
            let components = Calendar.current.dateComponents([.day, .month, .year], from: date)
            return AniListDate(year: components.year, month: components.month, day: components.day)
        }
        return nil
    }

    func getStatusString(status: TrackStatus) -> String? {
        switch status {
            case .reading: return "CURRENT"
            case .planning: return "PLANNING"
            case .completed: return "COMPLETED"
            case .dropped: return "DROPPED"
            case .paused: return "PAUSED"
            case .rereading: return "REPEATING"
            default: return nil
        }
    }
}
