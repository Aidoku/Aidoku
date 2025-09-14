//
//  MultiArrayModel.swift
//  Aidoku
//
//  Created by Skitty on 6/25/25.
//

// wrapper for coreml multiarray (float buffer) models
// references:
// - https://github.com/nagadomi/nunif/tree/master/waifu2x
// - https://github.com/imxieyi/waifu2x-ios

import Accelerate
import CoreML
import MetalKit

class MultiArrayModel: ImageProcessingModel {
    private let mlmodel: MLModel
    private let inputName: String
    private let outputName: String
    private let shape: [NSNumber]
    private let blockSize: Int
    private let shrinkSize: Int
    private let scale: Int

    required init(model: MLModel, config: [String: Any]) {
        self.mlmodel = model
        self.inputName = (config["inputName"] as? String) ?? "input"
        self.outputName = (config["outputName"] as? String) ?? "output"
        self.blockSize = (config["blockSize"] as? Int) ?? 256
        self.shrinkSize = (config["shrinkSize"] as? Int) ?? 0
        self.scale = (config["scale"] as? Int) ?? 2
        if let customShape = config["shape"] as? [Int] {
            self.shape = customShape.map { NSNumber(value: $0) }
        } else {
            self.shape = [1, 3, NSNumber(value: blockSize), NSNumber(value: blockSize)]
        }
    }

    func process(_ image: CGImage) async -> CGImage? {
        let width = image.width
        let height = image.height
        let channels = 4
        let blockSize = self.blockSize - shrinkSize * 2
        let outScale = scale
        let outWidth = width * outScale
        let outHeight = height * outScale
        let outBlockSize = blockSize * outScale

        // set up pool of buffers
        let poolSize = ProcessInfo.processInfo.activeProcessorCount
        let blockAndShrink = blockSize + 2 * shrinkSize
        let channelStride = blockAndShrink * blockAndShrink
        var bufferPool: [MLMultiArray] = (0..<poolSize).compactMap { _ in
            try? MLMultiArray(shape: shape, dataType: .float32)
        }
        let bufferSemaphore = DispatchSemaphore(value: poolSize)
        let bufferPoolLock = NSLock()

        func getBuffer() -> MLMultiArray {
            bufferSemaphore.wait()
            bufferPoolLock.lock()
            let buffer = bufferPool.removeLast()
            bufferPoolLock.unlock()
            return buffer
        }

        func returnBuffer(_ buffer: MLMultiArray) {
            bufferPoolLock.lock()
            bufferPool.append(buffer)
            bufferPoolLock.unlock()
            bufferSemaphore.signal()
        }

        // expand image by the shrink size
        let expwidth = Int(image.width) + 2 * shrinkSize
        let expheight = Int(image.height) + 2 * shrinkSize
        let expanded = image.expand(shrinkSize: shrinkSize)

        // calculate image block rects
        let rects = calculateRects(width: width, height: height, blockSize: blockSize)

        // feed expanded image data into blocks of MLMultiArrays
        let multiArrayStream = AsyncStream<(Int, MLMultiArray)> { continuation in

            Task.detached {
                for (i, rect) in rects.enumerated() {
                    let x = Int(rect.origin.x)
                    let y = Int(rect.origin.y)
                    let multi = getBuffer()
                    let floatPtr = multi.dataPointer.assumingMemoryBound(to: Float32.self)
                    for yExp in y..<(y + blockAndShrink) {
                        guard yExp >= 0 else { continue }
                        for xExp in x..<(x + blockAndShrink) {
                            guard xExp >= 0 else { continue }
                            let baseIdx = (yExp - y) * blockAndShrink + (xExp - x)
                            // channel 0
                            floatPtr[baseIdx] = Float32(expanded[yExp * expwidth + xExp])
                            // channel 1
                            floatPtr[baseIdx + channelStride] = Float32(
                                expanded[yExp * expwidth + xExp + expwidth * expheight]
                            )
                            // channel 2
                            floatPtr[baseIdx + channelStride * 2] = Float32(
                                expanded[yExp * expwidth + xExp + expwidth * expheight * 2]
                            )
                        }
                    }
                    continuation.yield((i, multi))
                }
                continuation.finish()
            }
        }

        // feed image block arrays into the model
        let predictionStream = AsyncStream<(Int, MLMultiArray)> { [inputName, outputName] continuation in
            Task.detached {
                for await (i, multi) in multiArrayStream {
                    var buffer = multi
                    if let prediction = try? self.mlmodel.prediction(inputName: inputName, outputName: outputName, input: buffer) {
                        buffer = prediction
                    } else {
                        LogManager.logger.error("Failed to get output from multiarray model")
                    }
                    continuation.yield((i, buffer))
                    returnBuffer(multi)
                }
                continuation.finish()
            }
        }

        // helper to send values from [0,1] to [0,255] and clamp
        func normalizeAccelerate(
            _ src: UnsafePointer<Float32>, _ dst: UnsafeMutablePointer<UInt8>, count: Int
        ) {
            var scale: Float32 = 255
            var minVal: Float32 = 0
            var maxVal: Float32 = 255
            var tempMul = [Float32](repeating: 0, count: count)
            var tempClip = [Float32](repeating: 0, count: count)
            // multiply by 255
            vDSP_vsmul(src, 1, &scale, &tempMul, 1, vDSP_Length(count))
            // clamp to [0,255]
            vDSP_vclip(&tempMul, 1, &minVal, &maxVal, &tempClip, 1, vDSP_Length(count))
            // convert to u8
            vDSP_vfixu8(&tempClip, 1, dst, 1, vDSP_Length(count))
        }

        // process final output
        var imgData: [UInt8] = [UInt8](repeating: 0, count: outWidth * outHeight * channels)

        await withTaskGroup(of: Void.self) { group in
            for await (i, prediction) in predictionStream {
                group.addTask {
                    let rect = rects[i]
                    let originX = Int(rect.origin.x) * outScale
                    let originY = Int(rect.origin.y) * outScale
                    let dataPointer = prediction.dataPointer.assumingMemoryBound(to: Float32.self)
                    for channel in 0..<3 {
                        let channelOffset = outBlockSize * outBlockSize * channel
                        let src = dataPointer.advanced(by: channelOffset)
                        let count = outBlockSize * outBlockSize
                        // use temporary buffer for this channel's output
                        var tempBlock = [UInt8](repeating: 0, count: count)
                        normalizeAccelerate(src, &tempBlock, count: count)
                        // write to output image buffer
                        for srcY in 0..<outBlockSize {
                            for srcX in 0..<outBlockSize {
                                let destX = originX + srcX
                                let destY = originY + srcY
                                let destIndex = (destY * outWidth + destX) * channels + channel
                                let srcIndex = srcY * outBlockSize + srcX
                                guard destIndex >= 0, srcIndex >= 0 else { continue }
                                imgData[destIndex] = tempBlock[srcIndex]
                            }
                        }
                    }
                }
            }
        }

        // create final cgimage from imgData buffer
        guard
            let cfbuffer = CFDataCreate(nil, &imgData, outWidth * outHeight * channels),
            let dataProvider = CGDataProvider(data: cfbuffer)
        else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue // skip alpha
        return CGImage(
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * channels,
            bytesPerRow: outWidth * channels,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: CGColorRenderingIntent.defaultIntent
        )
    }

    // calculate the rects for the image blocks
    private func calculateRects(width: Int, height: Int, blockSize: Int) -> [CGRect] {
        var rects: [CGRect] = []
        let numW = width / blockSize
        let numH = height / blockSize
        let remW = width % blockSize
        let remH = height % blockSize

        // regular tiles
        for i in 0..<numW {
            for j in 0..<numH {
                rects.append(CGRect(x: i * blockSize, y: j * blockSize, width: blockSize, height: blockSize))
            }
        }
        // right edge
        if remW > 0 {
            for j in 0..<numH {
                rects.append(CGRect(x: width - blockSize, y: j * blockSize, width: blockSize, height: blockSize))
            }
        }
        // bottom edge
        if remH > 0 {
            for i in 0..<numW {
                rects.append(CGRect(x: i * blockSize, y: height - blockSize, width: blockSize, height: blockSize))
            }
        }
        // bottom right corner
        if remW > 0 && remH > 0 {
            rects.append(CGRect(x: width - blockSize, y: height - blockSize, width: blockSize, height: blockSize))
        }
        return rects
    }
}

private class MLInput: MLFeatureProvider {
    var input: MLMultiArray
    var featureNames: Set<String>

    func featureValue(for featureName: String) -> MLFeatureValue? {
        MLFeatureValue(multiArray: input)
    }

    init(name: String, input: MLMultiArray) {
        self.input = input
        self.featureNames = [name]
    }
}

private extension MLModel {
    func prediction(inputName: String, outputName: String, input: MLMultiArray) throws -> MLMultiArray? {
        let inputProvider = MLInput(name: inputName, input: input)
        let outFeatures = try self.prediction(from: inputProvider)
        return outFeatures.featureValue(for: outputName)?.multiArrayValue
    }
}

private extension CGImage {
    // expands image by shrinkSize and returns rgb float array
    func expand(shrinkSize: Int) -> [Float] {
        let clipEta8: Float = 0.00196078411

        let exwidth = width + 2 * shrinkSize
        let exheight = height + 2 * shrinkSize

        // extract rgba pixel data
        var u8Array = [UInt8](repeating: 0, count: width * height * 4)
        u8Array.withUnsafeMutableBytes { u8Pointer in
            let context = CGContext(
                data: u8Pointer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(
                self,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: height
                )
            )
        }

        // process main image area
        let mainW = width
        let mainH = height
        let mainOffsetX = shrinkSize
        let mainOffsetY = shrinkSize

        var arr = [Float](repeating: 0, count: 3 * exwidth * exheight)

        var rArr = [Float](repeating: 0, count: mainW * mainH)
        var gArr = [Float](repeating: 0, count: mainW * mainH)
        var bArr = [Float](repeating: 0, count: mainW * mainH)

        u8Array.withUnsafeBufferPointer { buf in
            guard let src = buf.baseAddress else { return }
            var scale: Float = 1 / 255
            var eta = clipEta8
            // red
            var tempR = [Float](repeating: 0, count: mainW * mainH)
            var tempR2 = [Float](repeating: 0, count: mainW * mainH)
            vDSP_vfltu8(src, 4, &tempR, 1, vDSP_Length(mainW * mainH))
            vDSP_vsmsa(&tempR, 1, &scale, &eta, &tempR2, 1, vDSP_Length(mainW * mainH))
            rArr = tempR2
            // green
            var tempG = [Float](repeating: 0, count: mainW * mainH)
            var tempG2 = [Float](repeating: 0, count: mainW * mainH)
            vDSP_vfltu8(src.advanced(by: 1), 4, &tempG, 1, vDSP_Length(mainW * mainH))
            vDSP_vsmsa(&tempG, 1, &scale, &eta, &tempG2, 1, vDSP_Length(mainW * mainH))
            gArr = tempG2
            // blue
            var tempB = [Float](repeating: 0, count: mainW * mainH)
            var tempB2 = [Float](repeating: 0, count: mainW * mainH)
            vDSP_vfltu8(src.advanced(by: 2), 4, &tempB, 1, vDSP_Length(mainW * mainH))
            vDSP_vsmsa(&tempB, 1, &scale, &eta, &tempB2, 1, vDSP_Length(mainW * mainH))
            bArr = tempB2
        }

        // copy to expanded array
        for channel in 0..<3 {
            let srcArr = channel == 0 ? rArr : (channel == 1 ? gArr : bArr)
            for y in 0..<mainH {
                let srcRow = y * mainW
                let dstStart = (channel * exwidth * exheight) + (mainOffsetY + y) * exwidth + mainOffsetX
                arr[dstStart..<dstStart + mainW].withUnsafeMutableBufferPointer { dstBuf in
                    srcArr[srcRow..<srcRow + mainW].withUnsafeBufferPointer { srcBuf in
                        if let srcAddress = srcBuf.baseAddress {
                            dstBuf.baseAddress?.update(from: srcAddress, count: mainW)
                        }
                    }
                }
            }
        }

        // helper to fill a region with a color
        func fillRegion(channel: Int, xRange: Range<Int>, yRange: Range<Int>, value: Float) {
            let base = channel * exwidth * exheight
            for y in yRange {
                let rowStart = base + y * exwidth
                arr.replaceSubrange(
                    rowStart + xRange.lowerBound..<rowStart + xRange.upperBound,
                    with: repeatElement(value, count: xRange.count)
                )
            }
        }

        // process sides and corners
        // top left
        let tlR = rArr[0] - clipEta8
        let tlG = gArr[0] - clipEta8
        let tlB = bArr[0] - clipEta8
        fillRegion(channel: 0, xRange: 0..<shrinkSize, yRange: 0..<shrinkSize, value: tlR)
        fillRegion(channel: 1, xRange: 0..<shrinkSize, yRange: 0..<shrinkSize, value: tlG)
        fillRegion(channel: 2, xRange: 0..<shrinkSize, yRange: 0..<shrinkSize, value: tlB)
        // top right
        let trR = rArr[mainW - 1] - clipEta8
        let trG = gArr[mainW - 1] - clipEta8
        let trB = bArr[mainW - 1] - clipEta8
        fillRegion(
            channel: 0,
            xRange: width + shrinkSize..<width + 2 * shrinkSize,
            yRange: 0..<shrinkSize, value: trR
        )
        fillRegion(
            channel: 1,
            xRange: width + shrinkSize..<width + 2 * shrinkSize,
            yRange: 0..<shrinkSize, value: trG
        )
        fillRegion(
            channel: 2,
            xRange: width + shrinkSize..<width + 2 * shrinkSize,
            yRange: 0..<shrinkSize, value: trB
        )
        // bottom left
        let blR = rArr[(mainH - 1) * mainW] - clipEta8
        let blG = gArr[(mainH - 1) * mainW] - clipEta8
        let blB = bArr[(mainH - 1) * mainW] - clipEta8
        fillRegion(
            channel: 0,
            xRange: 0..<shrinkSize,
            yRange: height + shrinkSize..<height + 2 * shrinkSize, value: blR
        )
        fillRegion(
            channel: 1,
            xRange: 0..<shrinkSize,
            yRange: height + shrinkSize..<height + 2 * shrinkSize, value: blG
        )
        fillRegion(
            channel: 2,
            xRange: 0..<shrinkSize,
            yRange: height + shrinkSize..<height + 2 * shrinkSize, value: blB
        )
        // bottom right
        let brR = rArr[mainW * mainH - 1] - clipEta8
        let brG = gArr[mainW * mainH - 1] - clipEta8
        let brB = bArr[mainW * mainH - 1] - clipEta8
        fillRegion(
            channel: 0,
            xRange: width + shrinkSize..<width + 2 * shrinkSize,
            yRange: height + shrinkSize..<height + 2 * shrinkSize, value: brR
        )
        fillRegion(
            channel: 1,
            xRange: width + shrinkSize..<width + 2 * shrinkSize,
            yRange: height + shrinkSize..<height + 2 * shrinkSize, value: brG
        )
        fillRegion(
            channel: 2,
            xRange: width + shrinkSize..<width + 2 * shrinkSize,
            yRange: height + shrinkSize..<height + 2 * shrinkSize, value: brB
        )

        // top and bottom sides
        for x in 0..<width {
            let rTop = rArr[x] - clipEta8
            let gTop = gArr[x] - clipEta8
            let bTop = bArr[x] - clipEta8
            let rBot = rArr[(mainH - 1) * mainW + x] - clipEta8
            let gBot = gArr[(mainH - 1) * mainW + x] - clipEta8
            let bBot = bArr[(mainH - 1) * mainW + x] - clipEta8
            let xx = x + shrinkSize
            fillRegion(channel: 0, xRange: xx..<xx + 1, yRange: 0..<shrinkSize, value: rTop)
            fillRegion(channel: 1, xRange: xx..<xx + 1, yRange: 0..<shrinkSize, value: gTop)
            fillRegion(channel: 2, xRange: xx..<xx + 1, yRange: 0..<shrinkSize, value: bTop)
            fillRegion(
                channel: 0,
                xRange: xx..<xx + 1,
                yRange: height + shrinkSize..<height + 2 * shrinkSize, value: rBot
            )
            fillRegion(
                channel: 1,
                xRange: xx..<xx + 1,
                yRange: height + shrinkSize..<height + 2 * shrinkSize, value: gBot
            )
            fillRegion(
                channel: 2,
                xRange: xx..<xx + 1,
                yRange: height + shrinkSize..<height + 2 * shrinkSize, value: bBot
            )
        }

        // left and right sides
        for y in 0..<height {
            let rLeft = rArr[y * mainW] - clipEta8
            let gLeft = gArr[y * mainW] - clipEta8
            let bLeft = bArr[y * mainW] - clipEta8
            let rRight = rArr[y * mainW + mainW - 1] - clipEta8
            let gRight = gArr[y * mainW + mainW - 1] - clipEta8
            let bRight = bArr[y * mainW + mainW - 1] - clipEta8
            let yy = y + shrinkSize
            fillRegion(channel: 0, xRange: 0..<shrinkSize, yRange: yy..<yy + 1, value: rLeft)
            fillRegion(channel: 1, xRange: 0..<shrinkSize, yRange: yy..<yy + 1, value: gLeft)
            fillRegion(channel: 2, xRange: 0..<shrinkSize, yRange: yy..<yy + 1, value: bLeft)
            fillRegion(
                channel: 0,
                xRange: width + shrinkSize..<width + 2 * shrinkSize,
                yRange: yy..<yy + 1, value: rRight
            )
            fillRegion(
                channel: 1,
                xRange: width + shrinkSize..<width + 2 * shrinkSize,
                yRange: yy..<yy + 1, value: gRight
            )
            fillRegion(
                channel: 2,
                xRange: width + shrinkSize..<width + 2 * shrinkSize,
                yRange: yy..<yy + 1, value: bRight
            )
        }

        return arr
    }
}
