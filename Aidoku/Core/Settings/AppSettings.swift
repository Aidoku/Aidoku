//
//  AppSettings.swift
//  Aidoku
//
//  Created by skitty on 7/16/26.
//

import Foundation

struct AppSettings {
    static let appearance = AppearanceSettings()
    static let backups = BackupsSettings()
    static let browse = BrowseSettings()
    static let dictionary = DictionarySettings()
    static let downloads = DownloadsSettings()
    static let flags = FlagSettings()
    static let general = GeneralSettings()
    static let library = LibrarySettings()
    static let reader = ReaderSettings()
    static let tracking = TrackingSettings()

    private static var keys: [any SettingsDefault] {
        appearance.keys
            + backups.keys
            + browse.keys
            + dictionary.keys
            + downloads.keys
            + flags.keys
            + general.keys
            + library.keys
            + reader.keys
            + tracking.keys
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
