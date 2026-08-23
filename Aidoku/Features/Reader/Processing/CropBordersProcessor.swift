//
//  CropBordersProcessor.swift
//  Aidoku (iOS)
//
//  Created by Axel Lopez on 20/06/2023.
//

import Foundation
import Nuke
import UIKit

struct CropBordersProcessor: ImageProcessing {

    var identifier: String {
        "com.github.Aidoku/Aidoku/cropBorders"
    }

    private let whiteThreshold = 0xAA
    private let blackThreshold = 0x05
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let downscale = 0.4

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard let cgImage = image.cgImage else { return image }

        return autoreleasepool {
            let downsampledImage = downsampleImage(image)
            guard let downsampledCGImage = downsampledImage.cgImage else { return image }
            let newRect = createCropRect(downsampledCGImage, scale: downscale)
            guard !newRect.isEmpty else { return image }

            if let croppedImage = cgImage.cropping(to: newRect) {
                return PlatformImage(cgImage: croppedImage)
            } else {
                return image
            }
        }
    }

    func createCropRect(_ cgImage: CGImage, scale: CGFloat = 1) -> CGRect {
        let height = cgImage.height
        let width = cgImage.width
        let heightFloat = CGFloat(height)
        let widthFloat = CGFloat(width)

        guard
            let context = createARGBBitmapContext(width: width, height: height),
            let data = context.data?.assumingMemoryBound(to: UInt8.self)
        else {
            return CGRect.zero
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var lowX = widthFloat
        var lowY = heightFloat
        var highX: CGFloat = 0
        var highY: CGFloat = 0

        // Filter through data and look for non-transparent pixels.
        for y in 0 ..< height {
            let y = CGFloat(y)

            for x in 0 ..< width {
                let x = CGFloat(x)
                let pixelIndex = (widthFloat * y + x) * 4 /* 4 for A, R, G, B */

                // crop transparent
                if data[Int(pixelIndex)] == 0 { continue }

                // crop white
                if
                    data[Int(pixelIndex+1)] > whiteThreshold
                    && data[Int(pixelIndex+2)] > whiteThreshold
                    && data[Int(pixelIndex+3)] > whiteThreshold
                {
                    continue
                }

                // crop black
                if
                    data[Int(pixelIndex+1)] < blackThreshold
                    && data[Int(pixelIndex+2)] < blackThreshold
                    && data[Int(pixelIndex+3)] < blackThreshold
                {
                    continue
                }

                lowX = min(x, lowX)
                highX = max(x, highX)

                lowY = min(y, lowY)
                highY = max(y, highY)
            }
        }

        return CGRect(x: lowX / scale, y: lowY / scale, width: (highX - lowX) / scale, height: (highY - lowY) / scale)
    }

    func createARGBBitmapContext(width: Int, height: Int) -> CGContext? {

        let bitmapBytesPerRow = width * 4

        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bitmapBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )

        return context
    }

    func downsampleImage(_ image: PlatformImage) -> PlatformImage {
        guard let data = image.jpegData(compressionQuality: 0) else {
            return image
        }

        let finalSize = CGSize(
            width: CGFloat(round(image.size.width * downscale)),
            height: CGFloat(round(image.size.height * downscale))
        )

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return image
        }

        let maxDimension = round(max(finalSize.width, finalSize.height))
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as [CFString: Any] as CFDictionary

        guard let output = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return image
        }

        return PlatformImage(cgImage: output, scale: 1, orientation: image.imageOrientation)
    }
}
