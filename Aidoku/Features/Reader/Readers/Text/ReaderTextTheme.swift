//
//  ReaderTextTheme.swift
//  Aidoku
//

import UIKit

/// Preset color themes for the text reader, similar to the Books app.
/// Each theme has a light and dark color variant, following the interface style;
/// a separate appearance setting can pin the reader to a light or dark style.
enum ReaderTextTheme: String, CaseIterable {
    case `default`
    case sepia
    case paper
    case gray

    static let userDefaultsKey = "Reader.textTheme"
    static let appearanceUserDefaultsKey = "Reader.textAppearance"
    static let changeNotification = "Reader.textTheme"

    static var current: ReaderTextTheme {
        UserDefaults.standard.string(forKey: userDefaultsKey).flatMap(ReaderTextTheme.init) ?? .default
    }

    /// The interface style override for the reader, from the appearance setting.
    static var interfaceStyleOverride: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: appearanceUserDefaultsKey) {
            case "light": .light
            case "dark": .dark
            default: .unspecified
        }
    }

    /// The current theme's colors, pre-resolved against the appearance override
    /// (trait propagation doesn't reliably re-resolve dynamic colors in the reader).
    static var background: UIColor { resolve(current.backgroundColor) }
    static var text: UIColor { resolve(current.textColor) }

    private static func resolve(_ color: UIColor) -> UIColor {
        let style = interfaceStyleOverride
        guard style != .unspecified else { return color }
        return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    var title: String {
        switch self {
            case .default: NSLocalizedString("DEFAULT")
            case .sepia: NSLocalizedString("TEXT_THEME_SEPIA")
            case .paper: NSLocalizedString("TEXT_THEME_PAPER")
            case .gray: NSLocalizedString("TEXT_THEME_GRAY")
        }
    }

    var backgroundColor: UIColor {
        switch self {
            case .default: .systemBackground
            case .sepia: UIColor(light: 0xFAF1E3, dark: 0x3B3226)
            case .paper: UIColor(light: 0xF2F1EC, dark: 0x2E2E2B)
            case .gray: UIColor(light: 0xD1D1D6, dark: 0x414141)
        }
    }

    var textColor: UIColor {
        switch self {
            case .default: .label
            case .sepia, .paper, .gray: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.9)
                    : UIColor.black.withAlphaComponent(0.9)
            }
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

    convenience init(light: Int, dark: Int) {
        self.init { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        }
    }
}
