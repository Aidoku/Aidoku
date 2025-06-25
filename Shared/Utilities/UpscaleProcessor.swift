//
//  UpscaleProcessor.swift
//  Aidoku
//
//  Created by Skitty on 6/24/25.
//

import Foundation
import Nuke

import Vision

#if os(iOS) || os(tvOS)
import UIKit
#else
import CoreGraphics
import ImageIO
#endif

struct UpscaleProcessor: ImageProcessing {
    var identifier: String {
        "com.github.Aidoku/Aidoku/upscale"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        BlockingTask {
            let model: ImageProcessingModel
            do {
                guard let imageModel = try await ModelManager.shared.getEnabledModel() else {
                    throw ProcessorError.missingModel
                }
                model = imageModel
            } catch {
                LogManager.logger.error("Unable to load enabled upscaling model: \(error)")
                return image
            }
            guard
                let cgImage = image.cgImage,
                let output = await model.process(cgImage)
            else {
                LogManager.logger.error("Upscaling model failed to process image")
                return image
            }
#if os(iOS) || os(tvOS)
            return await PlatformImage(cgImage: output, scale: UIScreen.main.scale, orientation: image.imageOrientation)
#else
            return PlatformImage(cgImage: output, size: .init(width: image.size.width, height: image.size.height))
#endif
        }.get()
    }

    enum ProcessorError: Error {
        case missingModel
    }
}
