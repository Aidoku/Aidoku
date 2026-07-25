//
//  ReaderTextTheme.swift
//  Aidoku
//

import UIKit

/// Preset color themes for the text reader, similar to the Books app.
/// All themes besides `system` override the reader's user interface style.
enum ReaderTextTheme: String, CaseIterable {
    case system
    case white
    case sepia
    case paper
    case gray
    case black

    static let lightUserDefaultsKey = "Reader.textThemeLight"
    static let darkUserDefaultsKey = "Reader.textThemeDark"
    static let changeNotification = "Reader.textTheme"

    /// The active theme, selected separately for light and dark mode.
    /// Uses the window's interface style, since the reader's own style
    /// may be overridden by the active theme.
    static var current: ReaderTextTheme {
        let isDark = UIApplication.shared.firstKeyWindow?.traitCollection.userInterfaceStyle == .dark
        let key = isDark ? darkUserDefaultsKey : lightUserDefaultsKey
        return UserDefaults.standard.string(forKey: key).flatMap(ReaderTextTheme.init) ?? .system
    }

    static var background: UIColor { current.backgroundColor }
    static var text: UIColor { current.textColor }

    var title: String {
        switch self {
            case .system: NSLocalizedString("READER_BG_COLOR_SYSTEM")
            case .white: NSLocalizedString("READER_BG_COLOR_WHITE")
            case .sepia: NSLocalizedString("TEXT_THEME_SEPIA")
            case .paper: NSLocalizedString("TEXT_THEME_PAPER")
            case .gray: NSLocalizedString("TEXT_THEME_GRAY")
            case .black: NSLocalizedString("READER_BG_COLOR_BLACK")
        }
    }

    var backgroundColor: UIColor {
        switch self {
            case .system: .systemBackground
            case .white: .white
            case .sepia: UIColor(rgb: 0xFAF1E3)
            case .paper: UIColor(rgb: 0xF2F1EC)
            case .gray: UIColor(rgb: 0x414141)
            case .black: .black
        }
    }

    var textColor: UIColor {
        switch self {
            case .system: .label
            case .white: .black
            case .sepia, .paper: UIColor.black.withAlphaComponent(0.9)
            case .gray: UIColor.white.withAlphaComponent(0.9)
            case .black: .white
        }
    }

    /// The interface style the reader should take on while this theme is active.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
            case .system: .unspecified
            case .white, .sepia, .paper: .light
            case .gray, .black: .dark
        }
    }
}

private extension UIColor {
    convenience init(rgb: Int) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
