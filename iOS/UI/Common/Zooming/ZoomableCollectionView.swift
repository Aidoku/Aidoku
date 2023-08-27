//
//  ZoomableCollectionView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/21/22.
//

import UIKit
import AsyncDisplayKit

class ZoomableCollectionView: ASDisplayNode {

    let collectionNode: ASCollectionNode
    let scrollNode = ASScrollNode()
    private let dummyZoomView = UIView(frame: .zero)
    let layout: UICollectionViewLayout

    private var tempGestures: [(parent: UIView, gesture: UIGestureRecognizer)] = []
    private var lastHit = Date.distantPast

    var zoomTimer: Timer?

    lazy private var zoomingTap: UITapGestureRecognizer = {
        let zoomingTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        zoomingTap.numberOfTapsRequired = 2
        return zoomingTap
    }()

    init(layout: UICollectionViewLayout) {
        self.layout = layout
        collectionNode = ASCollectionNode(collectionViewLayout: layout)
        super.init()

        automaticallyManagesSubnodes = true
        collectionNode.backgroundColor = .clear

        // remove gesture recognizers from the collection view (in order to use scroll view's)
        collectionNode.view.gestureRecognizers?.forEach {
            collectionNode.view.removeGestureRecognizer($0)
        }

        scrollNode.view.delegate = self

        // bounce not supported since it doesn't call scrollViewDidZoom
        scrollNode.view.bouncesZoom = false
        scrollNode.view.addSubview(dummyZoomView)

        dummyZoomView.addGestureRecognizer(zoomingTap)
        dummyZoomView.isUserInteractionEnabled = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASOverlayLayoutSpec(child: collectionNode, overlay: scrollNode)
    }

    override func layoutDidFinish() {
        super.layoutDidFinish()
        adjustContentSize()
    }

    func adjustContentSize() {
        let size = layout.collectionViewContentSize
        scrollNode.view.contentSize = size
        dummyZoomView.frame = CGRect(origin: .zero, size: size)
    }

    // move force touch gestures on cell nodes to scroll node and then remove on next hit
    // if the gestures aren't removed, new ones wont work
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let orig = collectionNode.hitTest(convert(point, to: collectionNode), with: event)
        if let orig = orig as? _ASDisplayView {
            if lastHit.timeIntervalSinceNow <= -0.1 {
                if !tempGestures.isEmpty {
                    tempGestures.forEach {
                        scrollNode.view.removeGestureRecognizer($0.gesture)
                        $0.parent.addGestureRecognizer($0.gesture)
                    }
                    tempGestures = []
                }
            }
            lastHit = Date()

            orig.gestureRecognizers?.forEach {
                if gestureRecognizerShouldBegin($0) {
                    tempGestures.append((orig, $0))
                    orig.removeGestureRecognizer($0)
                    scrollNode.view.addGestureRecognizer($0)
                }
            }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Scroll View Delegate
extension ZoomableCollectionView: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        collectionNode.contentOffset = scrollView.contentOffset
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // cancel double tap zoom if user starts scrolling mid zoom
        if let zoomTimer {
            zoomTimer.invalidate()
            self.zoomTimer = nil
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard
            let layout = layout as? ZoomableLayoutProtocol,
            layout.getScale() != scrollView.zoomScale
        else { return }
        layout.setScale(scrollView.zoomScale)
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
        if let zoomTimer {
            zoomTimer.invalidate()
            self.zoomTimer = nil
        }

        let location = sender.location(in: sender.view)
        let xLoc = (location.x - scrollNode.view.contentOffset.x) / scrollNode.view.bounds.width
        let yLoc = (location.y - scrollNode.view.contentOffset.y) / scrollNode.view.bounds.height
        let startY = scrollNode.view.contentOffset.y
        let startX = scrollNode.view.contentOffset.x

        let steps = 120
        let out = scrollNode.view.zoomScale > 1
        let from = scrollNode.view.zoomScale
        let to = out ? scrollNode.view.zoomScale : scrollNode.view.maximumZoomScale

        var scales: [CGFloat] = []
        var points: [CGPoint] = []

        for i in 0...steps {
            // set zoom scale
            let scale: CGFloat
            if (out && i >= steps / 2) || (!out && i < steps / 2) {
                let step = ((pow(CGFloat(out ? steps - i : i) / (CGFloat(steps) / 2), 2) / 2) * (to - 1))
                scale = 1 + step
            } else {
                let step = ((pow(CGFloat(out ? i : steps - i) / (CGFloat(steps) / 2), 2) / 2) * (to - 1))
                scale = to - step
            }
            scales.append(scale)
            // set offset
            let point: CGPoint
            if out {
                let newX = startX - (1 - (scale - 1)/(from - 1)) * startX
                point = CGPoint(x: newX, y: scrollNode.view.contentOffset.y)
            } else {
                let xStep = (scale - 1) * scrollNode.view.bounds.width
                let yStep = (scale - 1) * scrollNode.view.bounds.height
                let newX = min(max(0, 2 * xStep * xLoc - xStep / 2), xStep)
                let newY = startY + min(max(0, 2 * yStep * yLoc - yStep / 2), yStep) + (scale - 1) * startY
                point = CGPoint(x: newX, y: newY)
            }
            points.append(point)
        }

        let finalScales = scales
        let finalPoints = points

        var i = 0
        // ~300ms animation
        zoomTimer = Timer.scheduledTimer(withTimeInterval: 0.3 / Double(steps), repeats: true) { timer in
            if i > steps || !timer.isValid {
                timer.invalidate()
                return
            }
            self.scrollNode.view.zoomScale = finalScales[i]
            self.scrollViewDidZoom(self.scrollNode.view)
            if out {
                self.scrollNode.view.setContentOffset(
                    CGPoint(x: finalPoints[i].x, y: self.scrollNode.view.contentOffset.y),
                    animated: false
                )
            } else {
                self.scrollNode.view.setContentOffset(finalPoints[i], animated: false)
            }
            i += 1
        }
    }
}
