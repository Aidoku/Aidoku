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
    /// The tracker identifier for the title.
    let trackerId: String
    /// The source identifier for the title.
    let sourceId: String
    /// The identifier for the title.
    let mangaId: String
    /// The paired tracking state of the title.
    var state: TrackState
}
