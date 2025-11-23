//
//  TrackerInfo.swift
//  Aidoku
//
//  Created by Skitty on 11/23/25.
//

struct TrackerInfo: Sendable {
    /// An array of track statuses the tracker supports.
    let supportedStatuses: [TrackStatus]
    /// The current score type for the tracker.
    let scoreType: TrackScoreType
    /// An array of options paired with scores to use if score type is an option list.
    var scoreOptions: [(String, Int)] = []
}
