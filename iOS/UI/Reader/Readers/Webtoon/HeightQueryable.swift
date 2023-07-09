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
        if pillarbox && image != nil && isPillarboxOrientation() {
            let percent = (100 - pillarboxAmount) / 100
            let height = getPillarboxHeight(percent: percent, maxWidth: UIScreen.main.bounds.width)
            return height
        } else {
            let ratio = ratio ?? Self.defaultRatio
            return UIScreen.main.bounds.width * ratio
        }
    }
}

extension ReaderWebtoonTransitionNode: HeightQueryable {
    func getHeight() -> CGFloat {
        if pillarbox && isPillarboxOrientation() {
            return UIScreen.main.bounds.width * (100 - pillarboxAmount) / 100
        } else {
            return UIScreen.main.bounds.width
        }
    }
}
