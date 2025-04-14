//
//  ShikimoriTracker.swift
//  Aidoku
//
//  Created by Vova Lapskiy on 02.11.2024.
//

import Foundation

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

/// Shikimori tracker for Aidoku.
class ShikimoriTracker: OAuthTracker {
    let id = "shikimori"
    let name = "Shikimori"
    let icon = UIImage(named: "shikimori")

    let supportedStatuses = TrackStatus.defaultStatuses
    let scoreType: TrackScoreType = .tenPoint

    let api = ShikimoriApi()

    let callbackHost = "shikimori-auth"
    lazy var authenticationUrl: String = api.getAuthenticationUrl() ?? ""

    var oauthClient: OAuthClient { api.oauth }

    func register(trackId: String, hasReadChapters: Bool) async -> String? {
        await api.register(trackId: trackId, hasReadChapters: hasReadChapters)
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

    func search(for manga: Manga) async -> [TrackSearchItem] {
        await getSearch(query: manga.title ?? "", includeNsfw: manga.nsfw != .safe)
    }

    func search(title: String) async -> [TrackSearchItem] {
        await getSearch(query: title)
    }

    func handleAuthenticationCallback(url: URL) async {
        if let authCode = url.queryParameters?["code"] {
            let oauth = await api.getAccessToken(authCode: authCode)
            token = oauth?.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")
        }
    }
}

private extension ShikimoriTracker {
    func getSearch(query: String, includeNsfw: Bool = false) async -> [TrackSearchItem] {
        guard let result = await api.search(query: query, censored: !includeNsfw) else {
            return []
        }
        return result.data.mangas.map {
            TrackSearchItem(
                id: $0.id,
                trackerId: self.id,
                title: $0.russian ?? $0.name,
                coverUrl: $0.poster.mini2xUrl,
                type: getMediaType(typeString: $0.kind),
                tracked: false
            )
        }
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
