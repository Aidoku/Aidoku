//
//  TrackState.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

/// A structure containing tracking state data.
struct TrackState {
    /// An integer representing the rating score.
    var score: Int?
    /// The current reading status.
    var status: TrackStatus?
    /// The latest read chapter number.
    var lastReadChapter: Float?
    /// The latest read volume number.
    var lastReadVolume: Int?
    /// The total amount of chapters, if available.
    var totalChapters: Int?
    /// The total amount of volumes, if available.
    var totalVolumes: Int?
    /// The date that reading began.
    var startReadDate: Date?
    /// The date that reading completed.
    var finishReadDate: Date?
}
