//
//  TrackStatus.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

/// A class wrapping integer values that indicate a title's tracking status.
class TrackStatus {
    static let reading = TrackStatus(1)
    static let planning = TrackStatus(2)
    static let completed = TrackStatus(3)
    static let paused = TrackStatus(4)
    static let dropped = TrackStatus(5)
    static let rereading = TrackStatus(6)

    /// An array of the built-in track statuses.
    static let defaultStatuses = [
        TrackStatus.reading, TrackStatus.planning, TrackStatus.completed, TrackStatus.rereading, TrackStatus.paused, TrackStatus.dropped
    ]

    /// The wrapped raw value of the track status.
    var rawValue: Int

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}
