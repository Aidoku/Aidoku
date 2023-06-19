//
//  UIImage.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/13/22.
//

import UIKit
import CoreGraphics

extension UIImage {
    func sizeToFit(_ pageSize: CGSize) -> CGSize {
        guard size.height * size.width * pageSize.width * pageSize.height > 0 else { return .zero }

        let scaledHeight = size.height * (pageSize.width / size.width)
        return CGSize(width: pageSize.width, height: scaledHeight)
    }
    
    func cropWhiteBorder() -> UIImage {
            let newRect = self.cropRect
            if let imageRef = self.cgImage!.cropping(to: newRect) {
                return UIImage(cgImage: imageRef)
            }
            return self
        }

    var cropRect: CGRect {
        guard let cgImage = self.cgImage,
            let context = createARGBBitmapContextFromImage(inImage: cgImage) else {
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

                if data[Int(pixelIndex)] == 0 { continue } // crop transparent

                if data[Int(pixelIndex+1)] > 0xE0 && data[Int(pixelIndex+2)] > 0xE0 && data[Int(pixelIndex+3)] > 0xE0 { continue } // crop white

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

        let context = CGContext (data: bitmapData,
                                 width: width,
                                 height: height,
                                 bitsPerComponent: 8,      // bits per component
            bytesPerRow: bitmapBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)

        return context
    }
}
