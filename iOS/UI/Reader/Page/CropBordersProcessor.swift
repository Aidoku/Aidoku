//
//  CropBordersProcessor.swift
//  Aidoku (iOS)
//
//  Created by Axel Lopez on 20/06/2023.
//

import Foundation
import Nuke

#if os(iOS) || os(tvOS)
import UIKit
#else
import CoreGraphics
#endif

struct CropBordersProcessor: ImageProcessing {

    var identifier: String {
        "com.github.Aidoku/Aidoku/cropBorders"
    }

    private let whiteThreshold = 0xAA
    private let blackThreshold = 0x05

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard let cgImage = image.cgImage else { return image }

        let newRect = createCropRect(cgImage)
        if let croppedImage = cgImage.cropping(to: newRect) {
            return PlatformImage(cgImage: croppedImage)
        }
        return image
    }

    func createCropRect(_ cgImage: CGImage) -> CGRect {
        guard let context = createARGBBitmapContextFromImage(inImage: cgImage) else {
            return CGRect.zero
        }

        let height = CGFloat(cgImage.height)
        let width = CGFloat(cgImage.width)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: rect)

        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return CGRect.zero
        }

        var lowX = width
        var lowY = height
        var highX: CGFloat = 0
        var highY: CGFloat = 0
        let heightInt = Int(height)
        let widthInt = Int(width)

        // Filter through data and look for non-transparent pixels.
        for y in 0 ..< heightInt {
            let y = CGFloat(y)

            for x in 0 ..< widthInt {
                let x = CGFloat(x)
                let pixelIndex = (width * y + x) * 4 /* 4 for A, R, G, B */

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

        return CGRect(x: lowX, y: lowY, width: highX - lowX, height: highY - lowY)
    }

    func createARGBBitmapContextFromImage(inImage: CGImage) -> CGContext? {

        let width = inImage.width
        let height = inImage.height

        let bitmapBytesPerRow = width * 4
        let bitmapByteCount = bitmapBytesPerRow * height

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let bitmapData = malloc(bitmapByteCount)
        if bitmapData == nil {
            return nil
        }

        let context = CGContext(
            data: bitmapData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bitmapBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )

        return context
    }
}
