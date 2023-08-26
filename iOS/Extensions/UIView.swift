//
//  UIView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/26/22.
//

import UIKit

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self.next
        while parentResponder != nil {
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
            parentResponder = parentResponder?.next
        }
        return nil
    }

    func addOverlay(color: UIColor) {
        let overlay = UIView()
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.frame = bounds
        overlay.backgroundColor = color
        overlay.alpha = 0
        overlay.tag = color.hash
        addSubview(overlay)
    }

    func showOverlay(color: UIColor, alpha: CGFloat = 1) {
        if let overlay = viewWithTag(color.hash) {
            overlay.alpha = alpha
        }
    }

    func hideOverlay(color: UIColor) {
        if let overlay = viewWithTag(color.hash) {
            overlay.alpha = 0
        }
    }
}
