//
//  UIImage.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/13/22.
//

import UIKit

extension UIImage {
    func sizeToFit(_ pageSize: CGSize) -> CGSize {
        guard size.height * size.width * pageSize.width * pageSize.height > 0 else { return .zero }

        let scaledHeight = size.height * (pageSize.width / size.width)
        return CGSize(width: pageSize.width, height: scaledHeight)
    }
}
