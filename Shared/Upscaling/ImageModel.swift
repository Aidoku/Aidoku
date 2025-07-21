//
//  ImageModel.swift
//  Aidoku
//
//  Created by Skitty on 6/30/25.
//

// wrapper for coreml image models

import CoreML
import CoreImage
import Vision

class ImageModel: ImageProcessingModel {
    private let model: MLModel

    required init?(model: MLModel, config: [String: Any]) {
        self.model = model
    }

    func process(_ image: CGImage) async -> CGImage? {
        guard let vnModel = try? VNCoreMLModel(for: model) else { return nil }

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        try? handler.perform([request])

        guard let result = request.results?.first as? VNPixelBufferObservation else { return nil }

        let image = CIImage(cvImageBuffer: result.pixelBuffer)

        return image.cgImage
    }
}
