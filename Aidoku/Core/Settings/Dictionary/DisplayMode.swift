//
//  DisplayMode.swift
//  Aidoku
//
//  Created by skitty on 8/23/26.
//

extension DictionarySettings {
    enum DisplayMode: String, SettingsValue, CaseIterable {
        case `default`
        case fullWidth

        var title: String {
            switch self {
                case .default: NSLocalizedString("DEFAULT_DISPLAY_MODE")
                case .fullWidth: NSLocalizedString("FULL_WIDTH")
            }
        }
    }
}
