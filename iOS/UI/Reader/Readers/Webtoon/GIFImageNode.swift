//
//  GIFImageNode.swift
//  Aidoku
//
//  Created by Skitty on 6/23/25.
//

import AsyncDisplayKit
import Gifu

class GIFImageNode: ASControlNode {
    var imageView: GIFImageView?
    var animatedData: Data?
    var storedInteraction: UIInteraction?

    override var contentMode: UIView.ContentMode {
        didSet {
            imageView?.contentMode = contentMode
        }
    }

    var image: UIImage? {
        didSet {
            Task { @MainActor in
                imageView?.image = image
            }
        }
    }

    override var isUserInteractionEnabled: Bool {
        didSet {
            imageView?.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }

    override init() {
        super.init()

        setViewBlock { [weak self] in
            let gifView = GIFImageView()
            gifView.image = self?.image
            gifView.isUserInteractionEnabled = true
            if let contentMode = self?.contentMode {
                gifView.contentMode = contentMode
            }
            if let data = self?.animatedData {
                gifView.animate(withGIFData: data)
                self?.animatedData = nil
            }
            if let interaction = self?.storedInteraction {
                gifView.addInteraction(interaction)
                self?.storedInteraction = nil
            }
            self?.imageView = gifView
            return gifView
        }
    }

    func animate(withGIFData data: Data) {
        if let imageView {
            Task { @MainActor in
                imageView.animate(withGIFData: data)
            }
        } else {
            animatedData = data
        }
    }

    func addInteraction(_ interaction: UIInteraction) {
        if let imageView {
            imageView.addInteraction(interaction)
        } else {
            storedInteraction = interaction
        }
    }
}
