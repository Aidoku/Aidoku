//
//  BaseCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import UIKit

class BaseCollectionViewController: BaseObservingViewController, UICollectionViewDelegate {

    lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())

    override func configure() {
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.alwaysBounceVertical = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
    }

    override func constrain() {
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
    }

    func makeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, _ in
            nil
        }
    }
}
