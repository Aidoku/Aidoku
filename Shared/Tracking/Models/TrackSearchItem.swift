//
//  TrackSearchItem.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

/// A structure containing the necessary data to be returned from a tracker search.
struct TrackSearchItem: Equatable {
    /// A unique identifier of the tracker item.
    let id: String
    /// The title of the tracker item.
    var title: String?
    /// The URL for the cover image of the tracker item.
    var coverUrl: String?
    /// The description or summary of the tracker item.
    var description: String?
    /// The publishing status of the tracker item.
    var status: PublishingStatus?
    /// The type or format of the tracker item.
    var type: MediaType?
    /// A boolean indicating if the item is currently being tracked by the user.
    var tracked: Bool
}
