//
//  AniListTracker.swift
//  Aidoku
//
//  Created by Koding Dev on 19/7/2022.
//

import Foundation

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

class AniListTracker: OAuthTracker {

    let id = "anilist"
    let name = "AniList"
    let icon = UIImage(named: "anilist")

    let supportedStatuses = TrackStatus.defaultStatuses
    let scoreType: TrackScoreType = .tenPoint

    let api = AniListApi()

    let callbackHost = "myanimelist-auth"
    lazy var authenticationUrl = api.oauth.getAuthenticationUrl(response: "token") ?? ""

    func register(trackId: String) async {

    }

    func update(trackId: String, state: TrackState) async {

    }

    func getState(trackId: String) async -> TrackState {
        TrackState()
    }

    func search(for manga: Manga) async -> [TrackSearchItem] {
        let result = await api.search(query: manga.title ?? "")?.data.media
        if result == nil {
            return []
        }

        return [TrackSearchItem(
            id: String(result?.id ?? 0),
            trackerId: self.id,
            coverUrl: result?.coverImage.large,
            description: result?.description,
            status: .unknown,
            type: .manga
        )]
    }

    func handleAuthenticationCallback(url: URL) async {
        guard let params = URL(string: "\(url.formatted())?\(url.fragment ?? "")") else { return }
        if let accessToken = params.queryParameters?["access_token"] {
            let oauth = OAuthResponse(
                tokenType: params.queryParameters?["token_type"],
                refreshToken: nil,
                accessToken: accessToken,
                expiresIn: Int(params.queryParameters?["expires_in"] ?? "0")
            )

            token = oauth.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")
        }
    }

}
