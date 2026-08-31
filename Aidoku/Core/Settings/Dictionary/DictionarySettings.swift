//
//  DictionarySettings.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

import Foundation

struct DictionarySettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            enable,
            updateInterval,
            lastUpdate,
            lookupGesture,
            textOverlayMode,
            restrictOCRLanguages,
            restrictedOCRLanguages,
            overlayPadding,
            overlayTextScaleMultiplier,
            displayMode,
            popupWidth,
            popupHeight
        ]
    }

    let enable = SettingsKey<Bool>("Dictionary.enable", default: false, requires: {
        if #unavailable(iOS 18.0) {
            return false
        }
        return nil
    })
    let lookupGesture = SettingsKey<LookupGesture>("Dictionary.lookupGesture", default: .singleTap)
    let updateInterval = SettingsKey<UpdateInterval>("Dictionary.updateInterval", default: .never)
    let lastUpdate = SettingsKey<Date>("Dictionary.lastUpdate", default: Date.distantPast)
    let textOverlayMode = SettingsKey<Bool>("Dictionary.textOverlayMode", default: false)
    let restrictOCRLanguages = SettingsKey<Bool>("Dictionary.restrictOCRLanguages", default: false)
    let restrictedOCRLanguages = SettingsKey<[String]>("Dictionary.restrictedOCRLanguages", default: [])
    let overlayPadding = SettingsKey<Double>("Dictionary.overlayPadding", default: 5)
    let overlayTextScaleMultiplier = SettingsKey<Double>("Dictionary.overlayTextScaleMultiplier", default: 1)
    let displayMode = SettingsKey<DisplayMode>("Dictionary.displayMode", default: .default)
    let popupWidth = SettingsKey<Double>("Dictionary.popupWidth", default: 320)
    let popupHeight = SettingsKey<Double>("Dictionary.popupHeight", default: 350)

    func isReaderDoubleTapDisabled(language: String?) -> Bool {
        UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap")
            || (AppSettings.dictionary.lookupGesture.get() == .singleTap && isOCREnabled(language: language))
    }

    func isReaderQuickActionsDisabled(language: String?) -> Bool {
        UserDefaults.standard.bool(forKey: "Reader.disableQuickActions")
            || (AppSettings.dictionary.lookupGesture.get() == .longPress && isOCREnabled(language: language))
    }

    func isOCREnabled(language: String?) -> Bool {
        guard AppSettings.dictionary.enable.get() else { return false }
        guard
            let language,
            AppSettings.dictionary.restrictOCRLanguages.get()
        else {
            return true
        }
        let languages = AppSettings.dictionary.restrictedOCRLanguages.get()
        return languages.contains(language)
    }
}
