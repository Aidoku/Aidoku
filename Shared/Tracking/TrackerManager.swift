//
//  TrackerManager.swift
//  Aidoku
//
//  Created by Skitty on 6/14/22.
//

import Foundation

/// An interface to interact with title tracking services.
class TrackerManager {
    /// The shared tracker mangaer instance.
    static let shared = TrackerManager()

    /// An instance of the MyAnimeList tracker.
    let myanimelist = MyAnimeListTracker()

    /// An array of the available trackers.
    lazy var trackers: [Tracker] = [myanimelist]

    func getTracker(id: String) -> Tracker? {
        trackers.first { $0.id == id }
    }
}
