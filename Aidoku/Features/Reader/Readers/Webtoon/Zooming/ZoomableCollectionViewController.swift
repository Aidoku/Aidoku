//
//  ZoomableCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/21/22.
//

import UIKit
import AsyncDisplayKit

class ZoomableCollectionViewController: BaseObservingViewController {

    let zoomView: ZoomableCollectionView

    var scrollNode: ASScrollNode {
        zoomView.scrollNode
    }
    var scrollView: UIScrollView {
        zoomView.scrollNode.view
    }
    var collectionNode: ASCollectionNode {
        zoomView.collectionNode
    }

    convenience override init() {
        self.init(layout: UICollectionViewLayout())
    }

    init(layout: UICollectionViewLayout) {
        let zoomView = ZoomableCollectionView(layout: layout)
        self.zoomView = zoomView
        super.init(node: zoomView)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        scrollView.delegate = self
        scrollView.delaysContentTouches = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollNode.isUserInteractionEnabled = true
        scrollNode.automaticallyManagesContentSize = false
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

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        zoomView.scrollViewWillBeginDragging(scrollView)
    }
}
