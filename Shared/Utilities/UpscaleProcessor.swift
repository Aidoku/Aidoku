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
            let model = try? await ModelManager.shared.getEnabledModel()
            guard
                let model,
                let cgImage = image.cgImage,
                let output = await model.process(cgImage)
            else {
                return image
            }
#if os(iOS) || os(tvOS)
            return await PlatformImage(cgImage: output, scale: UIScreen.main.scale, orientation: image.imageOrientation)
#else
            return PlatformImage(cgImage: output, size: .init(width: image.size.width, height: image.size.height))
#endif
        }.get()
    }
}
