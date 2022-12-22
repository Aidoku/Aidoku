//
//  ZoomableCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/21/22.
//

import UIKit

class ZoomableCollectionViewController: BaseObservingViewController, UICollectionViewDelegate {

    lazy var zoomView = ZoomableCollectionView(frame: .zero, layout: makeCollectionViewLayout())

    var scrollView: UIScrollView {
        zoomView.scrollView
    }
    var collectionView: UICollectionView {
        zoomView.collectionView
    }

    override func configure() {
        collectionView.delegate = self
        scrollView.delegate = self
        scrollView.delaysContentTouches = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomView)
    }

    override func constrain() {
        NSLayoutConstraint.activate([
            zoomView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomView.leftAnchor.constraint(equalTo: view.leftAnchor),
            zoomView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
    }

    func makeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, _ in
            nil
        }
    }
}

// MARK: - Scroll View Delegate
extension ZoomableCollectionViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        zoomView.scrollViewDidScroll(scrollView)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        zoomView.scrollViewDidZoom(scrollView)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomView.viewForZooming(in: scrollView)
    }
}
