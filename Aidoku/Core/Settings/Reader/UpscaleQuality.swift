//
//  UpscaleQuality.swift
//  Aidoku
//
//  Created by skitty on 10/6/26.
//

extension ReaderSettings {
    enum UpscaleQuality: String, SettingsValue, CaseIterable {
        case fast
        case best

        var title: String {
            switch self {
                case .fast: NSLocalizedString("UPSCALE_QUALITY_FAST")
                case .best: NSLocalizedString("UPSCALE_QUALITY_BEST")
            }
        }
    }
}
