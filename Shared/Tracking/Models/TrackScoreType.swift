//
//  TrackScoreType.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

/// Available scoring types for a tracker.
enum TrackScoreType {
    /// A score type where an integer value between 1 and 10 can be selected.
    case tenPoint
    /// A score type where an integer value between 1 and 100 can be selected.
    case hundredPoint
    /// A score type where a float value between 1 and 10 can be selected.
    /// Stored as an integer from 1 to 100.
    case tenPointDecimal
    /// A score type where a score value is selected from a list.
    case optionList
}
