//
//  ZoomableScrollView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/22/21.
//
//  Copyright © 2018 Seyed Samad Gholamzadeh. All rights reserved.
//  https://github.com/ssamadgh/PhotoScroller_Completed_Sample_Code_Part_I/blob/master/PhotoScroller/ImageScrollView.swift
//

import UIKit

class ZoomableScrollView: UIScrollView {

    var zoomView: UIView! {
        didSet {
            configure()
        }
    }

    lazy var zoomingTap: UITapGestureRecognizer = {
        let zoomingTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        zoomingTap.numberOfTapsRequired = 2
        return zoomingTap
    }()

    var zoomEnabled = true {
        didSet {
            isScrollEnabled = zoomEnabled
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        delegate = self
        maximumZoomScale = 2
        minimumZoomScale = 1
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        insetsLayoutMarginsFromSafeArea = false
        contentInsetAdjustmentBehavior = .never
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        centerView()
    }

    func configure() {
        zoomView.addGestureRecognizer(zoomingTap)
        zoomView.isUserInteractionEnabled = true
    }

    func centerView() {
        let boundsSize = self.bounds.size
        var frameToCenter = zoomView?.frame ?? CGRect.zero

        // horizontal
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width)/2
        } else {
            frameToCenter.origin.x = 0
        }

        // vertical
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height)/2
        } else {
            frameToCenter.origin.y = 0
        }

        zoomView?.frame = frameToCenter
    }
}

// MARK: - Double Tap Gesture
extension ZoomableScrollView {

    @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
        guard zoomEnabled else { return }
        let location = sender.location(in: sender.view)
        zoom(to: location, animated: true)
    }

    func zoom(to point: CGPoint, animated: Bool) {
        guard zoomEnabled else { return }
        let currentScale = self.zoomScale
        let minScale = self.minimumZoomScale
        let maxScale = self.maximumZoomScale

        if minScale == maxScale && minScale > 1 {
            return
        }

        let toScale = maxScale
        let finalScale = (currentScale == minScale) ? toScale : minScale
        let zoomRect = zoomRect(for: finalScale, withCenter: point)
        zoom(to: zoomRect, animated: animated)
    }

    func zoomRect(for scale: CGFloat, withCenter center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero
        let bounds = self.bounds

        zoomRect.size.width = bounds.size.width / scale
        zoomRect.size.height = bounds.size.height / scale

        zoomRect.origin.x = center.x - (zoomRect.size.width / 2)
        zoomRect.origin.y = center.y - (zoomRect.size.height / 2)

        return zoomRect
    }
}

// MARK: - Scroll View Delegate
extension ZoomableScrollView: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomEnabled ? zoomView : nil
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerView()
    }
}
