//
//  NSLocalizedString.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 4/23/22.
//

import Foundation

let fallbackBundle = Bundle.main.path(forResource: "en", ofType: "lproj")
    .flatMap { Bundle(path: $0) }

// falls back to english for localized strings
func NSLocalizedString(
    _ key: String,
    tableName _: String? = nil,
    bundle _: Bundle = Bundle.main,
    value _: String = "",
    comment: String = ""
) -> String {
    guard let fallbackBundle else { return key }
    let fallbackString = fallbackBundle.localizedString(forKey: key, value: comment, table: nil)
    return Bundle.main.localizedString(forKey: key, value: fallbackString, table: nil)
}
