//
//  AniListApi.swift
//  Aidoku
//
//  Created by Koding Dev on 19/7/2022.
//

import Foundation

class AniListApi {
    private let encoder = JSONEncoder()

    let oauth = OAuthClient(
        id: "anilist",
        clientId: "8912",
        base: "https://anilist.co/api/v2/oauth"
    )
}

// MARK: - Data
extension AniListApi {

    func search(query: String) async -> GraphQLResponse<AniListSearchResponse>? {
        let query = GraphQLQuery(query: searchQuery, variables: AniListSearchVars(search: query))
        return await request(query)
    }

    func getState(media: Int) async -> Media? {
        let query = GraphQLQuery(query: mediaStatusQuery, variables: AniListMediaStatusVars(id: media))
        let res: GraphQLResponse<AniListSearchResponse>? = await request(query)
        return res?.data.media
    }

    func update(media: Int, state: TrackState) async -> GraphQLResponse<AniListUpdateResponse>? {
        let progress = state.lastReadChapter == nil ? nil : Int(state.lastReadChapter!)
        let score = state.score == nil ? nil : Float(state.score!)
        let vars = AniListUpdateMediaVars(
                id: media,
                status: encodeStatus(state.status),
                progress: progress,
                volumes: state.lastReadVolume,
                score: score,
                startedAt: encodeDate(state.startReadDate),
                completedAt: encodeDate(state.finishReadDate)
        )

        let query = GraphQLQuery(query: updateMediaQuery, variables: vars)
        return await request(query)
    }

    private func request<T: Codable>(_ data: Encodable) async -> T? {
        guard let url = URL(string: "https://graphql.anilist.co") else { return nil }
        var request = oauth.authorizedRequest(for: url)

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try? encoder.encode(data)

        return try? await URLSession.shared.object(from: request)
    }

    private func encodeStatus(_ value: TrackStatus?) -> String? {
        if let value = value {
            switch value {
            case .reading: return "CURRENT"
            case .planning: return "PLANNING"
            case .completed: return "COMPLETED"
            case .dropped: return "DROPPED"
            case .paused: return "PAUSED"
            default: return nil
            }
        }
        return nil
    }

    private func encodeDate(_ value: Date?) -> AniListDate? {
        if let date = value {
            let components = Calendar.current.dateComponents([.day, .month, .year], from: date)
            return AniListDate(year: components.year, month: components.month, day: components.day)
        }
        return nil
    }
}
