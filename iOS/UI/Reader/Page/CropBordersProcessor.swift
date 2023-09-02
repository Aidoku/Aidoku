//
//  CropBordersProcessor.swift
//  Aidoku (iOS)
//
//  Created by Axel Lopez on 20/06/2023.
//

import Foundation
import Nuke
import CoreGraphics

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

        return CGRect(x: lowX, y: lowY, width: highX - lowX, height: highY - lowY)
    }

    func createARGBBitmapContext(width: Int, height: Int) -> CGContext? {

        let bitmapBytesPerRow = width * 4

        let colorSpace = CGColorSpaceCreateDeviceRGB()

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
}
