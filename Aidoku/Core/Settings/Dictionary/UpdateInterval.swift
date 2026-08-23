//
//  UpdateInterval.swift
//  Aidoku
//
//  Created by skitty on 8/23/26.
//

import Foundation

extension DictionarySettings {
    enum UpdateInterval: String, SettingsValue, CaseIterable {
        case never
        case daily
        case weekly
        case monthly

        var title: String {
            switch self {
                case .never: NSLocalizedString("NEVER")
                case .daily: NSLocalizedString("DAILY")
                case .weekly: NSLocalizedString("WEEKLY")
                case .monthly: NSLocalizedString("MONTHLY")
            }
        }

        var timeInterval: TimeInterval {
            switch self {
                case .never: 0
                case .daily: 24 * 60 * 60
                case .weekly: 7 * 24 * 60 * 60
                case .monthly: 30 * 24 * 60 * 60
            }
        }
    }
}
