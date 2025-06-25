//
//  ImageModel.swift
//  Aidoku
//
//  Created by Skitty on 6/25/25.
//

import CoreML

protocol ImageModel {
    init(model: MLModel)
    func process(_ image: CGImage) async -> CGImage?
}
