//
//  ImageProcessingSettingsKey.swift
//  Aidoku
//
//  Created by 686udjie on 26/11/2025.
//

import Foundation
import Nuke

extension UpscaleProcessor {
    static func getProcessorSettingsKey() -> String {
        let crop = UserDefaults.standard.bool(forKey: "Reader.cropBorders")
        let downsample = UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
        let upscale = UserDefaults.standard.bool(forKey: "Reader.upscaleImages")
        let maxHeight = UserDefaults.standard.integer(forKey: "Reader.upscaleMaxHeight")
        return "\(crop)-\(downsample)-\(upscale)-\(maxHeight)"
    }
}