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
class MyAnimeListTracker: NSObject, OAuthTracker {

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
        if let code = url.queryParameters?["code"] {
            // TODO: get and save access token
        }
    }
}
