//
//  ShikimoriTracker.swift
//  Aidoku
//
//  Created by Vova Lapskiy on 02.11.2024.
//

import AidokuRunner
import Foundation

/// Shikimori tracker for Aidoku.
final class ShikimoriTracker: OAuthTracker {
    let id = "shikimori"
    let name = "Shikimori"
    let icon = PlatformImage(named: "shikimori")

    let api = ShikimoriApi()

    let callbackHost = "shikimori-auth"
    var oauthClient: OAuthClient { api.oauth }

    func getTrackerInfo() -> TrackerInfo {
        .init(supportedStatuses: TrackStatus.defaultStatuses, scoreType: .tenPoint)
    }

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        await api.register(trackId: trackId, highestChapterRead: highestChapterRead, earliestReadDate: earliestReadDate)
    }

    func update(trackId: String, update: TrackUpdate) async {
        await api.update(trackId: trackId, update: update)
    }

    func getState(trackId: String) async -> TrackState {
        await api.getState(trackId)
    }

    func getUrl(trackId: String) async -> URL? {
        guard let id = await api.getMangaIdByRate(trackId: trackId) else { return nil }

        return URL(string: oauthClient.baseUrl + "/mangas/\(id)")
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async -> [TrackSearchItem] {
        await getSearch(query: manga.title, includeNsfw: includeNsfw)
    }

    func search(title: String, includeNsfw: Bool) async -> [TrackSearchItem] {
        await getSearch(query: title, includeNsfw: includeNsfw)
    }

    func getAuthenticationUrl() async -> URL? {
        await api.oauth.getAuthenticationUrl(
            responseType: "code",
            path: "/oauth/authorize",
            redirectUri: "aidoku://shikimori-auth",
            extraQueryItems: ["scope": "user_rates"]
        )
    }

    func handleAuthenticationCallback(url: URL) async {
        if let authCode = url.queryParameters?["code"] {
            let oauth = await api.getAccessToken(authCode: authCode)
            token = oauth?.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Tracker.\(id).oauth")
        }
    }
}

private extension ShikimoriTracker {
    func getSearch(query: String, includeNsfw: Bool = false) async -> [TrackSearchItem] {
        guard let result = await api.search(query: query, censored: !includeNsfw) else {
            return []
        }
        return result.data?.mangas.map {
            TrackSearchItem(
                id: $0.id,
                title: $0.russian ?? $0.name,
                coverUrl: $0.poster.mini2xUrl,
                type: getMediaType(typeString: $0.kind),
                tracked: false
            )
        } ?? []
    }

    func getMediaType(typeString: String) -> MediaType {
        switch typeString {
            case "manga": return .manga
            case "novel", "light_novel": return .novel
            case "one_shot": return .oneShot
            case "manhwa": return .manhwa
            case "manhua": return .manhua
            default: return .unknown
        }
    }
}
