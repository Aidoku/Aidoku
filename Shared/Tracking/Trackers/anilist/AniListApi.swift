//
//  AniListApi.swift
//  Aidoku
//
//  Created by Koding Dev on 19/7/2022.
//

import Foundation

class AniListApi {

    private let encoder = JSONEncoder()

    // Registered under Skitty's AniList account
    let oauth = OAuthClient(
        id: "anilist",
        clientId: "8912",
        baseUrl: "https://anilist.co/api/v2/oauth"
    )
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

    private func request<T: Codable, D: Encodable>(_ data: D) async -> T? {
        guard let url = URL(string: "https://graphql.anilist.co") else { return nil }
        var request = oauth.authorizedRequest(for: url)

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try? encoder.encode(data)

        return try? await URLSession.shared.object(from: request)
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
