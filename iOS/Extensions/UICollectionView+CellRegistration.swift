//
//  UICollectionView+CellRegistration.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/1/22.
//

import UIKit

extension UICollectionView.CellRegistration {
    var cellProvider: (UICollectionView, IndexPath, Item) -> Cell {
        { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(
                using: self,
                for: indexPath,
                item: item
            )
        }
    }
}
