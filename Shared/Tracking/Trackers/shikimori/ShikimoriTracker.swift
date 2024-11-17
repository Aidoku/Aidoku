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

class ShikimoriTracker: OAuthTracker {
    var api = ShikimoriApi()
    let callbackHost = "shikimori-auth"
    var oauthClient: OAuthClient { api.oauth }
    lazy var authenticationUrl: String = api.getAuthenticationUrl() ?? ""

    var id: String = "shikimori"
    var name: String = "Shikimori"
    var icon: UIImage? = UIImage(named: "shikimori")

    let supportedStatuses = TrackStatus.defaultStatuses
    var scoreType: TrackScoreType = .tenPoint

    func handleAuthenticationCallback(url: URL) async {
        if let authCode = url.queryParameters?["code"] {
            let oauth = await api.getAccessToken(authCode: authCode)
            token = oauth?.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")
        }
    }

    func register(trackId: String, hasReadChapters: Bool) async -> String? {
        await api.register(trackId, hasReadChapters)
    }

    func update(trackId: String, update: TrackUpdate) async {
        await api.update(trackId, update)
    }

    func getState(trackId: String) async -> TrackState {
        await api.getState(trackId)
    }

    func getUrl(trackId: String) async -> URL? {
        guard let id = await api.getMangaIdByRate(trackId: trackId) else { return nil }

        return URL(string: oauthClient.baseUrl + "mangas/\(id)")
    }

    func search(for manga: Manga) async -> [TrackSearchItem] {
        await getSearch(query: manga.title!)
    }

    func search(title: String) async -> [TrackSearchItem] {
        await getSearch(query: title)
    }
}

private extension ShikimoriTracker {
    func getSearch(query: String) async -> [TrackSearchItem] {
        guard let resp = await api.search(query: query) else { return [] }

        return resp.data.mangas.map {
            TrackSearchItem(
                id: String($0.id),
                trackerId: self.id,
                title: $0.russian,
                coverUrl: $0.poster.mini2xUrl,
                type: getMediaType(typeString: $0.kind),
                tracked: false
            )
        }
    }

    func getMediaType(typeString: String) -> MediaType {
        switch typeString {
        case "manga": return .manga
        case "novel": return .novel
        case "one_shot": return .oneShot
        case "manhwa": return .manhwa
        case "manhua": return .manhua
        default: return .unknown
        }
    }
}
