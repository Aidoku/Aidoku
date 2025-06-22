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
import ImageIO
#endif

struct DownsampleProcessor: ImageProcessing {
    private let size: CGSize
#if os(iOS) || os(tvOS)
    @MainActor
    let scaleFactor = UIScreen.main.scale
#else
    let scaleFactor: CGFloat = 1
#endif

    @MainActor
    init(size: CGSize) {
        self.size = size
    }

    @MainActor
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

#if os(iOS) || os(tvOS)
        var data = image.pngData()
#else
        var data = image.tiffRepresentation
#endif
        if data == nil {
#if os(iOS) || os(tvOS)
            data = image.jpegData(compressionQuality: 1)
#endif
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

#if os(iOS) || os(tvOS)
        return PlatformImage(cgImage: output, scale: scaleFactor, orientation: image.imageOrientation)
#else
        return PlatformImage(cgImage: output, size: .init(width: finalSize.width, height: finalSize.height))
#endif
    }
}
