//
//  NSLocalizedString.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 4/23/22.
//

import Foundation

// falls back to english for localized strings
public func NSLocalizedString(
    _ key: String,
    tableName: String? = nil,
    bundle: Bundle = Bundle.main,
    value: String = "",
    comment: String
) -> String {
    guard
        let fallbackBundlePath = Bundle.main.path(forResource: "en", ofType: "lproj"),
        let fallbackBundle = Bundle(path: fallbackBundlePath)
    else {
        return key
    }
    let fallbackString = fallbackBundle.localizedString(forKey: key, value: comment, table: nil)
    return Bundle.main.localizedString(forKey: key, value: fallbackString, table: nil)
}
