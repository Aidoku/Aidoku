//
//  DownloadsSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

struct DownloadsSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            compress,
            parallel,
            background,
            downloadOnlyOnWifi,
            deleteDownloadAfterReading
        ]
    }

    let compress = SettingsKey<Bool>("Downloads.compress", default: true)
    let parallel = SettingsKey<Bool>("Downloads.parallel", default: true)
    let background = SettingsKey<Bool>("Downloads.background", default: true)

    let downloadOnlyOnWifi = SettingsKey<Bool>("Library.downloadOnlyOnWifi", default: false)
    let deleteDownloadAfterReading = SettingsKey<Bool>("Library.deleteDownloadAfterReading", default: false)
}
