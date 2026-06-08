//  KitsuApi.swift
//  Aidoku

import Foundation

struct KitsuApi {
    let oauth = OAuthClient(
        clientId: "dd031b32d2f56c990b1425efe6c42ad847c7a4c1b8c8e8e8e8e8e8e8e8e8e8e8",
        clientSecret: "",
        authUrl: "https://kitsu.io/api/oauth/token",
        tokenUrl: "https://kitsu.io/api/oauth/token",
        scope: ""
    )

    private let baseUrl = "https://kitsu.io/api/edge"

    func searchAnime(query: String) async -> KitsuSearchResponse? {
        let url = URL(string: "\(baseUrl)/anime?filter[text]=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(KitsuSearchResponse.self, from: data)
        } catch {
            return nil
        }
    }

    func getLibraryEntry(animeId: String) async -> KitsuLibraryEntry? {
        // Placeholder - would require authenticated request
        return nil
    }

    func updateLibraryEntry(animeId: String, progress: Int? = nil, status: String? = nil, rating: Int? = nil) async {
        // Placeholder - would require authenticated PATCH request
    }
}

struct KitsuSearchResponse: Codable {
    let data: [KitsuAnime]
}

struct KitsuAnime: Codable {
    let id: String
    let attributes: KitsuAnimeAttributes
}

struct KitsuAnimeAttributes: Codable {
    let canonicalTitle: String
    let synopsis: String?
    let posterImage: KitsuImage?
}

struct KitsuImage: Codable {
    let original: String?
}

struct KitsuLibraryEntry: Codable {
    let status: String?
    let progress: Int?
    let ratingTwenty: Int?
}
