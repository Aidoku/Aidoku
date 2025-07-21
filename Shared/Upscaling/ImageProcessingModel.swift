//
//  ImageModel.swift
//  Aidoku
//
//  Created by Skitty on 6/25/25.
//

import CoreML

protocol ImageProcessingModel {
    init?(model: MLModel, config: [String: Any])
    func process(_ image: CGImage) async -> CGImage?
}
