//
//  ZoomableCollectionView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/21/22.
//

import UIKit

class ZoomableCollectionView: UIView {

    let collectionView: UICollectionView
    let scrollView: UIScrollView
    private let dummyZoomView: UIView
    let layout: UICollectionViewLayout

    lazy private var zoomingTap: UITapGestureRecognizer = {
        let zoomingTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        zoomingTap.numberOfTapsRequired = 2
        return zoomingTap
    }()

    init(frame: CGRect, layout: UICollectionViewLayout) {
        collectionView = UICollectionView(frame: frame, collectionViewLayout: layout)
        scrollView = UIScrollView(frame: frame)
        dummyZoomView = UIView(frame: .zero)

        self.layout = layout

        super.init(frame: frame)

        // remove gesture recognizers from the collection view (in order to use scroll view's)
        collectionView.gestureRecognizers?.forEach {
            collectionView.removeGestureRecognizer($0)
        }

        scrollView.delegate = self

        // bounce not supported since it doesn't call scrollViewDidZoom
        scrollView.bouncesZoom = false

        addSubview(collectionView)
        addSubview(scrollView)
        scrollView.addSubview(dummyZoomView)

        // TODO: make double tap zoom at location
//        dummyZoomView.addGestureRecognizer(zoomingTap)
//        dummyZoomView.isUserInteractionEnabled = true

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leftAnchor.constraint(equalTo: leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: rightAnchor),

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leftAnchor.constraint(equalTo: leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: rightAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        adjustContentSize()
    }

    func adjustContentSize() {
        let size = layout.collectionViewContentSize
        scrollView.contentSize = size
        dummyZoomView.frame = CGRect(origin: .zero, size: size)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if collectionView.gestureRecognizers?.contains(where: { gestureRecognizerShouldBegin($0) }) == true {
            // move force touch gestures to scroll view
            collectionView.gestureRecognizers?.forEach {
                collectionView.removeGestureRecognizer($0)
                scrollView.addGestureRecognizer($0)
            }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Scroll View Delegate
extension ZoomableCollectionView: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        collectionView.contentOffset = scrollView.contentOffset
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard
            let layout = layout as? ZoomableLayoutProtocol,
            layout.getScale() != scrollView.zoomScale
        else { return }
        layout.setScale(scrollView.zoomScale)
        collectionView.contentOffset = scrollView.contentOffset
        self.layout.invalidateLayout()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        dummyZoomView
    }
}

// MARK: - Double Tap Gesture
extension ZoomableCollectionView {

    // simulates an animated zoom
    // necessary since zoom toRect doesn't call scrollViewDidZoom
    @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
//        let location = sender.location(in: sender.view)
        Task {
            let steps = 30
            let out = scrollView.zoomScale > 1
            let to = out ? scrollView.zoomScale : scrollView.maximumZoomScale
            for i in 0...steps {
                let scale: CGFloat
                if (out && i >= steps / 2) || (!out && i < steps / 2) {
                    scale = 1 + ((pow(CGFloat(out ? steps - i : i) / (CGFloat(steps) / 2), 2) / 2) * (to - 1))
                } else {
                    scale = to - ((pow(CGFloat(out ? i : steps - i) / (CGFloat(steps) / 2), 2) / 2) * (to - 1))
                }
                scrollView.zoomScale = scale
                scrollViewDidZoom(scrollView)
                try? await Task.sleep(nanoseconds: 10 * 1000000)
            }
        }
    }
}
