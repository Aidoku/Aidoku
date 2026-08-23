//
//  LookupGesture.swift
//  Aidoku
//
//  Created by skitty on 8/23/26.
//

extension DictionarySettings {
    enum LookupGesture: String, SettingsValue, CaseIterable {
        case singleTap = "single-tap"
        case longPress = "long-press"

        var title: String {
            switch self {
                case .singleTap: NSLocalizedString("SINGLE_TAP")
                case .longPress: NSLocalizedString("LONG_PRESS")
            }
        }
    }
}
