//
//  GIFImage.swift
//  Aidoku
//
//  Created by Skitty on 6/23/25.
//

import Gifu
import SwiftUI

struct GIFImage: UIViewRepresentable {
    var image: UIImage?
    var data: Data
    var contentMode: ContentMode = .fill

    func makeUIView(context: Context) -> GIFImageView {
        let imageView = GIFImageView(frame: .zero)
        imageView.isUserInteractionEnabled = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ uiView: GIFImageView, context: Context) {
        uiView.image = image
        uiView.animate(withGIFData: data)
        uiView.contentMode = switch contentMode {
            case .fit: .scaleAspectFit
            case .fill: .scaleAspectFill
        }
    }
}
