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
    private let upscale: Bool
    private let downscale: Bool

    init(size: CGSize, upscale: Bool = true, downscale: Bool = true) {
        self.size = size
        self.upscale = upscale
        self.downscale = downscale
    }

    init(width: CGFloat, upscale: Bool = true, downscale: Bool = true) {
        self.size = CGSize(width: width, height: CGFloat.infinity)
        self.upscale = upscale
        self.downscale = downscale
    }

    var identifier: String {
        "com.github.Aidoku/Aidoku/downsample?s=\(size)"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        #if os(macOS)
            let targetSize = size
        #else
            let targetSize = CGSize(width: size.width * UIScreen.main.scale, height: size.height * UIScreen.main.scale)
        #endif

        guard let cgImage = image.cgImage else {
            return nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        let scaleHor = targetSize.width / imageSize.width
        let scaleVert = targetSize.height / imageSize.height
        let scale = min(scaleHor, scaleVert)

        if scale == 1 {
            return image // no need to scale
        } else if scale > 1 && !upscale {
            return image // don't want to upscale
        } else if scale < 1 && !downscale {
            return image // don't want to downscale
        }

        let size = CGSize(width: CGFloat(round(imageSize.width * scale)), height: CGFloat(round(imageSize.height * scale)))

        let isOpaque = cgImage.alphaInfo == .none || cgImage.alphaInfo == .noneSkipFirst || cgImage.alphaInfo == .noneSkipLast
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (isOpaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
        ) else {
            return image
        }

        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let output = ctx.makeImage() else {
            return image
        }

        return PlatformImage(cgImage: output, scale: UIScreen.main.scale, orientation: image.imageOrientation)
    }
}
