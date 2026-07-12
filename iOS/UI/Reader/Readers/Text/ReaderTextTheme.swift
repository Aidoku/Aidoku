//
//  ReaderTextTheme.swift
//  Aidoku
//

import UIKit

/// User-configurable text reader colors, with separate values for light and dark mode.
/// Falls back to the system colors when unset.
enum ReaderTextTheme {
    static let changeNotification = "Reader.textColors"
    static let userDefaultsKeys = [
        "Reader.textBackgroundColorLight",
        "Reader.textBackgroundColorDark",
        "Reader.textColorLight",
        "Reader.textColorDark"
    ]

    static var background: UIColor {
        dynamicColor(
            lightKey: "Reader.textBackgroundColorLight",
            darkKey: "Reader.textBackgroundColorDark",
            fallback: .systemBackground
        )
    }

    static var text: UIColor {
        dynamicColor(
            lightKey: "Reader.textColorLight",
            darkKey: "Reader.textColorDark",
            fallback: .label
        )
    }

    private static func dynamicColor(lightKey: String, darkKey: String, fallback: UIColor) -> UIColor {
        UIColor { traits in
            let key = traits.userInterfaceStyle == .dark ? darkKey : lightKey
            if
                let hex = UserDefaults.standard.string(forKey: key),
                let color = UIColor(hexString: hex)
            {
                return color
            }
            return fallback.resolvedColor(with: traits)
        }
    }
}

extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func component(_ value: CGFloat) -> Int {
            Int(round(min(max(value, 0), 1) * 255))
        }
        return String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }
}
