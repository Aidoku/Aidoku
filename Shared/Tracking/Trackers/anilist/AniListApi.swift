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

    private func request<T: Codable>(_ data: Encodable) async -> T? {
        guard let url = URL(string: "https://graphql.anilist.co") else { return nil }
        var request = oauth.authorizedRequest(for: url)

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try? encoder.encode(data)

        return try? await URLSession.shared.object(from: request)
    }

}
