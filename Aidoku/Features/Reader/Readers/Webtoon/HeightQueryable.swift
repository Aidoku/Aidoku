//
//  HeightQueryable.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/23/23.
//

import UIKit

protocol HeightQueryable {
    func getHeight(for size: CGSize) -> CGFloat
}

extension ReaderWebtoonPageNode: HeightQueryable {
    func getHeight(for size: CGSize) -> CGFloat {
        guard size.width > 0 else { return 0 }

        let ratio = ratio ?? Self.defaultRatio

        if pillarbox && isPillarboxOrientation() {
            let percent = (100 - pillarboxAmount) / 100
            return size.width * percent * ratio
        }

        return size.width * ratio
    }
}

extension ReaderWebtoonTransitionNode: HeightQueryable {
    func getHeight(for size: CGSize) -> CGFloat {
        guard size.width > 0 else { return 0 }

        if pillarbox && isPillarboxOrientation() {
            return size.width * (100 - pillarboxAmount) / 100
        }

        return size.width
    }
}
