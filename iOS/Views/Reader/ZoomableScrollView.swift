//
//  ZoomableScrollView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/22/21.
//

import UIKit

class ZoomableScrollView: UIScrollView {
    
    init() {
        super.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        
        maximumZoomScale = 2
        minimumZoomScale = 1
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if let targetView = self.subviews.first {
            if zoomScale == 1 { // zoom in
                let point = recognizer.location(in: targetView)

                let scrollSize = frame.size
                let size = CGSize(width: scrollSize.width / maximumZoomScale,
                                  height: scrollSize.height / maximumZoomScale)
                let origin = CGPoint(x: point.x - size.width / 2,
                                     y: point.y - size.height / 2)
                zoom(to: CGRect(origin: origin, size: size), animated: true)
            } else { // zoom out
                zoom(to: zoomRectForScale(scale: zoomScale, center: recognizer.location(in: targetView)), animated: true)
            }
        }
    }
    
    func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero
        if let targetView = subviews.first {
            zoomRect.size.height = targetView.frame.size.height / scale
            zoomRect.size.width  = targetView.frame.size.width  / scale
            let newCenter = convert(center, from: targetView)
            zoomRect.origin.x = newCenter.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = newCenter.y - (zoomRect.size.height / 2.0)
        }
        return zoomRect
    }
    
}

extension ZoomableScrollView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return subviews.first
    }
}

