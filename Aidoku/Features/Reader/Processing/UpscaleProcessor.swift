//
//  UpscaleProcessor.swift
//  Aidoku
//
//  Created by Skitty on 6/24/25.
//

import Nuke
import UIKit
import Vision

struct UpscaleProcessor: ImageProcessing {
    var identifier: String {
        "com.github.Aidoku/Aidoku/upscale"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard let cgImage = image.cgImage else { return image }

        // ensure an upscaling model is enabled
        guard ModelManager.shared.getEnabledModelFileName() != nil else {
            return image
        }

        // ensure image is smaller than max height
        let maxHeight = UserDefaults.standard.integer(forKey: "Reader.upscaleMaxHeight")
        guard cgImage.height < maxHeight else { return image }

        return BlockingTask {
            let model: ImageProcessingModel
            do {
                guard let imageModel = try await ModelManager.shared.getEnabledModel() else {
                    throw ProcessorError.invalidModel
                }
                model = imageModel
            } catch {
                LogManager.logger.error("Unable to load enabled upscaling model: \(error)")
                return image
            }
            guard let output = await model.process(cgImage) else {
                LogManager.logger.error("Upscaling model failed to process image")
                return image
            }
            return await PlatformImage(cgImage: output, scale: UIScreen.main.scale, orientation: image.imageOrientation)
        }.get()
    }

    enum ProcessorError: Error {
        case invalidModel
    }
}
