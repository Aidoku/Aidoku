//
//  Tracker.swift
//  Aidoku
//
//  Created by Skitty on 6/14/22.
//

import Foundation

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

/// A protocol for the implementation of a Tracker.
protocol Tracker: AnyObject {
    /// A unique identification string.
    var id: String { get }
    /// The title of the tracker.
    var name: String { get }
    /// The icon of the tracker.
    var icon: UIImage? { get }
    /// An array of track statuses the tracker supports.
    var supportedStatuses: [TrackStatus] { get }
    /// The current score type for the tracker.
    var scoreType: TrackScoreType { get }
    /// An array of options paired with scores to use if score type is an option list.
    var scoreOptions: [(String, Int)] { get }

    /// A boolean indicating if the tracker is currently logged in.
    var isLoggedIn: Bool { get }

    /// Register a new tracked title.
    ///
    /// Called when a tracker is linked with a title, indicating that the title should be added to the
    /// user's database on the tracker
    ///
    /// - Parameter trackId: The identifier for a tracker item.
    func register(trackId: String)

    /// Update the state of a tracked title.
    ///
    /// Used to send the edited state of the tracked item to the tracker. Called after manually editing
    /// details as well as with automatic changes such as a more recent chapter being read.
    ///
    /// - Parameters:
    ///   - trackId: The identifier for a tracker item.
    ///   - state: The updated state for the tracker item.
    func update(trackId: String, state: TrackState)

    /// Get search results for possible tracker matches for a Manga.
    ///
    /// The corresponding Tracker's API can be searched using the title of the Manga object (or
    /// any other relevant info it contains) to collect a list of tracking items for the user to choose from.
    ///
    /// - Returns: An array of titles the user can select to register for the manga.
    ///
    /// - Parameter manga: The Manga object to find matches for.
    func search(for manga: Manga) -> [TrackSearchItem]

    /// Get the current state of a tracked title from the tracker.
    ///
    /// Used to fetch the current tracking state of a title directly from the tracker in order to
    /// display the information available to edit.
    ///
    /// - Returns: The current state of the tracker item.
    ///
    /// - Parameter trackId: The identifier for a tracker item.
    func getState(trackId: String) -> TrackState

    /// Log out from the tracker.
    func logout()
}

/// A protocol for trackers that utilize OAuth authentication.
protocol OAuthTracker: Tracker {
    /// The host in the oauth callback url, e.g. `host` in `aidoku://host`.
    var callbackHost: String { get }
    /// The URL used to authenticate with the tracker service provider.
    var authenticationUrl: String { get }
    /// The OAuth access token for the tracker.
    var token: String? { get set }

    /// A callback function called after authenticating.
    func handleAuthenticationCallback(url: URL)
}

// Default values for optional properties
extension Tracker {
    var scoreOptions: [(String, Int)] { [] }
}

extension OAuthTracker {
    var token: String? {
        get {
            UserDefaults.standard.string(forKey: "Tracker.\(id).token")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Tracker.\(id).token")
        }
    }

    var isLoggedIn: Bool {
        token != nil
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: "Tracker.\(id).token")
    }
}
