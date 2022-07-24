//
//  TrackUpdate.swift
//  Aidoku
//
//  Created by Skitty on 7/21/22.
//

import Foundation

/// A structure containing tracking state data to update.
struct TrackUpdate {
    /// An integer representing the rating score.
    var score: Int?
    /// The current reading status.
    var status: TrackStatus?
    /// The latest read chapter number.
    var lastReadChapter: Float?
    /// The latest read volume number.
    var lastReadVolume: Int?
    /// The date that reading began.
    var startReadDate: Date?
    /// The date that reading completed.
    var finishReadDate: Date?
}
