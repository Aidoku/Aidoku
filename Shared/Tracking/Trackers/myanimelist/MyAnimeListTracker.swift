//
//  MyAnimeListTracker.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

/// Aidoku tracker for MyAnimeList.
class MyAnimeListTracker: Tracker {

    let id = "myanimelist"
    let name = "MyAnimeList"
    let icon = UIImage(named: "todo")

    let supportedStatuses = TrackStatus.defaultStatuses
    let scoreType: TrackScoreType = .tenPoint

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
}
