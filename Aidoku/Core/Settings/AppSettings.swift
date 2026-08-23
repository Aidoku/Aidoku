//
//  AppSettings.swift
//  Aidoku
//
//  Created by skitty on 7/16/26.
//

import Foundation

struct AppSettings {
    static let dictionary = DictionarySettings()
    static let flags = FlagSettings()

    private static var keys: [any SettingsDefault] {
        dictionary.keys + flags.keys
    }

    static func registerDefaults() {
        var values: [String: Any] = [:]
        for key in keys {
            guard let object = key.defaultObject else { continue }
            values[key.key] = object
        }
        UserDefaults.standard.register(defaults: values)
    }
}
