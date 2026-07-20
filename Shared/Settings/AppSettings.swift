//
//  AppSettings.swift
//  Aidoku
//
//  Created by skitty on 7/16/26.
//

import Foundation

struct AppSettings {
    static let dictionary = DictionarySettings()

    private static var keys: [any SettingsDefault] {
        dictionary.keys
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

struct DictionarySettings {
    var keys: [any SettingsDefault] {
        [
            enable,
            lookupGesture,
            textOverlayMode,
            restrictOCRLanguages,
            restrictedOCRLanguages,
            overlayPadding,
            overlayTextScaleMultiplier,
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
    let lookupGesture = SettingsKey<LookupGesture>("Dictionary.lookupGesture", default: .singleTap)
    let textOverlayMode = SettingsKey<Bool>("Dictionary.textOverlayMode", default: false)
    let restrictOCRLanguages = SettingsKey<Bool>("Dictionary.restrictOCRLanguages", default: false)
    let restrictedOCRLanguages = SettingsKey<[String]>("Dictionary.restrictedOCRLanguages", default: [])
    let overlayPadding = SettingsKey<Double>("Dictionary.overlayPadding", default: 5)
    let overlayTextScaleMultiplier = SettingsKey<Double>("Dictionary.overlayTextScaleMultiplier", default: 1)
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
