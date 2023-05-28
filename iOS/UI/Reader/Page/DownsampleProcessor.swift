//
//  DownsampleProcessor.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/17/22.
//

import Foundation
import Nuke

#if os(iOS) || os(tvOS)
import UIKit
#else
import CoreGraphics
#endif

struct DownsampleProcessor: ImageProcessing {

    private let size: CGSize
#if os(iOS) || os(tvOS)
    var scaleFactor = UIScreen.main.scale
#else
    var scaleFactor = 1
#endif

    init(size: CGSize) {
        self.size = size
    }

    init(width: CGFloat) {
        self.size = CGSize(width: width, height: CGFloat.infinity)
    }

    var identifier: String {
        "com.github.Aidoku/Aidoku/downsample?s=\(size)"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        let scaleHor = size.width / image.size.width
        let scaleVert = size.height / image.size.height
        let scale = min(scaleHor, scaleVert)

        if scale == 1 {
            return image // no need to scale
        } else if scale > 1 {
            return image // don't want to upscale
        }

        let finalSize = CGSize(
            width: CGFloat(round(image.size.width * scale)),
            height: CGFloat(round(image.size.height * scale))
        )

        var data = image.pngData()
        if data == nil {
            data = image.jpegData(compressionQuality: 1)
            if data == nil {
                return nil
            }
        }

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data! as CFData, imageSourceOptions) else {
            return nil
        }

        let maxDimension = round(max(finalSize.width, finalSize.height) * scaleFactor)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as [CFString: Any] as CFDictionary

        guard let output = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return nil
        }

        return PlatformImage(cgImage: output, scale: scaleFactor, orientation: image.imageOrientation)
    }
}
