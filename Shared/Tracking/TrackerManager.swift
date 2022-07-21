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

    /// A boolean indicating if there is a tracker that is currently logged in.
    var hasAvailableTrackers: Bool {
        trackers.contains { $0.isLoggedIn }
    }

    /// Get the instance of the tracker with the specified id.
    func getTracker(id: String) -> Tracker? {
        trackers.first { $0.id == id }
    }
}
