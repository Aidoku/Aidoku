//
//  AutoScrollPosition.swift
//  Aidoku
//
//  Created by skitty on 9/6/26.
//

extension ReaderSettings {
    enum AutoScrollPosition: String, SettingsValue, CaseIterable {
        case left
        case right

        var title: String {
            switch self {
                case .left: NSLocalizedString("POSITION_LEFT")
                case .right: NSLocalizedString("POSITION_RIGHT")
            }
        }
    }
}
