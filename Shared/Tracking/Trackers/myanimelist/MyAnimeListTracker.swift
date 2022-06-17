//
//  MyAnimeListTracker.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation
import AuthenticationServices

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

/// Aidoku tracker for MyAnimeList.
class MyAnimeListTracker: OAuthTracker {

    let id = "myanimelist"
    let name = "MyAnimeList"
    let icon = UIImage(named: "todo")

    let supportedStatuses = TrackStatus.defaultStatuses
    let scoreType: TrackScoreType = .tenPoint

    let api = MyAnimeListApi()

    let callbackHost = "myanimelist-auth"
    lazy var authenticationUrl = api.authenticationUrl ?? ""

    func register(trackId: String) {
    }

    func update(trackId: String, state: TrackState) {
    }

    func search(for manga: Manga) -> [TrackSearchItem] {
        []
    }

    func getState(trackId: String) -> TrackState {
        TrackState()
    }

    func handleAuthenticationCallback(url: URL) {
        if let authCode = url.queryParameters?["code"] {
            Task {
                guard let oauth = await api.getAccessToken(authCode: authCode) else { return }
                token = oauth.accessToken
                UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")
            }
        }
    }

    func logout() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "Token.\(id).token")
        UserDefaults.standard.removeObject(forKey: "Token.\(id).oauth")
    }
}
