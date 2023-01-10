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
    func register(trackId: String, hasReadChapters: Bool) async

    /// Update the state of a tracked title.
    ///
    /// Used to send state updates of the tracked item to the tracker. Called after manually editing
    /// details as well as with automatic changes such as a more recent chapter being read.
    ///
    /// - Parameters:
    ///   - trackId: The identifier for a tracker item.
    ///   - update: The update object with new state values for the tracker item.
    func update(trackId: String, update: TrackUpdate) async

    /// Get the current state of a tracked title from the tracker.
    ///
    /// Used to fetch the current tracking state of a title directly from the tracker in order to
    /// display the information available to edit.
    ///
    /// - Returns: The current state of the tracker item.
    ///
    /// - Parameter trackId: The identifier for a tracker item.
    func getState(trackId: String) async -> TrackState

    /// Get the tracker web URL for a title.
    ///
    /// - Returns: The URL for the title on the tracker website.
    ///
    /// - Parameter trackId: The identifier for a tracker item.
    func getUrl(trackId: String) async -> URL?

    /// Get search results for possible tracker matches for a Manga.
    ///
    /// The corresponding Tracker's API can be searched using the title of the Manga object (or
    /// any other relevant info it contains) to collect a list of tracking items for the user to choose from.
    ///
    /// - Returns: An array of titles the user can select to register for the manga.
    ///
    /// - Parameter manga: The Manga object to find matches for.
    func search(for manga: Manga) async -> [TrackSearchItem]

    /// Get search results for possible tracker matches for a title string.
    ///
    /// The user can specify a title to search the tracker in order to get a tracking item to choose.
    ///
    /// - Returns: An array of titles the user can select to register for the manga.
    ///
    /// - Parameter title: The title string to search with.
    func search(title: String) async -> [TrackSearchItem]

    /// Log out from the tracker.
    func logout()

    /// Get the scoreOptions option string for a specified score.
    ///
    /// - Returns: The option in scoreOptions for the specified score.
    ///
    /// - Parameter score: The score to match to a corresponding value in scoreOptions.
    func option(for score: Int) -> String?
}

// Default values for optional properties
extension Tracker {
    var scoreOptions: [(String, Int)] { [] }

    func option(for score: Int) -> String? {
        scoreOptions.first { $0.1 == score }?.0
    }
}

extension Tracker {
    /// Check if tracker is currently tracking a manga object.
    func isTracking(manga: Manga) -> Bool {
        CoreDataManager.shared.hasTrack(trackerId: id, sourceId: manga.sourceId, mangaId: manga.id)
    }
}
