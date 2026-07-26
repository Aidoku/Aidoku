//
//  DictionarySettings.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

import Foundation

struct DictionarySettings {
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

extension DictionarySettings {
    enum LookupGesture: String, SettingsValue, CaseIterable {
        case singleTap = "single-tap"
        case longPress = "long-press"

        var title: String {
            switch self {
                case .singleTap: NSLocalizedString("SINGLE_TAP")
                case .longPress: NSLocalizedString("LONG_PRESS")
            }
        }
    }

    enum UpdateInterval: String, SettingsValue, CaseIterable {
        case never
        case daily
        case weekly
        case monthly

        var title: String {
            switch self {
                case .never: NSLocalizedString("NEVER")
                case .daily: NSLocalizedString("DAILY")
                case .weekly: NSLocalizedString("WEEKLY")
                case .monthly: NSLocalizedString("MONTHLY")
            }
        }

        var timeInterval: TimeInterval {
            switch self {
                case .never: 0
                case .daily: 24 * 60 * 60
                case .weekly: 7 * 24 * 60 * 60
                case .monthly: 30 * 24 * 60 * 60
            }
        }
    }

    enum DisplayMode: String, SettingsValue, CaseIterable {
        case `default`
        case fullWidth

        var title: String {
            switch self {
                case .default: NSLocalizedString("DEFAULT_DISPLAY_MODE")
                case .fullWidth: NSLocalizedString("FULL_WIDTH")
            }
        }
    }
}
