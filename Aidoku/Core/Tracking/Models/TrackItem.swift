//
//  TrackItem.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

/// A structure representing a tracked title and its state.
struct TrackItem: Sendable {
    /// A unique identifier the tracker can use to identify an item.
    let id: String
    /// The tracker identifier for the item.
    let trackerId: String
    /// The manga identifier for the item.
    let mangaId: MangaIdentifier
    /// The tracker's title for the item.
    var title: String?
    /// The paired tracking state of the item.
    var state: TrackState?
    /// The chapter offset to apply for automatic tracker updates.
    var chapterOffset: Int
}
