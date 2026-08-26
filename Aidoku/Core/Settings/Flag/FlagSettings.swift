//
//  FlagSettings.swift
//  Aidoku
//
//  Created by skitty on 8/18/26.
//

struct FlagSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            libraryRefreshInProgress
        ]
    }

    let libraryRefreshInProgress = SettingsKey<Bool>("Flag.libraryRefreshInProgress", default: false)
}
