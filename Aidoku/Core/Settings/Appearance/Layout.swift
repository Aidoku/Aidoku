//
//  AppearanceLayout.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

extension AppearanceSettings {
    enum Layout: String, SettingsValue, CaseIterable {
        case standard
        case compact
        case custom

        var title: String {
            switch self {
                case .standard: NSLocalizedString("STANDARD")
                case .compact: NSLocalizedString("COMPACT")
                case .custom: NSLocalizedString("CUSTOM")
            }
        }

        @MainActor
        var imageName: String {
            switch self {
                case .standard: UIDevice.current.userInterfaceIdiom == .pad ? "LayoutStandardPad" : "LayoutStandard"
                case .compact: UIDevice.current.userInterfaceIdiom == .pad ? "LayoutCompactPad" : "LayoutCompact"
                case .custom: UIDevice.current.userInterfaceIdiom == .pad ? "LayoutCustomPad" : "LayoutCustom"
            }
        }
    }
}
