//
//  HeightQueryable.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/23/23.
//

import UIKit

protocol HeightQueryable {
    func getHeight() -> CGFloat
}

extension ReaderWebtoonImageNode: HeightQueryable {
    func getHeight() -> CGFloat {
        let ratio: CGFloat
        if let image {
            ratio = image.size.height / image.size.width
        } else {
            ratio = Self.defaultRatio
        }
        return UIScreen.main.bounds.width * ratio
    }
}

extension ReaderWebtoonTransitionNode: HeightQueryable {
    func getHeight() -> CGFloat {
        UIScreen.main.bounds.width
    }
}
