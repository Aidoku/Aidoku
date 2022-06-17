//
//  TrackItem.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

/// A structure that pairs a state with a tracked title.
struct TrackItem {
    /// A unique identifier the tracker can use to identify an item.
    let id: String
    /// The tracker identifier for the item.
    let trackerId: String
    /// The source identifier for the item.
    let sourceId: String
    /// The identifier for the item.
    let mangaId: String
    /// The tracker's title for the item.
    var title: String?
    /// The paired tracking state of the item.
    var state: TrackState
}
